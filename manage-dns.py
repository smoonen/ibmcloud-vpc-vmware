from vpc_lib import VPClib
import inventory
import pprint

vpclib = VPClib()

zone = vpclib.create_or_retrieve_zone(inventory.dns_instance_id, 'example.com')

vpclib.create_or_update_Arecord(zone, 'vcenter.example.com', inventory.vcenter_ip)
vpclib.create_or_update_Arecord(zone, 'host001.example.com', inventory.host001_vmk1_mgmt_ip)
vpclib.create_or_update_Arecord(zone, 'host002.example.com', inventory.host002_vmk1_mgmt_ip)
vpclib.create_or_update_Arecord(zone, 'host003.example.com', inventory.host003_vmk1_mgmt_ip)
