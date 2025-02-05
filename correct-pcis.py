from vpc_lib import VPClib
from inventory import Inventory

db = Inventory()
vpclib = VPClib(db.get('region'), db.get('api_key'))

# Process three hosts
for host in ('host001', 'host002', 'host003') :
  bm_id = db.get("bare_metals.%s.id" % host)

  # In theory the MAC addresses should appear on the attachment objects, but for now they are available only on the legacy interfaces API
  interfaces = list(vpclib.get_bare_metal_network_interfaces(bm_id))

  # Correct allowed VLANs on PCIs
  vmnic_counter = 1
  for network in ('vmotion', 'vsan', 'tep', 'uplink') :
    vlan = db.get("vlans.%s" % network)
    mac = db.get("bare_metals.%s.vmnic%d_mac" % (host, vmnic_counter))
    for interface in interfaces :
      if interface['mac_address'].lower() == mac.lower() :
        if vlan in interface['allowed_vlans'] :
          print("%s vmnic%d matches host interface %s; VLAN %d already applied" % (host, vmnic_counter, interface['name'], vlan))
        else :
          print("%s vmnic%d matches host interface %s; applying VLAN %d" % (host, vmnic_counter, interface['name'], vlan))
          patch = { 'allowed_vlans' : interface['allowed_vlans'] }
          patch['allowed_vlans'].append(vlan)

          # Attachment id and interface id are the same
          vpclib.update_bare_metal_attachment(bm_id, interface['id'], patch)

          # If this is the first host, attach NSX TEP and edge uplink VNIs
          if host == 'host001' and network in ('tep', 'uplink') :
            for reservation in db.get("subnets.%s.reservations" % network) :
              attachment = {
                'name'                      : reservation,
                'virtual_network_interface' : { 'id' : db.get("subnets.%s.reservations.%s.vni" % (network, reservation)) },
                'allow_to_float'            : True,
                'interface_type'            : 'vlan',
                'vlan'                      : db.get("vlans.%s" % network)
              }
              vpclib.create_or_retrieve_bare_metal_attachment(bm_id, attachment)

    vmnic_counter += 1

  # Attach vMotion and vSAN interfaces to the host
  for network in ('vmotion', 'vsan') :
    attachment = {
      'name'                      : 'vmk0' if network == 'vmotion' else 'vmk2',
      'virtual_network_interface' : { 'id' : db.get("subnets.%s.reservations.%s.vni" % (network, host)) },
      'allow_to_float'            : False,
      'interface_type'            : 'vlan',
      'vlan'                      : db.get("vlans.%s" % network)
    }
    vpclib.create_or_retrieve_bare_metal_attachment(bm_id, attachment)

