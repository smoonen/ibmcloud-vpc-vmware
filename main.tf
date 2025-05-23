# Inspired by https://github.com/vmware-nsx/dcinabox_terraform/

provider "nsxt" {
  host                 = var.nsx.fqdn
  username             = var.nsx.username
  password             = var.nsx.password
  allow_unverified_ssl = true
  max_retries          = 2
  license_keys         = [var.nsx.vdefend_key]
}

provider "vsphere" {
  vsphere_server       = var.vcenter.fqdn
  user                 = var.vcenter.username
  password             = var.vcenter.password
  allow_unverified_ssl = true
  api_timeout          = 20
}

# Data collection

data "vsphere_datacenter" "datacenter" {
  name = "ibmcloud"
}

data "vsphere_compute_cluster" "compute_cluster" {
  name          = "london"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_datastore" "datastore" {
  name          = "vsanDatastore"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_distributed_virtual_switch" "vds" {
  name          = "dswitch-tep"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "dpg_mgmt" {
  name          = "dpg-mgmt"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "dpg_uplink" {
  name          = "dpg-uplink"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "nsxt_policy_transport_zone" "overlay_transport_zone" {
  display_name = "nsx-overlay-transportzone"
}

data "nsxt_policy_transport_zone" "vlan_transport_zone" {
  display_name = "nsx-vlan-transportzone"
}

data "nsxt_compute_collection" "compute_cluster_collection" {
  display_name = "london"
}

data "nsxt_compute_manager" "vcenter" {
  display_name = "vcenter.example.com"
}

# IP Pool for TEPs

resource "nsxt_policy_ip_pool" "pool1" {
  display_name = "tep-pool"
  description  = "NSX TEP IPs"
}

resource "nsxt_policy_ip_pool_static_subnet" "static_subnet1" {
  display_name = "tep-pool-subnet"
  pool_path    = nsxt_policy_ip_pool.pool1.path
  cidr         = var.nsx.tep_cidr
  gateway      = var.nsx.tep_gateway

  allocation_range {
    start = var.nsx.tep_first
    end   = var.nsx.tep_last
  }
}

# Hosts / transport nodes

resource "nsxt_policy_uplink_host_switch_profile" "esxi_uplink_profile" {
  display_name = "esxi_uplink_profile"

  transport_vlan = var.nsx.tep_vlan
  overlay_encap  = "GENEVE"

  teaming {
    active {
      uplink_name = "uplink1"
      uplink_type = "PNIC"
    }
    policy = "LOADBALANCE_SRCID"
  }
}

resource "nsxt_policy_host_transport_node_profile" "tnp" {
  display_name = "tnp"
  standard_host_switch {
    host_switch_id   = data.vsphere_distributed_virtual_switch.vds.id
    host_switch_mode = "STANDARD"
    ip_assignment {
      static_ip_pool = nsxt_policy_ip_pool.pool1.path
    }
    transport_zone_endpoint {
      transport_zone = data.nsxt_policy_transport_zone.overlay_transport_zone.path
    }
    transport_zone_endpoint {
      transport_zone = data.nsxt_policy_transport_zone.vlan_transport_zone.path
    }
    host_switch_profile = [nsxt_policy_uplink_host_switch_profile.esxi_uplink_profile.path]
    is_migrate_pnics    = false
    uplink {
      uplink_name     = "uplink1"
      vds_uplink_name = "dvUplink1"
    }
  }
}

resource "nsxt_policy_host_transport_node_collection" "htnc1" {
  display_name                = "htnc1"
  compute_collection_id       = data.nsxt_compute_collection.compute_cluster_collection.id
  transport_node_profile_path = nsxt_policy_host_transport_node_profile.tnp.path
}

data "nsxt_policy_host_transport_node_collection_realization" "htnc1_realization" {
  path      = nsxt_policy_host_transport_node_collection.htnc1.path
  timeout   = 1200
  delay     = 1
}

# Edges whose TEPs live in the same subnet as the hosts must be placed on a VLAN segment rather than a port group
resource "nsxt_policy_vlan_segment" "segment-edge-tep" {
  display_name        = "segment-edge-tep"
  transport_zone_path = data.nsxt_policy_transport_zone.vlan_transport_zone.path
  vlan_ids            = [var.nsx.tep_vlan]
  depends_on = [data.nsxt_policy_host_transport_node_collection_realization.htnc1_realization]
}

data "nsxt_policy_segment_realization" "segment-edge-tep" {
  path = nsxt_policy_vlan_segment.segment-edge-tep.path
}

# Edge nodes and cluster

resource "nsxt_policy_transport_zone" "vlan_transport_zone_edge" {
  display_name   = "nsx-vlan-transportzone-edge"
  transport_type = "VLAN_BACKED"
}

resource "nsxt_policy_uplink_host_switch_profile" "edge_uplink_profile" {
  display_name = "edge_uplink_profile"

  mtu            = 9000
  overlay_encap  = "GENEVE"

  teaming {
    active {
      uplink_name = "uplink1"
      uplink_type = "PNIC"
    }
    policy = "FAILOVER_ORDER"
  }
}

resource "nsxt_edge_transport_node" "edge_node0" {
  description  = "Primary edge node"
  display_name = "edge-node-0"

  # N-VDS for TEPs
  standard_host_switch {
    ip_assignment {
      static_ip_pool = nsxt_policy_ip_pool.pool1.realized_id
    }
    transport_zone_endpoint {
      transport_zone = data.nsxt_policy_transport_zone.overlay_transport_zone.id
    }
    host_switch_name    = "tepSwitch"
    host_switch_profile = [nsxt_policy_uplink_host_switch_profile.edge_uplink_profile.realized_id]
    pnic {
      device_name = "fp-eth0"
      uplink_name = "uplink1"
    }
  }

  # N-VDS for uplinks; note that ip_assignment/DHCP are required but ignored since no overlay TZ
  standard_host_switch {
    ip_assignment {
      assigned_by_dhcp = true
    }
    transport_zone_endpoint {
      transport_zone = nsxt_policy_transport_zone.vlan_transport_zone_edge.realized_id
    }
    host_switch_name    = "uplinkSwitch"
    host_switch_profile = [nsxt_policy_uplink_host_switch_profile.edge_uplink_profile.realized_id]
    pnic {
      device_name = "fp-eth1"
      uplink_name = "uplink1"
    }
  }

  deployment_config {
    form_factor = "XLARGE"
    node_user_settings {
      cli_password   = var.nsx.cli_password
      root_password  = var.nsx.cli_password
      audit_username = "audit"
      audit_password = var.nsx.audit_password
    }
    vm_deployment_config {
      management_network_id = data.vsphere_network.dpg_mgmt.id
      data_network_ids      = [nsxt_policy_vlan_segment.segment-edge-tep.path, data.vsphere_network.dpg_uplink.id]
      compute_id            = data.vsphere_compute_cluster.compute_cluster.id
      storage_id            = data.vsphere_datastore.datastore.id
      vc_id                 = data.nsxt_compute_manager.vcenter.id
      management_port_subnet {
        ip_addresses  = [var.nsx.edge0]
        prefix_length = var.nsx.edge_prefixlen
      }
      default_gateway_address = [var.nsx.edge_gateway]
    }
  }
  node_settings {
    hostname             = "edge0.example.com"
    dns_servers          = ["161.26.0.7", "161.26.0.8"]
    ntp_servers          = ["161.26.0.6"]
    allow_ssh_root_login = true
    enable_ssh           = true
  }

  depends_on = [data.nsxt_policy_segment_realization.segment-edge-tep]
}

resource "nsxt_edge_transport_node" "edge_node1" {
  description  = "Secondary edge node"
  display_name = "edge-node-1"

  # N-VDS for TEPs
  standard_host_switch {
    ip_assignment {
      static_ip_pool = nsxt_policy_ip_pool.pool1.realized_id
    }
    transport_zone_endpoint {
      transport_zone = data.nsxt_policy_transport_zone.overlay_transport_zone.id
    }
    host_switch_name    = "tepSwitch"
    host_switch_profile = [nsxt_policy_uplink_host_switch_profile.edge_uplink_profile.realized_id]
    pnic {
      device_name = "fp-eth0"
      uplink_name = "uplink1"
    }
  }

  # N-VDS for uplinks; note that ip_assignment/DHCP are required but ignored since no overlay TZ
  standard_host_switch {
    ip_assignment {
      assigned_by_dhcp = true
    }
    transport_zone_endpoint {
      transport_zone = nsxt_policy_transport_zone.vlan_transport_zone_edge.realized_id
    }
    host_switch_name    = "uplinkSwitch"
    host_switch_profile = [nsxt_policy_uplink_host_switch_profile.edge_uplink_profile.realized_id]
    pnic {
      device_name = "fp-eth1"
      uplink_name = "uplink1"
    }
  }

  deployment_config {
    form_factor = "XLARGE"
    node_user_settings {
      cli_password   = var.nsx.cli_password
      root_password  = var.nsx.cli_password
      audit_username = "audit"
      audit_password = var.nsx.audit_password
    }
    vm_deployment_config {
      management_network_id = data.vsphere_network.dpg_mgmt.id
      data_network_ids      = [nsxt_policy_vlan_segment.segment-edge-tep.path, data.vsphere_network.dpg_uplink.id]
      compute_id            = data.vsphere_compute_cluster.compute_cluster.id
      storage_id            = data.vsphere_datastore.datastore.id
      vc_id                 = data.nsxt_compute_manager.vcenter.id
      management_port_subnet {
        ip_addresses  = [var.nsx.edge1]
        prefix_length = var.nsx.edge_prefixlen
      }
      default_gateway_address = [var.nsx.edge_gateway]
    }
  }
  node_settings {
    hostname             = "edge1.example.com"
    dns_servers          = ["161.26.0.7", "161.26.0.8"]
    ntp_servers          = ["161.26.0.6"]
    allow_ssh_root_login = true
    enable_ssh           = true
  }

  depends_on = [data.nsxt_policy_segment_realization.segment-edge-tep]
}

data "nsxt_transport_node_realization" "edge_node0_realization" {
  id      = nsxt_edge_transport_node.edge_node0.id
  timeout = 3000
}

data "nsxt_transport_node_realization" "edge_node1_realization" {
  id      = nsxt_edge_transport_node.edge_node1.id
  timeout = 3000
}

data "vsphere_virtual_machine" "edge-node-0" {
  name          = "edge-node-0"
  datacenter_id = data.vsphere_datacenter.datacenter.id
  depends_on    = [data.nsxt_transport_node_realization.edge_node0_realization]
}

data "vsphere_virtual_machine" "edge-node-1" {
  name          = "edge-node-1"
  datacenter_id = data.vsphere_datacenter.datacenter.id
  depends_on    = [data.nsxt_transport_node_realization.edge_node0_realization]
}

resource "vsphere_compute_cluster_vm_anti_affinity_rule" "edge_anti_affinity_rule" {
  name                = "edge-anti-affinity-rule"
  compute_cluster_id  = data.vsphere_compute_cluster.compute_cluster.id
  virtual_machine_ids = [data.vsphere_virtual_machine.edge-node-0.id, data.vsphere_virtual_machine.edge-node-1.id]
}

resource "nsxt_edge_cluster" "edgecluster1" {
  display_name = "edge-cluster-01"
  member {
    transport_node_id = nsxt_edge_transport_node.edge_node0.id
  }
  member {
    transport_node_id = nsxt_edge_transport_node.edge_node1.id
  }
  depends_on = [data.nsxt_transport_node_realization.edge_node0_realization, data.nsxt_transport_node_realization.edge_node1_realization]
}

data "nsxt_policy_edge_cluster" "edgecluster1" {
  display_name = "edge-cluster-01"
  depends_on   = [nsxt_edge_cluster.edgecluster1]
}

data "nsxt_policy_edge_node" "edgenode0" {
  edge_cluster_path = data.nsxt_policy_edge_cluster.edgecluster1.path
  display_name      = "edge-node-0"
}

data "nsxt_policy_edge_node" "edgenode1" {
  edge_cluster_path = data.nsxt_policy_edge_cluster.edgecluster1.path
  display_name      = "edge-node-1"
}

# T0 gateway and uplinks

resource "nsxt_policy_tier0_gateway" "nsx-t0" {
  display_name             = "nsx-t0"
  failover_mode            = "PREEMPTIVE"
  default_rule_logging     = false
  enable_firewall          = true
  ha_mode                  = "ACTIVE_STANDBY"
  edge_cluster_path        = data.nsxt_policy_edge_cluster.edgecluster1.path
}

resource "nsxt_policy_segment" "edge-uplink" {
  display_name        = "edge-uplink"
  transport_zone_path = nsxt_policy_transport_zone.vlan_transport_zone_edge.path
  vlan_ids            = [0]
}

resource "nsxt_policy_tier0_gateway_interface" "uplink_edge0" {
  display_name   = "uplink-edge0"
  type           = "EXTERNAL"
  edge_node_path = data.nsxt_policy_edge_node.edgenode0.path
  gateway_path   = nsxt_policy_tier0_gateway.nsx-t0.path
  segment_path   = nsxt_policy_segment.edge-uplink.path
  subnets        = [var.nsx.edgeuplink_0]
  mtu            = 1500
}

resource "nsxt_policy_tier0_gateway_interface" "uplink_edge1" {
  display_name   = "uplink-edge1"
  type           = "EXTERNAL"
  edge_node_path = data.nsxt_policy_edge_node.edgenode1.path
  gateway_path   = nsxt_policy_tier0_gateway.nsx-t0.path
  segment_path   = nsxt_policy_segment.edge-uplink.path
  subnets        = [var.nsx.edgeuplink_1]
  mtu            = 1500
}

resource "nsxt_policy_static_route" "default" {
  display_name = "default_route"
  gateway_path = nsxt_policy_tier0_gateway.nsx-t0.path
  network      = "0.0.0.0/0"

  next_hop {
    ip_address = var.nsx.uplink_gateway
  }
}

resource "nsxt_policy_tier0_gateway_ha_vip_config" "ha-vip" {
  config {
    enabled                  = true
    external_interface_paths = [nsxt_policy_tier0_gateway_interface.uplink_edge0.path, nsxt_policy_tier0_gateway_interface.uplink_edge1.path]
    vip_subnets              = [var.nsx.edgeuplink_vip]
  }
}

# T1 router

resource "nsxt_policy_tier1_gateway" "nsx-t1" {
  display_name              = "nsx-t1"
  edge_cluster_path         = data.nsxt_policy_edge_cluster.edgecluster1.path
  failover_mode             = "PREEMPTIVE"
  default_rule_logging      = false
  enable_firewall           = true
  enable_standby_relocation = false
  tier0_path                = nsxt_policy_tier0_gateway.nsx-t0.path
  route_advertisement_types = ["TIER1_STATIC_ROUTES", "TIER1_CONNECTED"]
  pool_allocation           = "ROUTING"
  ha_mode                   = "ACTIVE_STANDBY"
}

# Overlay segments

# This segment will hang off of the T0
resource "nsxt_policy_segment" "segment1" {
  display_name        = "segment1"
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_transport_zone.path
  connectivity_path = nsxt_policy_tier0_gateway.nsx-t0.path
  subnet {
    cidr = var.nsx.overlay1_gw_cidr
  }
  depends_on = [data.nsxt_policy_host_transport_node_collection_realization.htnc1_realization]
}

# The remaining segments will hang off of the T1
resource "nsxt_policy_segment" "segment2" {
  display_name        = "segment2"
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_transport_zone.path
  connectivity_path = nsxt_policy_tier1_gateway.nsx-t1.path
  subnet {
    cidr = var.nsx.overlay2_gw_cidr
  }
  depends_on = [data.nsxt_policy_host_transport_node_collection_realization.htnc1_realization]
}

resource "nsxt_policy_segment" "segment3" {
  display_name        = "segment3"
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_transport_zone.path
  connectivity_path = nsxt_policy_tier1_gateway.nsx-t1.path
  subnet {
    cidr = var.nsx.overlay3_gw_cidr
  }
  depends_on = [data.nsxt_policy_host_transport_node_collection_realization.htnc1_realization]
}

data "nsxt_policy_segment_realization" "s1" {
  path = nsxt_policy_segment.segment1.path
}

data "nsxt_policy_segment_realization" "s2" {
  path = nsxt_policy_segment.segment2.path
}

data "nsxt_policy_segment_realization" "s3" {
  path = nsxt_policy_segment.segment3.path
}

# T0 gateway firewall rules; allow outbound, filter inbound

resource "nsxt_policy_gateway_policy" "OutboundPolicy" {
  display_name    = "OutboundPolicy"
  category        = "LocalGatewayRules"
  locked          = false
  sequence_number = 200
  stateful        = true
  tcp_strict      = false

  rule {
    display_name       = "AllowOutboundAll"
    direction          = "OUT"
    disabled           = false
    action             = "ALLOW"
    logged             = false
    sequence_number    = "100"
    scope              = [nsxt_policy_tier0_gateway.nsx-t0.path]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "nsxt_policy_group" "vpc-private" {
  display_name = "vpc-private"

  criteria {
    ipaddress_expression {
      # Note that we exclude the vMotion, vSAN, TEP, and overlay subnets
      # The overlay does not need to intercommunicate with them
      ip_addresses = [var.nsx.management_cidr]
    }
  }
}

resource "nsxt_policy_gateway_policy" "InboundPolicy" {
  display_name    = "InboundPolicy"
  category        = "LocalGatewayRules"
  locked          = false
  sequence_number = 100
  stateful        = true
  tcp_strict      = false

  rule {
    display_name    = "AllowInboundPrivate"
    source_groups   = [nsxt_policy_group.vpc-private.path]
    direction       = "IN"
    disabled        = false
    action          = "ALLOW"
    logged          = false
    sequence_number = "100"
    scope           = [nsxt_policy_tier0_gateway.nsx-t0.path]
  }

  rule {
    display_name       = "DenyInboundAll"
    direction          = "IN"
    disabled           = false
    action             = "DROP"
    logged             = true
    sequence_number    = "1000"
    scope              = [nsxt_policy_tier0_gateway.nsx-t0.path]
  }

  lifecycle {
    create_before_destroy = true
  }
}

