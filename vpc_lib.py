from ibm_platform_services import GlobalCatalogV1, ResourceManagerV2, ResourceControllerV2
from ibm_vpc import VpcV1
from ibm_cloud_networking_services import DnsSvcsV1
from ibm_cloud_sdk_core.authenticators import IAMAuthenticator
import sshkey_tools.keys
from cryptography.hazmat.primitives.asymmetric import padding
import urllib.parse

def VPCiterator(f, listname) :
  query = {}

  while True :
    result = f(**query).result
    for item in result[listname] : yield item
    if 'next' not in result : break
    if isinstance(result['next'], str) : nexturl = result['next']
    else                               : nexturl = result['next']['href']
    query = urllib.parse.parse_qs(urllib.parse.urlparse(nexturl).query)

class VPClib :
  def __init__(self, region, api_key) :
    self.region = region
    authenticator = IAMAuthenticator(api_key)
    self.service = VpcV1(authenticator = authenticator)
    self.service.set_service_url('https://%s.iaas.cloud.ibm.com/v1' % region)
    self.globalcatalog = GlobalCatalogV1(authenticator = authenticator)
    self.resourcemgr = ResourceManagerV2(authenticator = authenticator)
    self.resourcecontroller = ResourceControllerV2(authenticator = authenticator)
    self.dnssvc = DnsSvcsV1(authenticator = authenticator)
    self.dnssvc.set_service_url('https://api.dns-svcs.cloud.ibm.com/v1/')

  def create_or_retrieve_vpc(self, name, vpc_id = None) :
    if vpc_id :
      response = self.service.get_vpc(vpc_id)
    else :
      response = self.service.create_vpc(address_prefix_management = 'manual', name = name)
    return response.result

  def create_or_retrieve_prefix(self, vpc_id, cidr, zone, name, is_default, prefix_id = None) :
    if prefix_id :
      response = self.service.get_vpc_address_prefix(vpc_id, prefix_id)
    else :
      response = self.service.create_vpc_address_prefix(vpc_id, cidr, zone, is_default = is_default, name = name)
    return response.result

  def create_or_retrieve_subnet(self, vpc_id, cidr, zone, name, subnet_id = None) :
    if subnet_id :
      response = self.service.get_subnet(subnet_id)
    else :
      subnet_model = {
        'vpc'             : { 'id' : vpc_id },
        'ip_version'      : 'ipv4',
        'ipv4_cidr_block' : cidr,
        'zone'            : zone,
        'name'            : name
      }
      response = self.service.create_subnet(subnet_model)
    return response.result

  def reserve_or_retrieve_ip(self, subnet_id, address, name, reservation_id = None) :
    if reservation_id :
      response = self.service.get_subnet_reserved_ip(subnet_id, reservation_id)
    else :
      response = self.service.create_subnet_reserved_ip(subnet_id, address = address, name = name)
    return response.result

  def create_or_retrieve_public_gateway(self, vpc_id, zone, name, gateway_id = None) :
    if gateway_id :
      response = self.service.get_public_gateway(gateway_id)
    else :
      response = self.service.create_public_gateway({ 'id' : vpc_id }, zone, name = name)
    return response.result

  def attach_public_gateway(self, subnet_id, gateway_id) :
    response = self.service.set_subnet_public_gateway(subnet_id, { 'id' : gateway_id })

  def list_images(self) :
    return VPCiterator(self.service.list_images, 'images')

  def create_or_retrieve_security_group(self, vpc_id, rules, name, sg_id = None) :
    if sg_id :
      response = self.service.get_security_group(sg_id)
    else :
      response = self.service.create_security_group({ 'id' : vpc_id }, name = name, rules = rules)
    return response.result

  # There are several forms of VNI creation that can attach at creation time.
  # This form attaches to a subnet and so the VPC and zone are implicit.
  def create_or_retrieve_vni(self, name, security_group = None, subnet_id = None, primary_ip = None, vni_id = None) :
    if vni_id :
      response = self.service.get_virtual_network_interface(vni_id)
    else :
      kwargs = { 'name'                          : name,
                 'allow_ip_spoofing'             : True,
                 'enable_infrastructure_nat'     : True,
                 'protocol_state_filtering_mode' : 'auto' }
      if security_group : kwargs['security_groups'] = [ { 'id' : security_group } ]
      if subnet_id      : kwargs['subnet'] = { 'id' : subnet_id }
      if primary_ip     : kwargs['primary_ip'] = { 'id' : primary_ip }
      response = self.service.create_virtual_network_interface(**kwargs)
    return response.result

  def get_vni(self, vni_id) :
    response = self.service.get_virtual_network_interface(id = vni_id)
    return response.result

  def get_vni_by_name(self, vni_name) :
    for vni in VPCiterator(self.service.list_virtual_network_interfaces, 'virtual_network_interfaces') :
      if vni['name'] == vni_name :
        return vni
    return None

  def create_or_retrieve_key(self, public_key, name, key_type, key_id = None) :
    if key_id :
      response = self.service.get_key(key_id)
    else :
      response = self.service.create_key(public_key, name = name, type = key_type)
    return response.result

  def create_or_retrieve_vsi(self, model) :
    def helper(**kwargs) :
      return self.service.list_instances(vpc_id = model['vpc']['id'], **kwargs)
    for vsi in VPCiterator(helper, 'instances') :
      if vsi['name'] == model['name'] :
        return vsi
    response = self.service.create_instance(model)
    return response.result

  def get_instance_initialization(self, vsi_id) :
    response = self.service.get_instance_initialization(vsi_id)
    return response.result

  def list_bare_metal_servers(self, vpc_id) :
    def helper(**kwargs) :
      return self.service.list_bare_metal_servers(vpc_id = vpc_id, **kwargs)
    return VPCiterator(helper, 'bare_metal_servers')

  def create_or_retrieve_bare_metal(self, model, bm_id = None) :
    if bm_id :
      response = self.service.get_bare_metal_server(bm_id)
    else :
      response = self.service.create_bare_metal_server(model)
    return response.result

  def get_bare_metal(self, bm_id) :
    response = self.service.get_bare_metal_server(bm_id)
    return response.result

  def get_bare_metal_initialization(self, bm_id) :
    response = self.service.get_bare_metal_server_initialization(bm_id)
    return response.result

  def stop_bare_metal(self, bm_id, type = 'hard') :
    response = self.service.stop_bare_metal_server(bm_id, type)
    return response.result

  def reinitialize_bare_metal(self, bm_id, image_id, key_id) :
    response = self.service.replace_bare_metal_server_initialization(bm_id, { 'id' : image_id }, [ { 'id' : key_id } ])
    return response.result

  def get_bare_metal_network_attachments(self, bm_id) :
    def helper(**kwargs) :
      return self.service.list_bare_metal_server_network_attachments(bm_id, **kwargs)
    return VPCiterator(helper, 'network_attachments')

  def get_bare_metal_network_interfaces(self, bm_id) :
    def helper(**kwargs) :
      return self.service.list_bare_metal_server_network_interfaces(bm_id, **kwargs)
    return VPCiterator(helper, 'network_interfaces')

  def create_or_retrieve_bare_metal_attachment(self, bm_id, attachment) :
    for existing in self.get_bare_metal_network_attachments(bm_id) :
      if existing['name'] == attachment['name'] :
        return existing
    response = self.service.create_bare_metal_server_network_attachment(bm_id, attachment)
    return response.result

  def update_bare_metal_attachment(self, bm_id, attach_id, updates) :
    response = self.service.update_bare_metal_server_network_attachment(bm_id, attach_id, updates)
    return response.result

  def create_or_retrieve_floating_ip(self, vni_id, name, fip_id = None) :
    if fip_id :
      response = self.service.get_floating_ip(fip_id)
    else :
      response = self.service.create_floating_ip({ 'name' : name, 'target' : { 'id' : vni_id } })
    return response.result

  def list_routing_tables(self, vpc_id) :
    def helper(**kwargs) :
      return self.service.list_vpc_routing_tables(vpc_id, **kwargs)
    return VPCiterator(helper, 'routing_tables')

  def create_or_retrieve_route(self, vpc_id, table_id, name, destination, zone, next_hop) :
    def helper(**kwargs) :
      return self.service.list_vpc_routing_table_routes(vpc_id, table_id, **kwargs)
    for route in VPCiterator(helper, 'routes') :
      if route['name'] == name :
        return route
    response = self.service.create_vpc_routing_table_route(vpc_id, table_id, destination, zone, name = name, next_hop = { 'address' : next_hop })
    return response.result

  def list_dnszones(self, dns_inst) :
    def helper(**kwargs) :
      return self.dnssvc.list_dnszones(dns_inst, **kwargs)
    return VPCiterator(helper, 'dnszones')

  def create_or_retrieve_zone(self, dns_inst, domain) :
    for zone in self.list_dnszones(dns_inst) :
      if zone['name'] == domain :
        return zone
    response = self.dnssvc.create_dnszone(dns_inst, name = domain)
    return response.result

  def create_or_retrieve_permitted_network(self, dns_inst, zone, vpc_crn) :
    def helper(**kwargs) :
      return self.dnssvc.list_permitted_networks(dns_inst, zone, **kwargs)
    for net in VPCiterator(helper, 'permitted_networks') :
      if net['permitted_network']['vpc_crn'] == vpc_crn :
        return net
    response = self.dnssvc.create_permitted_network(dns_inst, zone, type = 'vpc', permitted_network = { 'vpc_crn' : vpc_crn })
    return response.result

  def list_zonerecords(self, zone) :
    def helper(**kwargs) :
      return self.dnssvc.list_resource_records(zone['instance_id'], zone['id'], **kwargs)
    return VPCiterator(helper, 'resource_records')

  def create_or_update_Arecord(self, zone, name, ip) :
    for record in self.list_zonerecords(zone) :
      if record['name'] == name :
        response = self.dnssvc.update_resource_record(zone['instance_id'], zone['id'], record['id'], name = name, rdata = { 'ip' : ip })
        return
    response = self.dnssvc.create_resource_record(zone['instance_id'], zone['id'], type = 'A', ttl = 900, name = name, rdata = { 'ip' : ip })

