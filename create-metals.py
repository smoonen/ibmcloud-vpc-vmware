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

# Create vCenter VNI
vcenter_id = vpclib.create_or_retrieve_vni(inventory.mgmt_subnet_id, "smoonen-vni-vcenter", sg_id)
print("vcenter_id = '%s'" % vcenter_id)
print("vcenter_ip = '%s'" % vpclib.get_vni(vcenter_id)['ips'][0]['address'])

# Create three hosts
for host in ('host001', 'host002', 'host003') :
  # Create three VNIs; two for PCI interfaces and one for VLAN interface
  vmnic0_id = vpclib.create_or_retrieve_vni(inventory.host_subnet_id, "smoonen-vni-%s-vmnic0" % host, sg_id)
  print("%s_vmnic0_id = '%s'" % (host, vmnic0_id))
  print("%s_vmnic0_ip = '%s'" % (host, vpclib.get_vni(vmnic0_id)['ips'][0]['address']))

  vmnic1_id = vpclib.create_or_retrieve_vni(inventory.host_subnet_id, "smoonen-vni-%s-vmnic1" % host, sg_id)
  print("%s_vmnic1_id = '%s'" % (host, vmnic1_id))
  print("%s_vmnic1_ip = '%s'" % (host, vpclib.get_vni(vmnic1_id)['ips'][0]['address']))

  vmk0_id = vpclib.create_or_retrieve_vni(inventory.mgmt_subnet_id, "smoonen-vni-%s-vmk0-mgmt" % host, sg_id)
  print("%s_vmk0_mgmt_id = '%s'" % (host, vmk0_id))
  print("%s_vmk0_mgmt_ip = '%s'" % (host, vpclib.get_vni(vmk0_id)['ips'][0]['address']))

  # The following will have both a dedicated vmnic and vmknic; I've settled on vmnic for naming convention
  vmnic2_id = vpclib.create_or_retrieve_vni(inventory.vmotion_subnet_id, "smoonen-vni-%s-vmnic2-vmotion" % host, sg_id)
  print("%s_vmnic2_vmotion_id = '%s'" % (host, vmnic2_id))
  print("%s_vmnic2_vmotion_ip = '%s'" % (host, vpclib.get_vni(vmnic2_id)['ips'][0]['address']))

  vmnic3_id = vpclib.create_or_retrieve_vni(inventory.vsan_subnet_id, "smoonen-vni-%s-vmnic3-vsan" % host, sg_id)
  print("%s_vmnic3_vsan_id = '%s'" % (host, vmnic3_id))
  print("%s_vmnic3_vsan_ip = '%s'" % (host, vpclib.get_vni(vmnic3_id)['ips'][0]['address']))

  vmnic4_id = vpclib.create_or_retrieve_vni(inventory.tep_subnet_id, "smoonen-vni-%s-vmnic4-tep" % host, sg_id)
  print("%s_vmnic4_tep_id = '%s'" % (host, vmnic4_id))
  print("%s_vmnic4_tep_ip = '%s'" % (host, vpclib.get_vni(vmnic4_id)['ips'][0]['address']))

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
    'primary_network_attachment' : pci_network_attachment('vmnic0', vmnic0_id),
    'network_attachments'        : [ pci_network_attachment('vmnic1', vmnic1_id),
                                     pci_network_attachment('vmnic2', vmnic2_id),
                                     pci_network_attachment('vmnic3', vmnic3_id),
                                     pci_network_attachment('vmnic4', vmnic4_id),
                                     vlan_network_attachment('vmk0', vmk0_id, 1, False) ]
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

