from vpc_lib import VPClib
import inventory
import pprint, sys

vpclib = VPClib()

# Process three hosts
for host in ('host001', 'host002', 'host003') :
  bm_id = getattr(inventory, '%s_bm_id' % host)

  # In theory the MAC addresses should appear on the attachment objects, but for now they are available only on the legacy interfaces API
  interfaces = vpclib.get_bare_metal_network_interfaces(bm_id)

  for vmnic in range(1, 6) :
    mac = getattr(inventory, '%s_vmnic%d_mac' % (host, vmnic))
    for interface in interfaces :
      if interface['mac_address'].lower() == mac.lower() :
        print("%s vmnic%d matches host interface %s; applying VLAN %d" % (host, vmnic, interface['name'], vmnic + 1))
        patch = { 'allowed_vlans' : interface['allowed_vlans'] }
        patch['allowed_vlans'].append(vmnic + 1)

        # Attachment id and interface id are the same
        vpclib.update_bare_metal_attachment(bm_id, interface['id'], patch)

