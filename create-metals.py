from vpc_lib import VPClib
import sshkey_tools.keys
from cryptography.hazmat.primitives.asymmetric import padding
import base64, time
import inventory

# Commonalities and helper methods
zone1 = { 'name' : 'eu-gb-1' }
pci_network_attachment = lambda name, vni_id, allowed_vlans = [] : { 'name' : name, 'virtual_network_interface' : { 'id' : vni_id }, 'interface_type' : 'pci', 'allowed_vlans' : allowed_vlans }
vlan_network_attachment = lambda name, vni_id, vlan, allow_float : { 'name' : name, 'virtual_network_interface' : { 'id' : vni_id }, 'allow_to_float' : allow_float, 'interface_type' : 'vlan', 'vlan' : vlan }

vpclib = VPClib()

# Collect inventory for PowerCLI
ps_vars = "$hosts = @(\n"

# Create RSA key
try :
  rsa_priv = sshkey_tools.keys.RsaPrivateKey.from_string(inventory.rsa_private_key)
except :
  rsa_priv = sshkey_tools.keys.RsaPrivateKey.generate()
  print("rsa_private_key = \"\"\"%s\"\"\"" % rsa_priv.to_string())
key = vpclib.create_or_retrieve_key(rsa_priv.public_key.to_string(), 'smoonen-rsakey', 'rsa')
print("key_id = '%s'" % key['id'])

# Create intra-VPC security group
sg_rules = [ { 'direction' : 'inbound', 'ip_version' : 'ipv4', 'protocol' : 'all', 'remote' : { 'cidr_block' : '192.168.0.0/16' } },
             { 'direction' : 'outbound', 'ip_version' : 'ipv4', 'protocol' : 'all' } ]
sg = vpclib.create_or_retrieve_security_group(inventory.vpc_id, sg_rules, 'smoonen-sg-intravpc')
print("sg_id = '%s'" % sg['id'])

# Create vCenter VNI
vcenter = vpclib.create_or_retrieve_vni(inventory.mgmt_subnet_id, "smoonen-vni-vcenter", sg['id'])
print("vcenter_id = '%s'" % vcenter['id'])
while vcenter['ips'][0]['address'] == '0.0.0.0' :
  time.sleep(1)
  vcenter = vpclib.get_vni(vcenter['id'])
print("vcenter_ip = '%s'" % vcenter['ips'][0]['address'])

# Create three hosts
for host in ('host001', 'host002', 'host003') :
  # Create the VNIs for PCI / vmnic

  # vmnic0 - management; this is the only vmnic whose IP address is used, for bootstrapping purposes
  # This is also the only vmnic where we will initially set allowed VLANS (below), to [2]
  vmnic0 = vpclib.create_or_retrieve_vni(inventory.host_subnet_id, "smoonen-vni-%s-vmnic0" % host, sg['id'])
  print("%s_vmnic0_id = '%s'" % (host, vmnic0['id']))
  while vmnic0['ips'][0]['address'] == '0.0.0.0' :
    time.sleep(1)
    vmnic0 = vpclib.get_vni(vmnic0['id'])
  print("%s_vmnic0_ip = '%s'" % (host, vmnic0['ips'][0]['address']))

  # The remaining vmnics are used for vMotion, vSAN, TEPs, and uplinks.
  # However, the order in which they are consumed by ESXi is unpredictable.
  # You should not expect that the PCI index (1-4) matches the vmnic index, and therefore we cannot set allowed VLANs yet.
  additional_networks = []
  for x in range(1, 5) :
    vni = vpclib.create_or_retrieve_vni(inventory.host_subnet_id, "smoonen-vni-%s-pci%d" % (host, x), sg['id'])
    print("%s_pci%d_id = '%s'" % (host, x, vni['id']))
    additional_networks.append(pci_network_attachment('pci%d' % x, vni['id']))

  # Create the VNIs for VLAN / vmknic
  # Note that we are leaving TEP and uplink management for later.
  # Because we aren't assigning most allowed VLANs at this time, we won't be able to attach the vMotion and vSAN VNIs. We will create them now but save attachment for later.
  vmk_models = ( { 'name' : 'vmk1', 'purpose' : 'mgmt', 'vlan' : 2, 'float' : False, 'attach' : True },
                 { 'name' : 'vmk0', 'purpose' : 'vmotion', 'attach' : False },
                 { 'name' : 'vmk2', 'purpose' : 'vsan', 'attach' : False } )
  for vmk_model in vmk_models :
    vni = vpclib.create_or_retrieve_vni(getattr(inventory, vmk_model['purpose'] + '_subnet_id'), "smoonen-vni-%s-%s-%s" % (host, vmk_model['name'], vmk_model['purpose']), sg['id'])
    while vni['ips'][0]['address'] == '0.0.0.0' :
      time.sleep(1)
      vni = vpclib.get_vni(vni['id'])
    print("%s_%s_%s_ip = '%s'" % (host, vmk_model['name'], vmk_model['purpose'], vni['ips'][0]['address']))
    if vmk_model['attach'] :
      additional_networks.append(vlan_network_attachment(vmk_model['name'], vni['id'], vmk_model['vlan'], vmk_model['float']))
      vmk1_ip = vni['ips'][0]['address']

  # Add vCenter to first host
  if host == 'host001' :
    additional_networks.append(vlan_network_attachment('vcenter', vcenter['id'], 2, True))

  # Create bare metal
  bm_model = {
    'vpc'                        : { 'id' : inventory.vpc_id },
    'zone'                       : zone1,
    'name'                       : host,
    'profile'                    : { 'name' : 'bx2d-metal-96x384' },
    'initialization'             : { 'image' : { 'id': inventory.esxi_image_id },
                                     'keys'  : [ { 'id' : key['id'] } ] },
    'trusted_platform_module'    : { 'mode' : 'tpm_2' },
    'enable_secure_boot'         : True,
    'primary_network_attachment' : pci_network_attachment('vmnic0', vmnic0['id'], [2]),
    'network_attachments'        : additional_networks
  }
  bm = vpclib.create_or_retrieve_bare_metal(bm_model)
  print("%s_bm_id = '%s'" % (host, bm['id']))

  # Get server initialization information
  init = vpclib.get_bare_metal_initialization(bm['id'])

  if len(init['user_accounts']) == 0 :
    password = 'unset'
    print("%s_password = 'unset'" % host)
  else :
    # Decrypt root password
    password = rsa_priv.key.decrypt(base64.decodebytes(bytes(init['user_accounts'][0]['encrypted_password'], 'ascii')), padding.PKCS1v15()).decode('ascii')
    print("%s_password = '%s'" % (host, password))

  ps_vars += "@{ name = '%s'; pci = '%s'; vlan = '%s'; password = '%s' }\n" % (host, vmnic0['ips'][0]['address'], vmk1_ip, password)

# Note: the key object is attached to the bare metal for the life of the server and cannot be removed at this point

# Post deployment, the ESXi vmk0 interfaces need to be re-IPed to the VLAN VNIs; as part of this the gateway IP and VLAN also need to be corrected.
# The second vmnic will be used later to bootstrap the DVS; there is no need to add it to the vSwitch in this temporary unmanaged state.

print("\nPowershell variables")
print(ps_vars + ")")

