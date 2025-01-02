# VMware in IBM Cloud VPC

I created this project to explore the IBM Cloud VPC SDK and also to experiment with how ESXi behaves in IBM Cloud VPC.

## Prerequisites
Install packages `ibm-vpc`, `ibm-cloud-networking-services`, `jinja2`, and `sshkey-tools`.

## Files

### Helpers

- `inventory.py` - you must create this file yourself; some notable initial variables are as follows:
  - `api_key` - IBM Cloud API key with sufficient permissions to manage VPC and DNS resources
  - `allowed_ips` - a list of allowed IPs for your bastion VSI
- `inventory.ps1` - you must create this file as well; inventory for PowerShell
- [vpc_lib.py](vpc_lib.py) - contains a helper class for rudimentary idempotency; defaults to London
- [start-ssh.ps1](start-ssh.ps1) - Helper script to start SSH and ESXi shell services on hosts
- [terraform.tf](terraform.tf) - needed to install NSX provider
- `templates/`
  - [vcsa-deploy.json](templates/vcsa-deploy.json) - Jinja2 template for VCSA install JSON
  - [variables.tf](templates/variables.tf) - will be used to generate Terraform variables

### Scripts (in order)
1. [create-vpc.py](create-vpc.py) - create a VPC and networks; after completion you should add the output to `inventory.py`
2. [create-bastion.py](create-bastion.py) - create a Windows bastion VSI with access restricted to known source IPs; after completion you should add the RSA private key to `inventory.py`
3. [create-metals.py](create-metals.py) - create three bare metal ESXi servers; note that the ESXi image id is not published; variables from here should go in `inventory.py` and `inventory.ps1`
4. [collect-macs.ps1](collect-macs.ps1) - run this to inventory MAC addresses on hosts; add to `inventory.py`
5. [correct-pcis.py](correct-pcis.py) - run this to adjust the PCI allowed VLANs according to the order in which they were attached to each host
6. [manage-dns.py](manage-dns.py) - run this script to create or update DNS records for an existing DNS instance already attached to your VPC
7. [server-initialization.ps1](server-initialization.ps1) - basic initialization script for hosts; further configuration done in vCenter
8. [generate-vcenter-json.py](generate-vcenter-json.py) - generate JSON to deploy vcenter; set inventory variables `vcenter_root_password` and `vcenter_sso_password` before running
9. [deploy-vcsa.ps1](deploy-vcsa.ps1) - deploy VCSA appliance to host001
10. [configure-cluster.ps1](configure-cluster.ps1) - create and configure ESA cluster; set inventory variable `$vcenter_sso_password` before running; if variables `$vcfkey` and `$vsankey` are set, these are applied to the cluster
11. [deploy-nsx.ps1](deploy-nsx.ps1) - deploy and configure NSX cluster; before running set inventory variables `$nsx_password`, `$nsx_cli_passwd`, and `$nsx_cli_audit_password`
12. [generate-terraform.py](generate-terraform.py) - generate `variables.tf` file for Terraform; set inventory variable `nsx_password` before running
13. [main.tf](main.tf) - apply Terraform plan to configure hosts, segment, and edges

## Interface and addressing scheme

I am creating five vmnics (PCI interfaces) on each host. My goal is to enable performance testing of multiple paths to the smartNIC:

- One for management (given the smartNIC, two are not needed for redundancy; the only downside with one is that switch conversion involves a "dark side of the moon")
- One for vMotion
- One for vSAN
- One for TEPs
- One for uplinks

It is tempting to use the PCI IP address for the corresponding vmknic. However, PCI interfaces are coupled to the MAC address assigned by IBM Cloud, and it is difficult to customize the MAC address of a vmknic. Therefore, my addressing scheme assigns throwaway IP addresses to the PCI interfaces and will use VLAN interfaces for all vmknics. Since link-local addresses are reserved by IBM Cloud, I use the range 172.16.0.0/24. (If you are familiar with IBM Cloud classic networking, you may recall that throwaway IP addresses are used there for the public interfaces of hosts.)

Here is my vmknic and virtual machine addressing scheme:

- [vmk1] Management (also used for management VMs like vCenter) - 192.168.2.0/24, VLAN 2
- [vmk0] vMotion - 192.168.3.0/24, VLAN 3
- [vmk2] vSAN - 192.168.4.0/24, VLAN 4
- TEPs (also used for edges) - 192.168.5.0/24, VLAN 5
- Uplinks (used exclusively for edges and not for vmknic) - 192.168.6.0/24, VLAN 6

The first two vmknic ids are reversed because of the migration of the host IPs from the PCI interface to a VLAN interface.

Note that, other than vmnic0, ESXi does not necessarily perceive the physical interfaces in the same order that they were supplied at the time the bare metal server was created. Since it is difficult to customize the MAC address for a vmnic (in order to force the expected order), I take the approach instead of discovering the order after the host is provisioned. What this means is that I must customize the list of allowed VLANs on each PCI subsequent to creating the bare metal.

