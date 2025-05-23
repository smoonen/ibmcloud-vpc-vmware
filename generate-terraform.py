from jinja2 import Environment, FileSystemLoader, select_autoescape
from inventory import Inventory

db = Inventory()

jinja_env = Environment(loader = FileSystemLoader("templates"), autoescape = select_autoescape())

template = jinja_env.get_template("variables.tf")
print(template.render(inventory = db.data))

