from vpc_lib import VPClib
from inventory import Inventory
import sshkey_tools.keys
from cryptography.hazmat.primitives.asymmetric import padding
import base64, time

db = Inventory()
vpclib = VPClib(db.get('region'), db.get('api_key'))
zone = { 'name' : db.get('zone') }

# Find our OS image - the most recent Windows 2022 image
images = vpclib.list_images()

windows_images = list(filter(lambda x : x['operating_system']['name'] == 'windows-2022-amd64', images))
windows_images.sort(reverse = True, key = lambda x : x['created_at'])
image_id = windows_images[0]['id']

print("Create or retrieve bastion security group")
sg_rules = list(map(lambda x : { 'direction' : 'inbound', 'ip_version' : 'ipv4', 'protocol' : 'all', 'remote' : { 'address' : x } }, db.get('allowed_ips')))
sg_rules.append({ 'direction' : 'outbound', 'ip_version' : 'ipv4', 'protocol' : 'all' })
sg = vpclib.create_or_retrieve_security_group(db.get('vpc.id'), sg_rules, db.get('resource_prefix') + "-bastion-sg", db.get('security_groups.bastion_sg_id'))
db.set('security_groups.bastion_sg_id', sg['id'])

print("Create or retrieve bastion VNI")
vni = vpclib.create_or_retrieve_vni(db.get('resource_prefix') + '-bastion-vni', primary_ip = db.get('subnets.management.reservations.bastion.id'), security_group = sg['id'], vni_id = db.get('subnets.management.reservations.bastion.vni'))
db.set('subnets.management.reservations.bastion.vni', vni['id'])

print("Create or retrieve RSA key")
if db.get('rsa_key.private_key') :
  rsa_priv = sshkey_tools.keys.RsaPrivateKey.from_string(db.get('rsa_key.private_key'))
else :
  rsa_priv = sshkey_tools.keys.RsaPrivateKey.generate()
  db.set('rsa_key.private_key', rsa_priv.to_string())
key = vpclib.create_or_retrieve_key(rsa_priv.public_key.to_string(), db.get('resource_prefix') + '-rsakey', 'rsa', db.get('rsa_key.id'))
db.set('rsa_key.id', key['id'])

print("Create or retrieve virtual server instance")
vsi_model = {
  'vpc'                    : { 'id' : db.get('vpc.id') },
  'zone'                   : zone,
  'name'                   : db.get('resource_prefix') + '-bastion-vsi',
  'profile'                : { 'name' : 'bx2-2x8' },
  'image'                  : { 'id': image_id },
  'keys'                   : [ { 'id' : key['id'] } ],
  'volume_attachments'     : [ ],
  'boot_volume_attachment' : { 'volume' : {
                                 'name'     : db.get('resource_prefix') + '-bastion-bootvol',
                                 'capacity' : 100,
                                 'profile'  : { 'name' : 'general-purpose' } },
                               'delete_volume_on_instance_delete' : True },
  'primary_network_attachment' : { 'name'                      : 'eth0',
                                   'virtual_network_interface' : { 'id' : vni['id'] } },
}
vsi = vpclib.create_or_retrieve_vsi(vsi_model)
db.set('bastion.id', vsi['id'])

print("Retrieve password; wait if necessary")
init = vpclib.get_instance_initialization(vsi['id'])
while 'password' not in init :
  time.sleep(15)
  init = vpclib.get_instance_initialization(vsi['id'])

# Decrypt
password = rsa_priv.key.decrypt(base64.decodebytes(bytes(init['password']['encrypted_password'], 'ascii')), padding.PKCS1v15())
db.set('bastion.password', password.decode('ascii'))

# Note: the key object is attached to the VSI for the life of the VSI and cannot be removed at this point

print("Create or retrieve bastion public (floating) IP")
fip = vpclib.create_or_retrieve_floating_ip(vni['id'], db.get('resource_prefix') + '-bastion-fip', db.get('bastion.floating_ip.id'))
db.set('bastion.floating_ip.id', fip['id'])
db.set('bastion.floating_ip.ip', fip['address'])

