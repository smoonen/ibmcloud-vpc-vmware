from ibm_vpc import VpcV1
from ibm_cloud_networking_services import DnsSvcsV1
from ibm_cloud_sdk_core.authenticators import IAMAuthenticator
import sshkey_tools.keys
from cryptography.hazmat.primitives.asymmetric import padding
import inventory
import urllib.parse

class VPCiterator :
  def __init__(self, f, listname) :
    self.f = f
    self.listname = listname
    self.result = None

  def __iter__(self) :
    self.result = self.f(limit = 5).result
    return self

  def __next__(self) :
    if len(self.result[self.listname]) == 0 :
      if 'next' in self.result :
        parse = urllib.parse.urlparse(self.result['next']['href'])
        query = urllib.parse.parse_qs(parse.query)
        self.result = self.f(**query).result
      else :
        raise StopIteration
    nextitem = self.result[self.listname].pop(0)
    return nextitem

class VPClib :
  def __init__(self, region = 'eu-gb', api_key = inventory.api_key) :
    self.region = region
    authenticator = IAMAuthenticator(api_key)
    self.service = VpcV1(authenticator = authenticator)
    self.service.set_service_url('https://%s.iaas.cloud.ibm.com/v1' % region)
    self.dnssvc = DnsSvcsV1(authenticator = authenticator)
    self.dnssvc.set_service_url('https://api.dns-svcs.cloud.ibm.com/v1/')

  def create_or_retrieve_vpc(self, name) :
    for vpc in VPCiterator(self.service.list_vpcs, 'vpcs') :
      if vpc['name'] == name :
        return vpc
    response = self.service.create_vpc(address_prefix_management = 'manual', name = name)
    return response.result

  def create_or_retrieve_prefix(self, vpc_id, cidr, zone, name, is_default) :
    def helper(**kwargs) :
      return self.service.list_vpc_address_prefixes(vpc_id, **kwargs)
    for prefix in VPCiterator(helper, 'address_prefixes') :
      if prefix['name'] == name :
        return prefix
    response = self.service.create_vpc_address_prefix(vpc_id, cidr, zone, is_default = is_default, name = name)
    return response.result

  def create_or_retrieve_subnet(self, vpc_id, cidr, zone, name) :
    def helper(**kwargs) :
      return self.service.list_subnets(vpc_id = vpc_id, **kwargs)
    for subnet in VPCiterator(helper, 'subnets') :
      if subnet['name'] == name :
        return subnet
    subnet_model = {
      'vpc'             : { 'id' : vpc_id },
      'ip_version'      : 'ipv4',
      'ipv4_cidr_block' : cidr,
      'zone'            : zone,
      'name'            : name
    }
    response = self.service.create_subnet(subnet_model)
    return response.result

  def create_or_retrieve_public_gateway(self, vpc_id, zone, name) :
    for gateway in VPCiterator(self.service.list_public_gateways, 'public_gateways') :
      if gateway['name'] == name :
        return gateway
    response = self.create_public_gateway({ 'id' : vpc_id }, zone, name)
    return response.result

  def attach_public_gateway(self, subnet_id, gateway_id) :
    response = self.service.set_subnet_public_gateway(subnet_id, { 'id' : gateway_id })

  def list_images(self) :
    return VPCiterator(self.service.list_images, 'images')

  def create_or_retrieve_security_group(self, vpc_id, rules, name) :
    def helper(**kwargs) :
      return self.service.list_security_groups(vpc_id = vpc_id, **kwargs)
    for group in VPCiterator(helper, 'security_groups') :
      if group['name'] == name :
        return group
    response = self.service.create_security_group({ 'id' : vpc_id }, name = name, rules = rules)
    return response.result

  # There are several forms of VNI creation that can attach at creation time.
  # This form attaches to a subnet and so the VPC and zone are implicit.
  def create_or_retrieve_vni(self, subnet_id, name, security_group = None) :
    for vni in VPCiterator(self.service.list_virtual_network_interfaces, 'virtual_network_interfaces') :
      if vni['name'] == name :
        return vni
    response = self.service.create_virtual_network_interface(name = name, subnet = { 'id' : subnet_id }, allow_ip_spoofing = True, enable_infrastructure_nat = True, protocol_state_filtering_mode = 'auto', security_groups = [ { 'id' : security_group }])
    return response.result

  def get_vni(self, vni_id) :
    response = self.service.get_virtual_network_interface(id = vni_id)
    return response.result

  def create_or_retrieve_key(self, key, name, key_type) :
    for key in VPCiterator(self.service.list_keys, 'keys') :
      if key['name'] == name :
        return key
    response = self.service.create_key(key, name = name, type = key_type)
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

  def create_or_retrieve_bare_metal(self, model) :
    def helper(**kwargs) :
      return self.service.list_bare_metal_servers(vpc_id = model['vpc']['id'], **kwargs)
    for bare_metal in VPCiterator(helper, 'bare_metal_servers') :
      if bare_metal['name'] == model['name'] :
        return bare_metal
    response = self.service.create_bare_metal_server(model)
    return response.result

  def get_bare_metal_initialization(self, bm_id) :
    response = self.service.get_bare_metal_server_initialization(bm_id)
    return response.result

  def get_bare_metal_network_attachments(self, bm_id) :
    def helper(**kwargs) :
      return self.service.list_bare_metal_server_network_attachments(bm_id, **kwargs)
    return VPCiterator(helper, 'network_attachments')

  def get_bare_metal_network_interfaces(self, bm_id) :
    def helper(**kwargs) :
      return self.service.list_bare_metal_server_network_interfaces(bm_id, **kwargs)
    return VPCiterator(helper, 'network_interfaces')

  def update_bare_metal_attachment(self, bm_id, attach_id, updates) :
    response = self.service.update_bare_metal_server_network_attachment(bm_id, attach_id, updates)
    return response.result

  def create_or_retrieve_floating_ip(self, vni_id, name) :
    def helper(**kwargs) :
      return self.service.list_floating_ips(target_id = vni_id, **kwargs)
    for fip in VPCiterator(helper, 'floating_ips') :
      if fip['name'] == name :
        return fip
    response = self.service.create_floating_ip({ 'name' : name, 'target' : { 'id' : vni_id } })
    return response.result

