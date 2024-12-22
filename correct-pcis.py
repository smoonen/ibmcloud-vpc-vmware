from vpc_lib import VPClib
import inventory
import pprint, sys

vpclib = VPClib()

# Process three hosts
for host in ('host001', 'host002', 'host003') :
  bm_id = getattr(inventory, '%s_bm_id' % host)

  # In theory the MAC addresses should appear on the attachment objects, but for now they are available only on the legacy interfaces API
  interfaces = list(vpclib.get_bare_metal_network_interfaces(bm_id))

  # Correct allowed VLANs on PCIs
  for vmnic in range(1, 6) :
    mac = getattr(inventory, '%s_vmnic%d_mac' % (host, vmnic))
    for interface in interfaces :
      if interface['mac_address'].lower() == mac.lower() :
        if (vmnic + 1) in interface['allowed_vlans'] :
          print("%s vmnic%d matches host interface %s; VLAN %d already applied" % (host, vmnic, interface['name'], vmnic + 1))
        else :
          print("%s vmnic%d matches host interface %s; applying VLAN %d" % (host, vmnic, interface['name'], vmnic + 1))
          patch = { 'allowed_vlans' : interface['allowed_vlans'] }
          patch['allowed_vlans'].append(vmnic + 1)

          # Attachment id and interface id are the same
          vpclib.update_bare_metal_attachment(bm_id, interface['id'], patch)

  # Attach VLAN interfaces if needed
  vmk0 = vpclib.get_vni_by_name("smoonen-vni-%s-vmk0-vmotion" % host)
  attachment = { 'name' : 'vmk0', 'virtual_network_interface' : { 'id' : vmk0['id'] }, 'allow_to_float' : False, 'interface_type' : 'vlan', 'vlan' : 3 }
  vpclib.create_or_retrieve_bare_metal_attachment(bm_id, attachment)

  vmk2 = vpclib.get_vni_by_name("smoonen-vni-%s-vmk2-vsan" % host)
  attachment = { 'name' : 'vmk2', 'virtual_network_interface' : { 'id' : vmk2['id'] }, 'allow_to_float' : False, 'interface_type' : 'vlan', 'vlan' : 4 }
  vpclib.create_or_retrieve_bare_metal_attachment(bm_id, attachment)

