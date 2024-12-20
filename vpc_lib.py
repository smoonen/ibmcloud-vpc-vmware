from ibm_vpc import VpcV1
from ibm_cloud_networking_services import DnsSvcsV1
from ibm_cloud_sdk_core.authenticators import IAMAuthenticator
import sshkey_tools.keys
from cryptography.hazmat.primitives.asymmetric import padding
import inventory

# TODO: account for pagination in searches

class VPClib :
  def __init__(self, region = 'eu-gb', api_key = inventory.api_key) :
    self.region = region
    authenticator = IAMAuthenticator(api_key)
    self.service = VpcV1(authenticator = authenticator)
    self.service.set_service_url('https://%s.iaas.cloud.ibm.com/v1' % region)
    self.dnssvc = DnsSvcsV1(authenticator = authenticator)
    self.dnssvc.set_service_url('https://api.dns-svcs.cloud.ibm.com/v1/')

  def create_or_retrieve_vpc(self, name) :
    vpcs = self.service.list_vpcs()
    for vpc in vpcs.result['vpcs'] :
      if vpc['name'] == name :
        return vpc['id']
    response = self.service.create_vpc(address_prefix_management = 'manual', name = name)
    return response.result['id']

  def create_or_retrieve_prefix(self, vpc_id, cidr, zone, name, is_default) :
    prefixes = self.service.list_vpc_address_prefixes(vpc_id)
    for prefix in prefixes.result['address_prefixes'] :
      if prefix['name'] == name :
        return prefix['id']
    response = self.service.create_vpc_address_prefix(vpc_id, cidr, zone, is_default = is_default, name = name)
    return response.result['id']

  def create_or_retrieve_subnet(self, vpc_id, cidr, zone, name) :
    subnets = self.service.list_subnets(vpc_id = vpc_id)
    for subnet in subnets.result['subnets'] :
      if subnet['name'] == name :
        return subnet['id']
    subnet_model = {
      'vpc'             : { 'id' : vpc_id },
      'ip_version'      : 'ipv4',
      'ipv4_cidr_block' : cidr,
      'zone'            : zone,
      'name'            : name
    }
    response = self.service.create_subnet(subnet_model)
    return response.result['id']

  def create_or_retrieve_public_gateway(self, vpc_id, zone, name) :
    gateways = self.service.list_public_gateways()
    for gateway in gateways.result['public_gateways'] :
      if gateway['name'] == name :
        return gateway['id']
    response = self.create_public_gateway({ 'id' : vpc_id }, zone, name)
    return response.result['id']

  def attach_public_gateway(self, subnet_id, gateway_id) :
    response = self.service.set_subnet_public_gateway(subnet_id, { 'id' : gateway_id })

  def list_images(self) :
    response = self.service.list_images()
    return response.result['images']

  def create_or_retrieve_security_group(self, vpc_id, rules, name) :
    groups = self.service.list_security_groups(vpc_id = vpc_id)
    for group in groups.result['security_groups'] :
      if group['name'] == name :
        return group['id']
    response = self.service.create_security_group({ 'id' : vpc_id }, name = name, rules = rules)
    return response.result['id']

  # There are several forms of VNI creation that can attach at creation time.
  # This form attaches to a subnet and so the VPC and zone are implicit.
  def create_or_retrieve_vni(self, subnet_id, name, security_group = None) :
    vnis = self.service.list_virtual_network_interfaces()
    for vni in vnis.result['virtual_network_interfaces'] :
      if vni['name'] == name :
        return vni['id']
    response = self.service.create_virtual_network_interface(name = name, subnet = { 'id' : subnet_id }, allow_ip_spoofing = True, enable_infrastructure_nat = True, protocol_state_filtering_mode = 'auto', security_groups = [ { 'id' : security_group }])
    return response.result['id']

  def get_vni(self, vni_id) :
    response = self.service.get_virtual_network_interface(id = vni_id)
    return response.result

  def create_or_retrieve_key(self, key, name, key_type) :
    keys = self.service.list_keys()
    for key in keys.result['keys'] :
      if key['name'] == name :
        return key['id']
    response = self.service.create_key(key, name = name, type = key_type)
    return response.result['id']

  def create_or_retrieve_vsi(self, model) :
    vsis = self.service.list_instances(vpc_id = model['vpc']['id'])
    for vsi in vsis.result['instances'] :
      if vsi['name'] == model['name'] :
        return vsi['id']
    response = self.service.create_instance(model)
    return response.result['id']

  def get_instance_initialization(self, vsi_id) :
    response = self.service.get_instance_initialization(vsi_id)
    return response.result

  def create_or_retrieve_bare_metal(self, model) :
    bare_metals = self.service.list_bare_metal_servers(vpc_id = model['vpc']['id'])
    for bare_metal in bare_metals.result['bare_metal_servers'] :
      if bare_metal['name'] == model['name'] :
        return bare_metal['id']
    response = self.service.create_bare_metal_server(model)
    return response.result['id']

  def get_bare_metal_initialization(self, bm_id) :
    response = self.service.get_bare_metal_server_initialization(bm_id)
    return response.result

  def create_or_retrieve_floating_ip(self, vni_id, name) :
    fips = self.service.list_floating_ips(target_id = vni_id)
    for fip in fips.result['floating_ips'] :
      if fip['name'] == name :
        return fip['id']
    response = self.service.create_floating_ip({ 'name' : name, 'target' : { 'id' : vni_id } })
    return response.result['id']

