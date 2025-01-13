from vpc_lib import VPClib

# Commonalities
zone1 = { 'name' : 'eu-gb-1' }

vpclib = VPClib()

# Create VPC
vpc = vpclib.create_or_retrieve_vpc('smoonen-lon')
print("vpc_id = '%s'" % vpc['id'])

# Create address prefixes
prefix = vpclib.create_or_retrieve_prefix(vpc['id'], '192.168.0.0/16', zone1, 'smoonen-lon-prefix1', True)
print("prefix_id = '%s'" % prefix['id'])
prefix2 = vpclib.create_or_retrieve_prefix(vpc['id'], '172.16.0.0/16', zone1, 'smoonen-lon-private-prefix1', False)
print("private_prefix_id = '%s'" % prefix2['id'])

# Create subnets
host_subnet = vpclib.create_or_retrieve_subnet(vpc['id'], '172.16.0.0/24', zone1, 'smoonen-lon-host1')
print("host_subnet_id = '%s'" % host_subnet['id'])
mgmt_subnet = vpclib.create_or_retrieve_subnet(vpc['id'], '192.168.1.0/24', zone1, 'smoonen-lon-mgmt1')
print("mgmt_subnet_id = '%s'" % mgmt_subnet['id'])
vmotion_subnet = vpclib.create_or_retrieve_subnet(vpc['id'], '192.168.2.0/24', zone1, 'smoonen-lon-vmotion1')
print("vmotion_subnet_id = '%s'" % vmotion_subnet['id'])
vsan_subnet = vpclib.create_or_retrieve_subnet(vpc['id'], '192.168.3.0/24', zone1, 'smoonen-lon-vsan1')
print("vsan_subnet_id = '%s'" % vsan_subnet['id'])
tep_subnet = vpclib.create_or_retrieve_subnet(vpc['id'], '192.168.4.0/24', zone1, 'smoonen-lon-tep1')
print("tep_subnet_id = '%s'" % tep_subnet['id'])
uplink_subnet = vpclib.create_or_retrieve_subnet(vpc['id'], '192.168.5.0/24', zone1, 'smoonen-lon-uplink1')
print("uplink_subnet_id = '%s'" % uplink_subnet['id'])

# Create public gateway
public_gateway = vpclib.create_or_retrieve_public_gateway(vpc['id'], zone1, 'smoonen-lon-gateway')
print("public_gateway_id = '%s'" % public_gateway['id'])
print("public_gateway_ip = '%s'" % public_gateway['floating_ip']['address'])

# Attach this gateway to uplink and management subnets
vpclib.attach_public_gateway(uplink_subnet['id'], public_gateway['id'])
vpclib.attach_public_gateway(mgmt_subnet['id'], public_gateway['id'])

