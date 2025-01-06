# Inspired by https://github.com/vmware-nsx/dcinabox_terraform/

provider "nsxt" {
  host                 = var.nsx["fqdn"]
  username             = var.nsx["username"]
  password             = var.nsx["password"]
  allow_unverified_ssl = true
  max_retries          = 2
}

provider "vsphere" {
  vsphere_server       = var.vcenter["fqdn"]
  user                 = var.vcenter["username"]
  password             = var.vcenter["password"]
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

data "vsphere_network" "dpg_tep" {
  name          = "dpg-tep"
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
  cidr         = "192.168.5.0/24"
  gateway      = "192.168.5.1"

  allocation_range {
    start = var.tep_ips[0]
    end   = var.tep_ips[0]
  }

  allocation_range {
    start = var.tep_ips[1]
    end   = var.tep_ips[1]
  }

  allocation_range {
    start = var.tep_ips[2]
    end   = var.tep_ips[2]
  }

  allocation_range {
    start = var.tep_ips[3]
    end   = var.tep_ips[3]
  }

  allocation_range {
    start = var.tep_ips[4]
    end   = var.tep_ips[4]
  }

  allocation_range {
    start = var.tep_ips[5]
    end   = var.tep_ips[5]
  }

  allocation_range {
    start = var.tep_ips[6]
    end   = var.tep_ips[6]
  }

  allocation_range {
    start = var.tep_ips[7]
    end   = var.tep_ips[7]
  }

  allocation_range {
    start = var.tep_ips[8]
    end   = var.tep_ips[8]
  }

  allocation_range {
    start = var.tep_ips[9]
    end   = var.tep_ips[9]
  }
}

# IP Pool for overlay segment

resource "nsxt_policy_ip_pool" "pool2" {
  display_name = "overlay-pool"
  description  = "Overlay segment IPs"
}

resource "nsxt_policy_ip_pool_static_subnet" "static_subnet2" {
  display_name = "overlay-pool-subnet"
  pool_path    = nsxt_policy_ip_pool.pool2.path
  cidr         = "10.1.1.0/24"
  gateway      = "10.1.1.1"

  allocation_range {
    start = "10.1.1.2"
    end   = "10.1.1.254"
  }

}

# Hosts / transport nodes

resource "nsxt_policy_uplink_host_switch_profile" "esxi_uplink_profile" {
  display_name = "esxi_uplink_profile"

  transport_vlan = 5
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

# Overlay segment

resource "nsxt_policy_segment" "segment1" {
  display_name        = "segment-10-1-1"
  transport_zone_path = data.nsxt_policy_transport_zone.overlay_transport_zone.path
  subnet {
    cidr = "10.1.1.1/24"
  }
  advanced_config {
    address_pool_path = nsxt_policy_ip_pool.pool2.path
  }
  depends_on = [data.nsxt_policy_host_transport_node_collection_realization.htnc1_realization]
}

# Edge nodes and cluster

resource "nsxt_policy_transport_zone" "vlan_transport_zone_edge" {
  display_name   = "VLAN-EDGE"
  transport_type = "VLAN_BACKED"
  uplink_teaming_policy_names = ["uplink_1_only" , "uplink_2_only"]
}

resource "nsxt_policy_uplink_host_switch_profile" "edge_tep_uplink_profile" {
  display_name = "edge_tep_uplink_profile"

  mtu            = 9000
  transport_vlan = 5
  overlay_encap  = "GENEVE"

  teaming {
    active {
      uplink_name = "uplink1"
      uplink_type = "PNIC"
    }
    policy = "LOADBALANCE_SRCID"
  }
}

resource "nsxt_policy_uplink_host_switch_profile" "edge_uplink_profile" {
  display_name = "edge_uplink_profile"
  mtu          = 9000
  teaming {
    active {
      uplink_name = "uplink1"
      uplink_type = "PNIC"
    }
    policy = "FAILOVER_ORDER"
  }

  named_teaming {
    active {
      uplink_name = "uplink1"
      uplink_type = "PNIC"
    }
    policy = "FAILOVER_ORDER"
    name   = "uplink_1_only"
  }

  named_teaming {
    active {
      uplink_name = "uplink2"
      uplink_type = "PNIC"
    }
    policy = "FAILOVER_ORDER"
    name   = "uplink_2_only"
  }
}

resource "nsxt_edge_transport_node" "edge_node0" {
  description  = "Primary edge node"
  display_name = "edge-node-0"
  standard_host_switch {
    ip_assignment {
      static_ip_pool = nsxt_policy_ip_pool.pool1.realized_id
    }
    transport_zone_endpoint {
      transport_zone = data.nsxt_policy_transport_zone.overlay_transport_zone.id
    }
    transport_zone_endpoint {
      transport_zone = nsxt_policy_transport_zone.vlan_transport_zone_edge.realized_id
    }
    host_switch_profile = [nsxt_policy_uplink_host_switch_profile.edge_uplink_profile.realized_id]
    pnic {
      device_name = "fp-eth0"
      uplink_name = "uplink1"
    }
    pnic {
      device_name = "fp-eth1"
      uplink_name = "uplink2"
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
      data_network_ids      = [data.vsphere_network.dpg_tep.id, data.vsphere_network.dpg_uplink.id]
      compute_id            = data.vsphere_compute_cluster.compute_cluster.id
      storage_id            = data.vsphere_datastore.datastore.id
      vc_id                 = data.nsxt_compute_manager.vcenter.id
      management_port_subnet {
        ip_addresses  = [var.nsx.edge0]
        prefix_length = 24
      }
      default_gateway_address = ["192.168.2.1"]
    }
  }
  node_settings {
    hostname             = "edge0.example.com"
    dns_servers          = ["161.26.0.7", "161.26.0.8"]
    ntp_servers          = ["161.26.0.6"]
    allow_ssh_root_login = true
    enable_ssh           = true
  }
}

resource "nsxt_edge_transport_node" "edge_node1" {
  description  = "Secondary edge node"
  display_name = "edge-node-1"
  standard_host_switch {
    ip_assignment {
      static_ip_pool = nsxt_policy_ip_pool.pool1.realized_id
    }
    transport_zone_endpoint {
      transport_zone = data.nsxt_policy_transport_zone.overlay_transport_zone.id
    }
    transport_zone_endpoint {
      transport_zone = nsxt_policy_transport_zone.vlan_transport_zone_edge.realized_id
    }
    host_switch_profile = [nsxt_policy_uplink_host_switch_profile.edge_uplink_profile.realized_id]
    pnic {
      device_name = "fp-eth0"
      uplink_name = "uplink1"
    }
    pnic {
      device_name = "fp-eth1"
      uplink_name = "uplink2"
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
      data_network_ids      = [data.vsphere_network.dpg_tep.id, data.vsphere_network.dpg_uplink.id]
      compute_id            = data.vsphere_compute_cluster.compute_cluster.id
      storage_id            = data.vsphere_datastore.datastore.id
      vc_id                 = data.nsxt_compute_manager.vcenter.id
      management_port_subnet {
        ip_addresses  = [var.nsx.edge1]
        prefix_length = 24
      }
      default_gateway_address = ["192.168.2.1"]
    }
  }
  node_settings {
    hostname             = "edge1.example.com"
    dns_servers          = ["161.26.0.7", "161.26.0.8"]
    ntp_servers          = ["161.26.0.6"]
    allow_ssh_root_login = true
    enable_ssh           = true
  }
}

data "nsxt_transport_node_realization" "edge_node0_realization" {
  id      = nsxt_edge_transport_node.edge_node0.id
  timeout = 3000
}

data "nsxt_transport_node_realization" "edge_node1_realization" {
  id      = nsxt_edge_transport_node.edge_node1.id
  timeout = 3000
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

