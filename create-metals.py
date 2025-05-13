from vpc_lib import VPClib
from inventory import Inventory
import sshkey_tools.keys
from cryptography.hazmat.primitives.asymmetric import padding
import base64, time

db = Inventory()
vpclib = VPClib(db.get('region'), db.get('api_key'))
zone = { 'name' : db.get('zone') }

# Helper methods
pci_network_attachment = lambda name, vni_id, allowed_vlans = [] : { 'name' : name, 'virtual_network_interface' : { 'id' : vni_id }, 'interface_type' : 'pci', 'allowed_vlans' : allowed_vlans }
vlan_network_attachment = lambda name, vni_id, vlan, allow_float : { 'name' : name, 'virtual_network_interface' : { 'id' : vni_id }, 'allow_to_float' : allow_float, 'interface_type' : 'vlan', 'vlan' : vlan }

print("Create or retrieve RSA key")
if db.get('rsa_key.private_key') :
  rsa_priv = sshkey_tools.keys.RsaPrivateKey.from_string(db.get('rsa_key.private_key'))
else :
  rsa_priv = sshkey_tools.keys.RsaPrivateKey.generate()
  db.set('rsa_key.private_key', rsa_priv.to_string())
key = vpclib.create_or_retrieve_key(rsa_priv.public_key.to_string(), db.get('resource_prefix') + '-rsakey', 'rsa', db.get('rsa_key.id'))
db.set('rsa_key.id', key['id'])

print("Create or retrieve intra-VPC security group")
sg_rules = [ { 'direction' : 'outbound', 'ip_version' : 'ipv4', 'protocol' : 'all' } ]
for network in db.get('subnets') :
  sg_rules.append({ 'direction' : 'inbound', 'ip_version' : 'ipv4', 'protocol' : 'all', 'remote' : { 'cidr_block' : db.get("subnets.%s.cidr" % network) } })
sg = vpclib.create_or_retrieve_security_group(db.get('vpc.id'), sg_rules, db.get('resource_prefix') + '-intravpc-sg', db.get('security_groups.intravpc_sg_id'))
db.set('security_groups.intravpc_sg_id', sg['id'])

print("Create or retrieve all VNIs")
# We ultimately need a VNI for every IP we have already reserved.
# At this point we have created one for the bastion but not for anything else.
# Use the database as our master plan for VNI creation (excluding overlay networks).
for network in db.get('subnets') :
  if 'overlay' not in network :
    for ip in db.get("subnets.%s.reservations" % network) :
      if db.get("subnets.%s.reservations.%s.vni" % (network, ip)) is None :
        vni = vpclib.create_or_retrieve_vni("%s-%s-%s-vni" % (db.get('resource_prefix'), network, ip), primary_ip = db.get("subnets.%s.reservations.%s.id" % (network, ip)), security_group = sg['id'], vni_id = db.get("subnets.%s.reservations.%s.vni" % (network, ip)))
        db.set("subnets.%s.reservations.%s.vni" % (network, ip), vni['id'])

