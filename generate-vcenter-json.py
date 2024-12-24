from jinja2 import Environment, FileSystemLoader, select_autoescape
import inventory

jinja_env = Environment(loader = FileSystemLoader("templates"), autoescape = select_autoescape())

template = jinja_env.get_template("vcsa-deploy.json")
print(template.render(inventory = inventory))

