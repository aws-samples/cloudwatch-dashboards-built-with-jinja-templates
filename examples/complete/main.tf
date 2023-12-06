data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

#################################################
# VPC
#################################################

module "vpc" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-vpc.git?ref=0ea859dd659701e6e8dda61e61c47629eeda5ba3"

  name = "${local.project.name}-${local.project.env}"
  cidr = "10.99.0.0/22"

  azs             = local.global.azs
  public_subnets  = ["10.99.0.0/24", "10.99.1.0/24"]
  private_subnets = ["10.99.2.0/24", "10.99.3.0/24"]

  enable_nat_gateway      = true
  single_nat_gateway      = true
  map_public_ip_on_launch = false
  enable_dns_hostnames    = true
  tags = merge(local.global.tags,
    {
      Repository = "https://github.com/terraform-aws-modules/terraform-aws-vpc"
    },
  )
}

#################################################
# Security group
#################################################

resource "aws_security_group" "this" {
    #checkov:skip=CKV2_AWS_5: The security group is attached to resources in the main stack
  description = "Temporary security group for the CloudWatch dashboards blog demo"
  name        = "${local.project.name}-${local.project.env}"
  vpc_id      = module.vpc.vpc_id

  tags = local.global.tags
}

resource "aws_security_group_rule" "nfs_ingress" {
  security_group_id        = aws_security_group.this.id
  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.this.id
  description              = "NFS ingress within SG"
}

resource "aws_security_group_rule" "nfs_egress" {
  security_group_id        = aws_security_group.this.id
  type                     = "egress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.this.id
  description              = "NFS egress within SG"
}

resource "aws_security_group_rule" "https_egress" {
  security_group_id = aws_security_group.this.id
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTPS egress for Session Manager"
}

resource "aws_security_group_rule" "http_egress" {
  security_group_id = aws_security_group.this.id
  type              = "egress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTP egress for repositories"
}

resource "aws_security_group_rule" "dns_egress" {
  security_group_id = aws_security_group.this.id
  type              = "egress"
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  description       = "DNS egress for the Active Directory DNS servers"
}

#################################################
# EFS volume
#################################################

module "efs" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-efs.git?ref=8cdc5b65d3b92f4211271621a567e4ce6b4dc469"
  for_each = local.efs.file_systems

  name        = "${local.project.name}-${local.project.env}"
  encrypted   = true

  performance_mode                = "generalPurpose"
  throughput_mode                 = "provisioned"
  provisioned_throughput_in_mibps = 128

  lifecycle_policy = {
    transition_to_ia                    = "AFTER_30_DAYS"
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  # File system policy
  attach_policy                      = false
  bypass_policy_lockout_safety_check = false
  policy_statements = [
    {
      sid     = "Example"
      actions = ["elasticfilesystem:ClientMount"]
      principals = [
        {
          type        = "AWS"
          identifiers = [data.aws_caller_identity.current.arn]
        }
      ]
    }
  ]

  # Mount targets / security groups
  create_security_group = false

    mount_targets = [
    {
      subnet_id = element(module.vpc.private_subnets, 0)
      security_groups = [aws_security_group.this.id]
    }
  ]

  create_backup_policy = false
  enable_backup_policy = false

  tags = merge(local.global.tags,
    {
      Repository = "https://github.com/terraform-aws-modules/terraform-aws-efs"
    }
  )
}

#################################################
# IAM
#################################################

resource "aws_iam_role" "this" {
  name        = "${local.project.name}-${local.project.env}-test-controller"
  description = "Temporary role for the CloudWatch dashboards blog demo"

  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "EC2AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "ec2.${data.aws_partition.current.dns_suffix}"
          }
          Action = ["sts:AssumeRole"]
        }
      ]
    }
  )

  inline_policy {
    name = "EfsAccess"
    policy = jsonencode(
      {
        Version = "2012-10-17"
        Statement = [
          {
            Effect = "Allow"
            Action = [
              "elasticfilesystem:ClientMount",
              "elasticfilesystem:ClientWrite",
              "elasticfilesystem:DescribeMountTargets"
            ]
            Resource = "arn:${data.aws_partition.current.partition}:elasticfilesystem:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:file-system/*"
          },
          {
            Effect = "Allow"
            Action = [
              "ssm:UpdateInstanceInformation",
              "ssmmessages:CreateControlChannel",
              "ssmmessages:CreateDataChannel",
              "ssmmessages:OpenControlChannel",
              "ssmmessages:OpenDataChannel"
            ]
            Resource = "*"
          }
        ]
      }
    )
  }
  tags = local.global.tags
}

resource "aws_iam_instance_profile" "this" {
  name = "${local.project.name}-${local.project.env}-test-controller"
  role = aws_iam_role.this.name
}

#################################################
# EC2 test controller
#################################################

data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "template_cloudinit_config" "samba_server_user_data" {
  gzip          = false
  base64_encode = true

  part {
    content_type = "text/x-shellscript"
    content      = templatefile(local.test_controller.user_data_opts.path, local.test_controller.user_data_vars)
  }

}

# Deploying individual instances instead of an ASG to take advantage of simplified instance recovery with consistent IP mapping
module "test_controller" {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-ec2-instance.git?ref=6c13542c52e4ed87ca959b2027c85146e8548ac6"
  # Hidden dependencies on the EFS file systems that are referenced in the user-data
  depends_on = [
    module.efs
  ]

  name = "${local.project.name}-${local.project.env}"

  ami                    = data.aws_ami.al2.id
  ignore_ami_changes = true
  instance_type          = "t2.micro"
  subnet_id              = element(module.vpc.private_subnets, 0)
  vpc_security_group_ids = [aws_security_group.this.id]

  associate_public_ip_address = false

  maintenance_options = {
    auto_recovery = "default"
  }

  create_iam_instance_profile = false
  iam_instance_profile        = aws_iam_instance_profile.this.name

  user_data_base64 = data.template_cloudinit_config.samba_server_user_data.rendered

  enable_volume_tags = false
  root_block_device = [
    {
      delete_on_termination = true
      encrypted             = true
      volume_type           = "gp2"
      volume_size           = 1000
      tags                  = merge(local.global.tags)
    }
  ]

  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  tags = merge(local.global.tags,
    {
      Repository = "https://github.com/terraform-aws-modules/terraform-aws-ec2-instance"
    }
  )
}

