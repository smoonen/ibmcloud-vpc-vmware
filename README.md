# VMware in IBM Cloud VPC

I created this project to explore the IBM Cloud VPC SDK and also to experiment with how ESXi behaves in IBM Cloud VPC.

## Prerequisites
Install packages `ibm-vpc`, `ibm-cloud-networking-services`, and `sshkey-tools`.

## Files
- `inventory.py` - you must create this file yourself; some notable initial variables are as follows:
  - `api_key` - IBM Cloud API key with sufficient permissions to manage VPC and DNS resources
  - `allowed_ips` - a list of allowed IPs for your bastion VSI
- `vpc_lib.py` - contains a helper class for rudimentary idempotency; defaults to London
- `create-vpc.py` - create a VPC and networks; after completion you should add the output to `inventory.py`
- `create-bastion.py` - create a Windows bastion VSI with access restricted to known source IPs; after completion you should add the RSA private key to `inventory.py`
- `create-metals.py` - create three bare metal ESXi servers; note that the ESXi image id is not published; variables from here should go in `inventory.py` and `inventory.ps1`
- `inventory.ps1` - inventory for PowerShell
- `collect-macs.ps1` - run this to inventory MAC addresses on hosts; add to `inventory.py`
- `correct-pcis.py` - run this to adjust the PCI allowed VLANs according to the order in which they were attached to each host
- `server-initialization.ps1` - basic initialization script for hosts; further configuration done in vCenter

## Interface and addressing scheme

I am creating five vmnics (PCI interfaces) on each host. My goal is to enable performance testing of multiple paths to the smartNIC:

- Two for management (enabling straightforward conversion between standard and distributed switches)
- One for vMotion
- One for vSAN
- One for TEPs
- One for uplinks

For the latter vmnics, it is tempting to use the PCI IP address for the corresponding vmknic. However, PCI interfaces are coupled to the MAC address assigned by IBM Cloud, and it is difficult to customize the MAC address of a vmknic. Therefore, my addressing scheme assigns throwaway IP addresses to the PCI interfaces and will use VLAN interfaces for all vmknics. Since link-local addresses are reserved by IBM Cloud, I use the range 172.16.0.0/24. (If you are familiar with IBM Cloud classic networking, you may recall that throwaway IP addresses are used there for the public interfaces of hosts.)

Here is my vmknic and virtual machine addressing scheme:

- [vmk1] Management (also used for management VMs like vCenter) - 192.168.2.0/24, VLAN 2
- [vmk0] vMotion - 192.168.3.0/24, VLAN 3
- [vmk2] vSAN - 192.168.4.0/24, VLAN 4
- TEPs (also used for edges) - 192.168.5.0/24, VLAN 5
- Uplinks (used exclusively for edges and not for vmknic) - 192.168.6.0/24, VLAN 6

The vmknic ids are reversed because my simplistic way of moving the host's management IP results in recreating the management vmknic.

Note that, other than vmnic0, ESXi does not necessarily perceive the physical interfaces in the same order that they were supplied at the time the bare metal server was created. Since it is difficult to customize the MAC address for a vmnic (in order to force the expected order), I take the approach instead of discovering the order after the host is provisioned. What this means is that I must customize the list of allowed VLANs on each PCI subsequent to creating the bare metal.

Note also that the host management VLAN interface must be configured to allow floating. Movement between different PCI interfaces on a host is considered floating.

