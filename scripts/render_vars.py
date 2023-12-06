import argparse
import boto3
import math
import operator
import render_template

client_elb = boto3.client("elbv2")
client_rds = boto3.client("rds")
client_efs = boto3.client("efs")
client_asg = boto3.client("autoscaling")

session = boto3.session.Session()
print(session)
region = session.region_name
print(region)

def get_args():
    arg_parser = argparse.ArgumentParser(
        description="Tool for cleaning up IAM policies and roles"
    )
    arg_parser.add_argument(
        "--tag-key",
        required=True,
        type=str,
        action="store",
        help="Tag key to use to search for resources, e.g. ProjectEnv",
    )
    arg_parser.add_argument(
        "--tag-value",
        required=True,
        type=str,
        action="store",
        help="Tag value to use to search for resources, e.g. test",
    )
    arg_parser.add_argument(
        "--template",
        required=True,
        type=str,
        action="store",
        help="Filename of the template in the templates/ directory (e.g. dashboards.vars.jinja) that will be rendered to a .json file (e.g. dashboards.vars.json) in the specified directory",
    )
    arg_parser.add_argument(
        "--rendered-file",
        required=True,
        type=str,
        action="store",
        help="Complete path and filename for rendered output (e.g. cloudformation/dashboards.yaml)",
    )
    args = arg_parser.parse_args()
    return args


def get_elb_tags(elb_arn):
    elb_tags = client_elb.describe_tags(ResourceArns=[elb_arn]).get("TagDescriptions")[
        0
    ]["Tags"]
    return elb_tags


def select_resource_by_tag(tags, tag_key, tag_value):
    for tag in tags:
        if tag["Key"] == tag_key and tag["Value"] == tag_value:
            # print(f"Key = {tag['Key']} and Value = {tag['Value']}")
            select = True
            return select


def get_widget_width(service, resources):
    count = len(resources)
    if count > 0:
        widget_width = math.floor(24 / count)
    else:
        widget_width = 24
    return widget_width


def get_efs_fs(tag_key, tag_value):
    efs_fs_all = client_efs.describe_file_systems().get("FileSystems")
    efs_fs_filtered = []
    for efs in efs_fs_all:
        efs_tags = efs.get("Tags")
        select = select_resource_by_tag(efs_tags, tag_key, tag_value)
        if select == True:
            efs_dict = {
                "file_system_id": efs.get("FileSystemId"),
                "name": efs.get("Name")
            }
            efs_fs_filtered.append(efs_dict)
    efs_fs_filtered.sort(key=operator.itemgetter('name'))
    widget_width = get_widget_width("efs", efs_fs_filtered)
    efs_fs = {
        "efs_fs": efs_fs_filtered,
        "widget_width": widget_width
    }
    return efs_fs


def main():
    args = get_args()
    efs_fs = get_efs_fs(args.tag_key, args.tag_value)
    results_dict = {"region": region, "tag_key": args.tag_key, "tag_value": args.tag_value, "efs": efs_fs}
    print(results_dict)
    render_template.render_template(
        template=args.template,
        template_vars=results_dict,
        rendered_file=args.rendered_file,
    )


if __name__ == "__main__":
    main()