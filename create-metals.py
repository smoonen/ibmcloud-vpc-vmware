from vpc_lib import VPClib
import sshkey_tools.keys
from cryptography.hazmat.primitives.asymmetric import padding
import base64
import inventory
import sys

# Commonalities and helper methods
zone1 = { 'name' : 'eu-gb-1' }
pci_network_attachment = lambda name, vni_id : { 'name' : name, 'virtual_network_interface' : { 'id' : vni_id }, 'allowed_vlans' : [1,2,3,4,5,6,7,8,9,10], 'interface_type' : 'pci' }
vlan_network_attachment = lambda name, vni_id, vlan, allow_float : { 'name' : name, 'virtual_network_interface' : { 'id' : vni_id }, 'allow_to_float' : allow_float, 'interface_type' : 'vlan', 'vlan' : vlan }

vpclib = VPClib()

# Create RSA key
try :
  rsa_priv = sshkey_tools.keys.RsaPrivateKey.from_string(inventory.rsa_private_key)
except :
  rsa_priv = sshkey_tools.keys.RsaPrivateKey.generate()
  print("rsa_private_key = \"\"\"%s\"\"\"" % rsa_priv.to_string())
key_id = vpclib.create_or_retrieve_key(rsa_priv.public_key.to_string(), 'smoonen-rsakey', 'rsa')
print("key_id = '%s'" % key_id)

# Create intra-VPC security group
sg_rules = [ { 'direction' : 'inbound', 'ip_version' : 'ipv4', 'protocol' : 'all', 'remote' : { 'cidr_block' : '192.168.0.0/16' } },
             { 'direction' : 'outbound', 'ip_version' : 'ipv4', 'protocol' : 'all' } ]
sg_id = vpclib.create_or_retrieve_security_group(inventory.vpc_id, sg_rules, 'smoonen-sg-intravpc')
print("sg_id = '%s'" % sg_id)

# Create three hosts
for host in ('host001', 'host002', 'host003') :
  # Create three VNIs; two for PCI interfaces and one for VLAN interface
  pci1_id = vpclib.create_or_retrieve_vni(inventory.host_subnet_id, "smoonen-vni-%s-pci1" % host, sg_id)
  print("%s_pci1_id = '%s'" % (host, pci1_id))
  pci2_id = vpclib.create_or_retrieve_vni(inventory.host_subnet_id, "smoonen-vni-%s-pci2" % host, sg_id)
  print("%s_pci2_id = '%s'" % (host, pci2_id))
  vlan_id = vpclib.create_or_retrieve_vni(inventory.mgmt_subnet_id, "smoonen-vni-%s-vlan1" % host, sg_id)
  print("%s_vlan_id = '%s'" % (host, vlan_id))
  vlan_details = vpclib.get_vni(vlan_id)
  print("%s_vlan_ip = '%s'" % (host, vlan_details['ips'][0]['address']))

  # Create bare metal
  bm_model = {
    'vpc'                        : { 'id' : inventory.vpc_id },
    'zone'                       : zone1,
    'name'                       : host,
    'profile'                    : { 'name' : 'bx2d-metal-96x384' },
    'initialization'             : { 'image' : { 'id': inventory.esxi_image_id },
                                     'keys'  : [ { 'id' : key_id } ] },
    'trusted_platform_module'    : { 'mode' : 'tpm_2' },
    'enable_secure_boot'         : True,
    'primary_network_attachment' : pci_network_attachment('vmnic0', pci1_id),
    'network_attachments'        : [ pci_network_attachment('vmnic1', pci2_id),
                                     vlan_network_attachment('vmk0', vlan_id, 1, False) ]
  }
  bm_id = vpclib.create_or_retrieve_bare_metal(bm_model)
  print("%s_bm_id = '%s'" % (host, bm_id))

  # Get server initialization information
  init = vpclib.get_bare_metal_initialization(bm_id)

  if len(init['user_accounts']) == 0 :
    print("%s_password = 'unset'" % host)
  else :
    # Decrypt root password
    password = rsa_priv.key.decrypt(base64.decodebytes(bytes(init['user_accounts'][0]['encrypted_password'], 'ascii')), padding.PKCS1v15())
    print("%s_password = '%s'" % (host, password.decode('ascii')))

# Note: the key object is attached to the bare metal for the life of the server and cannot be removed at this point

# Post deployment, the ESXi vmk0 interfaces need to be re-IPed to the VLAN VNIs; as part of this the gateway IP and VLAN also need to be corrected.
# The second vmnic will be used later to bootstrap the DVS; there is no need to add it to the vSwitch in this temporary unmanaged state.

