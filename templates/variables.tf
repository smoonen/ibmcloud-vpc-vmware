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
    fqdn     = "nsx.example.com"
    username = "admin"
    password = "{{ inventory.nsx_password }}"
  }
}

variable "tep_ips" {
  type = list(string)
  default = [ "{{ inventory.nsxtep0 }}", "{{ inventory.nsxtep1 }}", "{{ inventory.nsxtep2 }}", "{{ inventory.nsxtep3 }}", "{{ inventory.nsxtep4 }}", "{{ inventory.nsxtep5 }}", "{{ inventory.nsxtep6 }}", "{{ inventory.nsxtep7 }}", "{{ inventory.nsxtep8 }}", "{{ inventory.nsxtep9 }}" ]
}

