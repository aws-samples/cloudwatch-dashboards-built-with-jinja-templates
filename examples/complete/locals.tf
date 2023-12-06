locals {

  project = {
    name = "cw-dash"
    env  = "demo"
  }

  global = {
    azs = slice(data.aws_availability_zones.available.names, 0, 2)
    tags = {
      Application = local.project.name
      ProjectEnv  = local.project.env
    }
  }

  downloads = {
    amazon_efs_utils = {
      aws     = "https://github.com/aws/efs-utils"
      aws-iso = "https://s3.us-iso-east-1.c2s.ic.gov/s3-efs-utils-mvp-prod-us-iso-east-1/linux/efs-utils.tar.gz"
    }
  }

    efs = {
    file_systems = {
      fs1 = {
        ec2_mount_directory = "/mnt/efs1"
      },
      fs2 = {
        ec2_mount_directory = "/mnt/efs2"
      },
    }
  }
  test_controller = {
    user_data_opts = {
      path                  = "../../scripts/user-data.tftpl"
      write_rendered_output = true
    }
    user_data_vars = {
      enable_log                    = true # Set to true and a log of the user data for development and troubleshooting will be created in /var/log/user-data.log. Set to false if you add or retrieve secrets that may be exposed; the standard user data log can be found in /var/log/cloud-init-output.log.
      efs_file_systems              = local.efs.file_systems
      efs_file_system_ids           = tomap({ for fs_id, fs in module.efs : fs_id => fs.id })
      efs_mount_point               = "/"
      region                        = data.aws_region.current.name
      proxy_url                     = ""
      no_proxy_list                 = ""
      amazon_efs_utils_download_url = lookup(local.downloads.amazon_efs_utils, data.aws_partition.current.partition)
    }
  }

}