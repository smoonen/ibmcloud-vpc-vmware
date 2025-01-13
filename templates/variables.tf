variable "vcenter" {
  type = map(string)
  default = {
    fqdn       = "vcenter.example.com"
    username   = "administrator@vsphere.local"
    password   = "{{ inventory.vcenter_sso_password }}"
  }
}

variable "nsx" {
  type = map(string)
  default = {
    fqdn           = "nsx.example.com"
    username       = "admin"
    password       = "{{ inventory.nsx_password }}"
    cli_password   = "{{ inventory.nsx_cli_password }}"
    audit_password = "{{ inventory.nsx_cli_audit_password }}"
    vdefend_key    = "{{ inventory.vdefend_key }}"
    edge0          = "{{ inventory.nsxedge0_ip }}"
    edge1          = "{{ inventory.nsxedge1_ip }}"
    edgeuplink_0   = "{{ inventory.edgeuplink_0 }}/24"
    edgeuplink_1   = "{{ inventory.edgeuplink_1 }}/24"
    edgeuplink_vip = "{{ inventory.edgeuplink_vip }}/24"
    snat_ip        = "{{ inventory.edgeuplink_vip }}"
  }
}

variable "ssh_authorized_key" {
  type = string
  default = "{{ inventory.bastion_pubkey }}"
}

