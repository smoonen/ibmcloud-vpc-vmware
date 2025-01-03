from vpc_lib import VPClib
import sshkey_tools.keys
from cryptography.hazmat.primitives.asymmetric import padding
import base64, time
import inventory

# Commonalities
zone1 = { 'name' : 'eu-gb-1' }

vpclib = VPClib()

# Find our OS image - the most recent Windows 2022 image
images = vpclib.list_images()

windows_images = list(filter(lambda x : x['operating_system']['name'] == 'windows-2022-amd64', images))
windows_images.sort(reverse = True, key = lambda x : x['created_at'])
image_id = windows_images[0]['id']

# Create security group
sg_rules = list(map(lambda x : { 'direction' : 'inbound', 'ip_version' : 'ipv4', 'protocol' : 'all', 'remote' : { 'address' : x } }, inventory.allowed_ips))
sg_rules.append({ 'direction' : 'outbound', 'ip_version' : 'ipv4', 'protocol' : 'all' })
sg = vpclib.create_or_retrieve_security_group(inventory.vpc_id, sg_rules, 'smoonen-sg-firewall')
print("sg_id = '%s'" % sg['id'])

# Create VNI
vni = vpclib.create_or_retrieve_vni(inventory.mgmt_subnet_id, 'smoonen-vni-bastion', sg['id'])
print("vni_id = '%s'" % vni['id'])
while vni['ips'][0]['address'] == '0.0.0.0' :
  time.sleep(1)
  vni = vpclib.get_vni(vni['id'])
print("vni_ip = '%s'" % vni['ips'][0]['address'])

# Create RSA key
try :
  rsa_priv = sshkey_tools.keys.RsaPrivateKey.from_string(inventory.rsa_private_key)
except :
  rsa_priv = sshkey_tools.keys.RsaPrivateKey.generate()
  print("rsa_private_key = \"\"\"%s\"\"\"" % rsa_priv.to_string())
key = vpclib.create_or_retrieve_key(rsa_priv.public_key.to_string(), 'smoonen-rsakey', 'rsa')
print("key_id = '%s'" % key['id'])

# Create virtual server instance
vsi_model = {
  'vpc'                    : { 'id' : inventory.vpc_id },
  'zone'                   : zone1,
  'name'                   : 'smoonen-vsi-bastion',
  'profile'                : { 'name' : 'bx2-2x8' },
  'image'                  : { 'id': image_id },
  'keys'                   : [ { 'id' : key['id'] } ],
  'volume_attachments'     : [ ],
  'boot_volume_attachment' : { 'volume' : {
                                 'name'     : 'smoonen-bastion-bootvol',
                                 'capacity' : 100,
                                 'profile'  : { 'name' : 'general-purpose' } },
                               'delete_volume_on_instance_delete' : True },
  'primary_network_attachment' : { 'name'                      : 'eth0',
                                   'virtual_network_interface' : { 'id' : vni['id'] } },
}
vsi = vpclib.create_or_retrieve_vsi(vsi_model)
print("vsi_id = '%s'" % vsi['id'])

# Get instance initialization information
init = vpclib.get_instance_initialization(vsi['id'])

# Decrypt Administrator password
if 'password' in init :
  password = rsa_priv.key.decrypt(base64.decodebytes(bytes(init['password']['encrypted_password'], 'ascii')), padding.PKCS1v15())
else :
  password = b'unset'
print("password = '%s'" % password.decode('ascii'))

# Note: the key object is attached to the VSI for the life of the VSI and cannot be removed at this point

# Create and attach floating IP
fip = vpclib.create_or_retrieve_floating_ip(vni['id'], 'smoonen-bastion-fip')
print("fip_id = '%s'" % fip['id'])
print("fip_ip = '%s'" % fip['address'])

