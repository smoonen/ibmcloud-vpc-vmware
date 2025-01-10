# VM settings map

variable "vm_settings" {
  type    = map(any)
  default = {
    ubuntu11 = {
      ipv4_address = "10.1.1.2"
      ipv4_gateway = "10.1.1.1"
      network      = "segment-10-1-1"
    }
    ubuntu21 = {
      ipv4_address = "10.2.1.2"
      ipv4_gateway = "10.2.1.1"
      network      = "segment-10-2-1"
    }
    ubuntu22 = {
      ipv4_address = "10.2.2.2"
      ipv4_gateway = "10.2.2.1"
      network      = "segment-10-2-2"
    }
  }
}

# Data collection

data "vsphere_resource_pool" "default" {
  name          = "london/Resources"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_host" "host" {
  name          = "host001.example.com"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

data "vsphere_network" "network" {
  for_each      = var.vm_settings
  name          = each.value.network
  datacenter_id = data.vsphere_datacenter.datacenter.id
  depends_on    = [nsxt_policy_segment.segment1, nsxt_policy_segment.segment2, nsxt_policy_segment.segment3]
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
    name         = each.key
    ipv4_address = each.value.ipv4_address
    ipv4_gateway = each.value.ipv4_gateway
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
    network_id   = data.vsphere_network.network[each.key].id
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

