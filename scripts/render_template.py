import argparse
from jinja2 import Environment, FileSystemLoader, select_autoescape
import json
import os


def get_args():
    arg_parser = argparse.ArgumentParser(
        description="Tool for cleaning up IAM policies and roles"
    )
    arg_parser.add_argument(
        "--template",
        required=True,
        type=str,
        action="store",
        help="Filename of the template in the templates/ directory to render",
    )
    arg_parser.add_argument(
        "--template-vars",
        required=True,
        type=str,
        action="store",
        help="Path to json file containing information about resources and properties for the dashboards to be included in the rendered CloudFormation or Terraform template.",
    )
    arg_parser.add_argument(
        "--rendered-file",
        required=True,
        type=str,
        action="store",
        help="Complete path and filename for rendered output file.",
    )
    args = arg_parser.parse_args()
    return args


def render_template(template, template_vars, rendered_file):
    environment = Environment(loader=FileSystemLoader(["./templates/"]), autoescape=select_autoescape()) # update this list with additional directories containing templates as needed
    template = environment.get_template(template)
    body = template.render(template_vars=template_vars)
    os.makedirs(os.path.dirname(rendered_file), exist_ok=True)
    with open(rendered_file, mode="w", encoding="utf-8") as message:
        message.write(body)
    return ()


def main():
    args = get_args()
    with open(args.template_vars) as f:
        template_vars_js = f.read()
    template_vars = json.loads(template_vars_js)
    render_template(
        template=args.template,
        template_vars=template_vars,
        rendered_file=args.rendered_file,
    )


if __name__ == "__main__":
    main()