print("Create or retrieve bare metal servers")
for host in ('host001', 'host002', 'host003') :
  # The primary network attachment is the host's management PCI interface; we will temporarily access the host using this IP
  primary_network_attachment = pci_network_attachment('vmnic0', db.get("subnets.pci.reservations.%s-management.vni" % host), [db.get('vlans.management')])

  # The additional PCI interfaces are part of our additional attachments
  # Since we don't know the order in which they will be assigned, we cannot yet initialize their allowed VLAN list
  # Nor can we attach the VLAN VNIs that will be used for them
  additional_networks = []
  counter = 1
  for network in ('vmotion', 'vsan', 'tep', 'uplink') :
    additional_networks.append(pci_network_attachment("pci%d" % counter, db.get("subnets.pci.reservations.%s-%s.vni" % (host, network))))
    counter += 1

  # Attach the host's managment VMK as a non-floating VNI; we will ultimately access the host using only this IP
  additional_networks.append(vlan_network_attachment('vmk1', db.get("subnets.management.reservations.%s.vni" % host), db.get('vlans.management'), False))

  # For host001, attach all VLAN interfaces that will be used by management VMs like vCenter, NSX, and Avi
  # Use the inventory database as our indication of what to add, filtering out the VSI and bare metals
  # These interfaces must be allowed to float
  if host == 'host001' :
    for item in db.get('subnets.management.reservations') :
      if item not in ('bastion', 'host001', 'host002', 'host003') :
        additional_networks.append(vlan_network_attachment(item, db.get("subnets.management.reservations.%s.vni" % item), db.get('vlans.management'), True))

  # Create bare metal
  bm_model = {
    'vpc'                        : { 'id' : db.get('vpc.id') },
    'zone'                       : zone,
    'name'                       : host,
    'profile'                    : { 'name' : 'bx2d-metal-96x384' },
    'initialization'             : { 'image' : { 'id': db.get('esxi_image_id') },
                                     'keys'  : [ { 'id' : key['id'] } ] },
    'trusted_platform_module'    : { 'mode' : 'tpm_2' },
    'enable_secure_boot'         : True,
    'primary_network_attachment' : primary_network_attachment,
    'network_attachments'        : additional_networks
  }
  bm = vpclib.create_or_retrieve_bare_metal(bm_model, db.get("bare_metals.%s.id" % host))
  db.set("bare_metals.%s.id" % host, bm['id'])

print("Retrieve bare metal server passwords; wait if necessary")
for host in ('host001', 'host002', 'host003') :
  # Get server initialization information
  init = vpclib.get_bare_metal_initialization(db.get("bare_metals.%s.id" % host))

  while len(init['user_accounts']) == 0 :
    time.sleep(15)
    init = vpclib.get_bare_metal_initialization(db.get("bare_metals.%s.id" % host))

  # Decrypt root password
  password = rsa_priv.key.decrypt(base64.decodebytes(bytes(init['user_accounts'][0]['encrypted_password'], 'ascii')), padding.PKCS1v15()).decode('ascii')
  db.set("bare_metals.%s.password" % host, password)

# Note: the key object is attached to the bare metal for the life of the server and cannot be removed at this point

# Find the default routing table and create routes to the edge uplink VIP
tables = list(vpclib.list_routing_tables(db.get('vpc.id')))
assert(len(tables) == 1)
vpclib.create_or_retrieve_route(db.get('vpc.id'), tables[0]['id'], 'route1', db.get('subnets.overlay1.cidr'), zone, db.get('subnets.uplink.reservations.vip.ip'))
vpclib.create_or_retrieve_route(db.get('vpc.id'), tables[0]['id'], 'route2', db.get('subnets.overlay2.cidr'), zone, db.get('subnets.uplink.reservations.vip.ip'))
vpclib.create_or_retrieve_route(db.get('vpc.id'), tables[0]['id'], 'route3', db.get('subnets.overlay3.cidr'), zone, db.get('subnets.uplink.reservations.vip.ip'))

# Create or update DNS entries based on the management addresses
dnsZone = vpclib.create_or_retrieve_zone(db.get('dns_instance_id'), 'example.com')
for item in db.get('subnets.management.reservations') :
  vpclib.create_or_update_Arecord(dnsZone, "%s.example.com" % item, db.get("subnets.management.reservations.%s.ip" % item))
# Do the same for each of our Ubuntu overlay VMs
for network in db.get('subnets') :
  if 'overlay' in network :
    for vmname in db.get("subnets.%s.reservations" % network) :
      vpclib.create_or_update_Arecord(dnsZone, "%s.example.com" % vmname, db.get("subnets.%s.reservations.%s.ip" % (network, vmname)))

# Post deployment, the ESXi vmk0 interfaces need to be re-IPed to the VLAN VNIs; as part of this the gateway IP and VLAN also need to be corrected.
# The second vmnic will be used later to bootstrap the DVS; there is no need to add it to the vSwitch in this temporary unmanaged state.

