# Data collection

data "vsphere_resource_pool" "default" {
  name          = "london/Resources"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_host" "host" {
  name          = "host001.example.com"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "n1" {
  name          = data.nsxt_policy_segment_realization.s1.network_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "n2" {
  name          = data.nsxt_policy_segment_realization.s2.network_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "n3" {
  name          = data.nsxt_policy_segment_realization.s3.network_name
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

resource "terraform_data" "network_ids" {
  input = {
    ubuntu1 = {
      network_id = data.vsphere_network.n1.id
    }
    ubuntu2 = {
      network_id = data.vsphere_network.n2.id
    }
    ubuntu3 = {
      network_id = data.vsphere_network.n3.id
    }
  }
}

# Ubuntu source

data "vsphere_ovf_vm_template" "ovf-ubuntu-24-04-lts" {
  name                      = "ubuntu-server-24-04-lts"
  disk_provisioning         = "thin"
  resource_pool_id          = data.vsphere_resource_pool.default.id
  datastore_id              = data.vsphere_datastore.datastore.id
  host_system_id            = data.vsphere_host.host.id
  remote_ovf_url            = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.ova"
  allow_unverified_ssl_cert = true
}

# Userdata template

data "template_file" "userdata" {
  for_each = var.vm_settings
  template = file("${path.module}/ubuntu-userdata.yml")
  vars = {
    name           = each.key
    ipv4_address   = each.value.ipv4_address
    ipv4_gateway   = each.value.ipv4_gateway
    ipv4_prefixlen = each.value.ipv4_prefixlen
  }
}

# Deploy the VMs

resource "random_uuid" "vm_uuid" {
  for_each = var.vm_settings
}

resource "vsphere_virtual_machine" "ubuntu_vms" {
  for_each             = var.vm_settings
  name                 = each.key
  datacenter_id        = data.vsphere_datacenter.datacenter.id
  host_system_id       = data.vsphere_host.host.id
  resource_pool_id     = data.vsphere_resource_pool.default.id
  datastore_id         = data.vsphere_datastore.datastore.id
  num_cpus             = data.vsphere_ovf_vm_template.ovf-ubuntu-24-04-lts.num_cpus
  num_cores_per_socket = data.vsphere_ovf_vm_template.ovf-ubuntu-24-04-lts.num_cores_per_socket
  memory               = data.vsphere_ovf_vm_template.ovf-ubuntu-24-04-lts.memory
  guest_id             = data.vsphere_ovf_vm_template.ovf-ubuntu-24-04-lts.guest_id
  firmware             = data.vsphere_ovf_vm_template.ovf-ubuntu-24-04-lts.firmware
  scsi_type            = data.vsphere_ovf_vm_template.ovf-ubuntu-24-04-lts.scsi_type
  network_interface {
    network_id   = terraform_data.network_ids.output[each.key].network_id
    adapter_type = "vmxnet3"
  }
  cdrom {
    client_device = true
  }
  disk {
    label            = "disk0"
    size             = 100
    thin_provisioned = true
  }
  ovf_deploy {
    allow_unverified_ssl_cert = true
    remote_ovf_url            = data.vsphere_ovf_vm_template.ovf-ubuntu-24-04-lts.remote_ovf_url
  }
  vapp {
    properties = {
      "hostname"    = each.key
      "instance-id" = random_uuid.vm_uuid[each.key].result
      "public-keys" = var.ssh_authorized_key
      "user-data"   = base64encode(data.template_file.userdata[each.key].rendered)
    }
  }

  wait_for_guest_ip_timeout = 10
  lifecycle {
    ignore_changes = [vapp[0].properties, host_system_id, num_cores_per_socket, disk[0].io_share_count]
  }
}

resource "vsphere_compute_cluster_vm_anti_affinity_rule" "ubuntu_anti_affinity_rule" {
  name                = "ubuntu-anti-affinity-rule"
  compute_cluster_id  = data.vsphere_compute_cluster.compute_cluster.id
  virtual_machine_ids = [for k, v in vsphere_virtual_machine.ubuntu_vms : v.id]

  lifecycle {
    replace_triggered_by = [vsphere_virtual_machine.ubuntu_vms]
  }
}
