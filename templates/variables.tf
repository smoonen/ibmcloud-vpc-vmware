variable "vcenter" {
  type = map(string)
  default = {
    fqdn       = "vcenter.example.com"
    username   = "administrator@vsphere.local"
    password   = "{{ inventory.passwords.vcenter_administrator }}"
  }
}

variable "nsx" {
  type = map(string)
  default = {
    fqdn             = "nsx.example.com"
    username           = "admin"
    password           = "{{ inventory.passwords.nsx_admin }}"
    cli_password       = "{{ inventory.passwords.nsx_cli_admin }}"
    audit_password     = "{{ inventory.passwords.nsx_cli_audit }}"
    vdefend_key        = "{{ inventory.license_keys.vdefend }}"
    management_cidr    = "{{ inventory.subnets.management.cidr }}"
    tep_cidr           = "{{ inventory.subnets.tep.cidr }}"
    tep_gateway        = "{{ inventory.subnets.tep.gateway }}"
    tep_first          = "{{ inventory.subnets.tep.reservations.tep0.ip }}"
    tep_last           = "{{ inventory.subnets.tep.reservations.tep9.ip }}"
    tep_vlan           = {{ inventory.vlans.tep }}
    edge0              = "{{ inventory.subnets.management.reservations.edge0.ip }}"
    edge1              = "{{ inventory.subnets.management.reservations.edge1.ip }}"
    edge_prefixlen     = {{ inventory.subnets.management.prefixlen }}
    edge_gateway       = "{{ inventory.subnets.management.gateway }}"
    edgeuplink_0       = "{{ inventory.subnets.uplink.reservations.uplink0.ip }}/{{ inventory.subnets.uplink.prefixlen }}"
    edgeuplink_1       = "{{ inventory.subnets.uplink.reservations.uplink1.ip }}/{{ inventory.subnets.uplink.prefixlen }}"
    edgeuplink_vip     = "{{ inventory.subnets.uplink.reservations.vip.ip }}/{{ inventory.subnets.uplink.prefixlen }}"
    uplink_gateway     = "{{ inventory.subnets.uplink.gateway }}"
    snat_ip            = "{{ inventory.subnets.uplink.reservations.vip.ip }}"
    overlay1_gw_cidr   = "{{ inventory.subnets.overlay1.gateway }}/{{ inventory.subnets.overlay1.prefixlen }}"
    overlay2_gw_cidr   = "{{ inventory.subnets.overlay2.gateway }}/{{ inventory.subnets.overlay2.prefixlen }}"
    overlay3_gw_cidr   = "{{ inventory.subnets.overlay3.gateway }}/{{ inventory.subnets.overlay3.prefixlen }}"
  }
}

variable "ssh_authorized_key" {
  type = string
  default = "{{ inventory.bastion_pubkey }}"
}

variable "vm_settings" {
  type    = map(any)
  default = {
    ubuntu1 = {
      ipv4_address   = "{{ inventory.subnets.overlay1.reservations.ubuntu1.ip }}"
      ipv4_gateway   = "{{ inventory.subnets.overlay1.gateway }}"
      ipv4_prefixlen = {{ inventory.subnets.overlay1.prefixlen }}
    }
    ubuntu2 = {
      ipv4_address   = "{{ inventory.subnets.overlay2.reservations.ubuntu2.ip }}"
      ipv4_gateway   = "{{ inventory.subnets.overlay2.gateway }}"
      ipv4_prefixlen = {{ inventory.subnets.overlay2.prefixlen }}
    }
    ubuntu3 = {
      ipv4_address   = "{{ inventory.subnets.overlay3.reservations.ubuntu3.ip }}"
      ipv4_gateway   = "{{ inventory.subnets.overlay3.gateway }}"
      ipv4_prefixlen = {{ inventory.subnets.overlay3.prefixlen }}
    }
  }
}

