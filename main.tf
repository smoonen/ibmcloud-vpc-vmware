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

data "vsphere_distributed_virtual_switch" "vds" {
  name          = "dswitch-tep"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "nsxt_policy_transport_zone" "overlay_transport_zone" {
  display_name = "nsx-overlay-transportzone"
}

data "nsxt_policy_transport_zone" "vlan_transport_zone" {
  display_name = "nsx-vlan-transportzone"
}

data "nsxt_policy_uplink_host_switch_profile" "host_uplink_profile" {
  display_name = "nsx-default-uplink-hostswitch-profile"
}

data "nsxt_compute_collection" "compute_cluster_collection" {
  display_name = "london"
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

# Hosts / transport nodes

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
    host_switch_profile = [data.nsxt_policy_uplink_host_switch_profile.host_uplink_profile.path]
    is_migrate_pnics    = false
    uplink {
      uplink_name     = "uplink-1"
      vds_uplink_name = "dvUplink1"
    }
  }
}

resource "nsxt_policy_host_transport_node_collection" "htnc1" {
  display_name                = "htnc1"
  compute_collection_id       = data.nsxt_compute_collection.compute_cluster_collection.id
  transport_node_profile_path = nsxt_policy_host_transport_node_profile.tnp.path
}

