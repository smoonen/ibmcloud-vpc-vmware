import ipaddress, itertools
from vpc_lib import VPClib
from inventory import Inventory

db = Inventory()
vpclib = VPClib(db.get('region'), db.get('api_key'))
zone = { 'name' : db.get('zone') }

print("Create or retrieve VPC")
vpc = vpclib.create_or_retrieve_vpc(db.get('resource_prefix') + '-vpc', db.get('vpc.id'))
db.set('vpc.id', vpc['id'])
db.set('vpc.name', vpc['name'])

print("Create or retrieve address prefixes and subnets")
for network in ('pci', 'management', 'vmotion', 'vsan', 'tep', 'uplink') :
  prefix = vpclib.create_or_retrieve_prefix(vpc['id'], db.get("subnets.%s.cidr" % network), zone, db.get('resource_prefix') + '-' + network + '-pfx', network == 'management', db.get("subnets.%s.prefix_id" % network))
  db.set("subnets.%s.prefix_id" % network, prefix['id'])
  db.set("subnets.%s.prefix_name" % network, prefix['name'])
  subnet = vpclib.create_or_retrieve_subnet(vpc['id'], db.get("subnets.%s.cidr" % network), zone, db.get('resource_prefix') + '-' + network + '-subnet', db.get("subnets.%s.subnet_id" % network))
  db.set("subnets.%s.subnet_id" % network, subnet['id'])
  db.set("subnets.%s.subnet_name" % network, subnet['name'])

print("Create or retrieve PCI network IP reservations")
pci_subnet = ipaddress.ip_network(db.get('subnets.pci.cidr'))
# Consume first three addresses which are typically reserved by IBM Cloud
pci_addresses = list(itertools.islice(pci_subnet.hosts(), 3, None))
for host in 'host001', 'host002', 'host003' :
  for interface in 'management', 'vmotion', 'vsan', 'tep', 'uplink' :
    reservation_name = "%s-%s" % (host, interface)
    reservation = vpclib.reserve_or_retrieve_ip(db.get('subnets.pci.subnet_id'), pci_addresses.pop(0).compressed, reservation_name, db.get("subnets.pci.reservations.%s.id" % reservation_name))
    db.set("subnets.pci.reservations.%s.id" % reservation_name, reservation['id'])
    db.set("subnets.pci.reservations.%s.ip" % reservation_name, reservation['address'])

print("Create or retrieve management network IP reservations")
management_subnet = ipaddress.ip_network(db.get('subnets.management.cidr'))
# Consume first three addresses which are typically reserved by IBM Cloud
management_addresses = list(itertools.islice(management_subnet.hosts(), 3, None))
for resource in ('bastion', 'host001', 'host002', 'host003', 'vcenter', 'nsx', 'nsx0', 'nsx1', 'nsx2', 'edge0', 'edge1', 'avi', 'avi0', 'avi1', 'avi2', 'super0', 'super1', 'super2', 'super3', 'super4') :
  reservation = vpclib.reserve_or_retrieve_ip(db.get('subnets.management.subnet_id'), management_addresses.pop(0).compressed, resource, db.get("subnets.management.reservations.%s.id" % resource))
  db.set("subnets.management.reservations.%s.id" % resource, reservation['id'])
  db.set("subnets.management.reservations.%s.ip" % resource, reservation['address'])

print("Create or retrieve vMotion and vSAN network IP reservations")
for network in ('vmotion', 'vsan') :
  subnet = ipaddress.ip_network(db.get("subnets.%s.cidr" % network))
  # Consume first three addresses which are typically reserved by IBM Cloud
  addresses = list(itertools.islice(subnet.hosts(), 3, None))
  for host in ('host001', 'host002', 'host003') :
    reservation = vpclib.reserve_or_retrieve_ip(db.get("subnets.%s.subnet_id" % network), addresses.pop(0).compressed, host, db.get("subnets.%s.reservations.%s.id" % (network, host)))
    db.set("subnets.%s.reservations.%s.id" % (network, host), reservation['id'])
    db.set("subnets.%s.reservations.%s.ip" % (network, host), reservation['address'])

print("Create or retrieve TEP IP reservations")
tep_subnet = ipaddress.ip_network(db.get('subnets.tep.cidr'))
# Consume first three addresses which are typically reserved by IBM Cloud
tep_addresses = list(itertools.islice(tep_subnet.hosts(), 3, None))
for x in range(10) :
  reservation = vpclib.reserve_or_retrieve_ip(db.get('subnets.tep.subnet_id'), tep_addresses.pop(0).compressed, "tep%d" % x, db.get("subnets.tep.reservations.tep%d.id" % x))
  db.set("subnets.tep.reservations.tep%d.id" % x, reservation['id'])
  db.set("subnets.tep.reservations.tep%d.ip" % x, reservation['address'])

print("Create or retrieve uplink reservations")
uplink_subnet = ipaddress.ip_network(db.get('subnets.uplink.cidr'))
# Consume first three addresses which are typically reserved by IBM Cloud
uplink_addresses = list(itertools.islice(uplink_subnet.hosts(), 3, None))
for name in ('vip', 'uplink0', 'uplink1') :
  reservation = vpclib.reserve_or_retrieve_ip(db.get('subnets.uplink.subnet_id'), uplink_addresses.pop(0).compressed, name, db.get("subnets.uplink.reservations.%s.id" % name))
  db.set("subnets.uplink.reservations.%s.id" % name, reservation['id'])
  db.set("subnets.uplink.reservations.%s.ip" % name, reservation['address'])

print("Calculate gateway IP and netmask for each subnet")
for network in db.get('subnets') :
  subnet = ipaddress.ip_network(db.get("subnets.%s.cidr" % network))
  # Netmask and prefix length are precalculated for us
  db.set("subnets.%s.netmask" % network, subnet.netmask.compressed)
  db.set("subnets.%s.prefixlen" % network, subnet.prefixlen)
  # Gateway is the first address
  addresses = subnet.hosts()
  db.set("subnets.%s.gateway" % network, next(addresses).compressed)

  # Snag one more address for Ubuntu machines on overlay networks
  if 'overlay' in network :
    vmname = network.replace('overlay', 'ubuntu')
    db.set("subnets.%s.reservations.%s.ip" % (network, vmname), next(addresses).compressed)

print("Create or retrieve public gateway")
public_gateway = vpclib.create_or_retrieve_public_gateway(vpc['id'], zone, db.get('resource_prefix') + '-gateway', db.get("public_gateway.id"))
db.set('public_gateway.id', public_gateway['id'])
db.set('public_gateway.ip', public_gateway['floating_ip']['address'])

# Attach this gateway to uplink and management subnets
vpclib.attach_public_gateway(db.get('subnets.uplink.subnet_id'), public_gateway['id'])
vpclib.attach_public_gateway(db.get('subnets.management.subnet_id'), public_gateway['id'])

# Attach this VPC to our DNS instance
dnsZone = vpclib.create_or_retrieve_zone(db.get('dns_instance_id'), 'example.com')
vpclib.create_or_retrieve_permitted_network(db.get('dns_instance_id'), dnsZone['id'], vpc['crn'])

