from vpc_lib import VPClib

# Commonalities
zone1 = { 'name' : 'eu-gb-1' }

vpclib = VPClib()

# Create VPC
vpc_id = vpclib.create_or_retrieve_vpc('smoonen-lon')
print("vpc_id = '%s'" % vpc_id)

# Create address prefix
prefix_id = vpclib.create_or_retrieve_prefix(vpc_id, '192.168.0.0/16', zone1, 'smoonen-lon-prefix1', True)
print("prefix_id = '%s'" % prefix_id)

# Create subnets
host_subnet_id = vpclib.create_or_retrieve_subnet(vpc_id, '192.168.1.0/24', zone1, 'smoonen-lon-host1')
print("host_subnet_id = '%s'" % host_subnet_id)
mgmt_subnet_id = vpclib.create_or_retrieve_subnet(vpc_id, '192.168.2.0/24', zone1, 'smoonen-lon-mgmt1')
print("mgmt_subnet_id = '%s'" % mgmt_subnet_id)
vmotion_subnet_id = vpclib.create_or_retrieve_subnet(vpc_id, '192.168.3.0/24', zone1, 'smoonen-lon-vmotion1')
print("vmotion_subnet_id = '%s'" % vmotion_subnet_id)
vsan_subnet_id = vpclib.create_or_retrieve_subnet(vpc_id, '192.168.4.0/24', zone1, 'smoonen-lon-vsan1')
print("vsan_subnet_id = '%s'" % vsan_subnet_id)
tep_subnet_id = vpclib.create_or_retrieve_subnet(vpc_id, '192.168.5.0/24', zone1, 'smoonen-lon-tep1')
print("tep_subnet_id = '%s'" % tep_subnet_id)
uplink_subnet_id = vpclib.create_or_retrieve_subnet(vpc_id, '192.168.6.0/24', zone1, 'smoonen-lon-uplink1')
print("uplink_subnet_id = '%s'" % uplink_subnet_id)

# Create public gateway
public_gateway_id = vpclib.create_or_retrieve_public_gateway(vpc_id, zone1, 'smoonen-lon-gateway')
print("public_gateway_id = '%s'" % public_gateway_id)

# Attach this gateway to uplink and management subnets
vpclib.attach_public_gateway(uplink_subnet_id, public_gateway_id)
vpclib.attach_public_gateway(mgmt_subnet_id, public_gateway_id)

