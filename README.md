# VMware in IBM Cloud VPC

I created this project to explore the IBM Cloud VPC SDK and also to experiment with how ESXi behaves in IBM Cloud VPC.

## Prerequisites
Install Python packages `ibm-vpc`, `ibm-cloud-networking-services`, `jinja2`, and `sshkey-tools`.

## Files

### Helpers

- `inventory.json.template` - copy to `inventory.json` and fill out initial fields. New data will be written to the `inventory.json` file as you run various scripts.
- Libraries and helper scripts
  - [vpc_lib.py](vpc_lib.py) - contains a helper class for rudimentary idempotency; defaults to London
  - [inventory.py](inventory.py) - helper methods to serialize configuration and inventory data to JSON file
  - [reinitialize-metals.py](reinitialize-metals.py) - reinitialize bare metal servers to perform fresh testing
  - [start-ssh.ps1](start-ssh.ps1) - Helper script to start SSH and ESXi shell services on hosts
- `templates/`
  - [vcsa-deploy.json](templates/vcsa-deploy.json) - Jinja2 template for VCSA install JSON
  - [variables.tf](templates/variables.tf) - will be used to generate Terraform variables

### Scripts (in order)
1. [create-vpc.py](create-vpc.py) - create a VPC and networks
2. [create-bastion.py](create-bastion.py) - create a Windows bastion VSI with access restricted to known source IPs
3. [create-metals.py](create-metals.py) - create three bare metal ESXi servers and all needed VNIs; note that the ESXi image id is not published
4. [collect-macs.ps1](collect-macs.ps1) - run this to inventory MAC addresses on hosts
5. [correct-pcis.py](correct-pcis.py) - run this to adjust the PCI allowed VLANs according to the order in which they were attached to each host
6. [server-initialization.ps1](server-initialization.ps1) - basic initialization script for hosts; further configuration done in vCenter
7. [generate-vcenter-json.py](generate-vcenter-json.py) - generate JSON to deploy vcenter
8. [deploy-vcsa.ps1](deploy-vcsa.ps1) - deploy VCSA appliance to host001
9. [configure-cluster.ps1](configure-cluster.ps1) - create and configure ESA cluster
10. [deploy-nsx.ps1](deploy-nsx.ps1) - deploy and configure NSX cluster
11. [generate-terraform.py](generate-terraform.py) - generate `variables.tf` file for Terraform
12. [terraform.tf](terraform.tf) - Tearraform provider specification; the plan is outlined in:
  - [main.tf](main.tf) - apply Terraform plan to configure NSX for hosts, segment, and edges
  - [vms.tf](vms.tf) and [ubuntu-userdata.yml](ubuntu-userdata.yml) - subsequent to edge configuration, deploy test VMs to each segment
13. [deploy-avi.ps1](deploy-avi.ps1) - deploy Avi controllers

## VPC interface and addressing scheme

I am creating five vmnics (PCI interfaces) on each host. My goal is to enable performance testing of multiple paths to the smartNIC:

- One for management (given the smartNIC, two are not needed for redundancy; the only downside with one is that switch conversion involves a "dark side of the moon")
- One for vMotion
- One for vSAN
- One for TEPs
- One for uplinks

It is tempting to use the PCI IP address for the corresponding vmknic. However, PCI interfaces are coupled to the MAC address assigned by IBM Cloud, and it is difficult to customize the MAC address of a vmknic. Therefore, my addressing scheme assigns throwaway IP addresses to the PCI interfaces and will use VLAN interfaces for all vmknics. Since link-local addresses are reserved by IBM Cloud, I use the range 172.16.150.0/24. (If you are familiar with IBM Cloud classic networking, you may recall that throwaway IP addresses are used there for the public interfaces of hosts.)

Here is my vmknic and virtual machine addressing scheme:

- [vmk1] Management (also used for management VMs like vCenter) - 192.168.151.0/24, VLAN 1
- [vmk0] vMotion - 192.168.152.0/24, VLAN 2
- [vmk2] vSAN - 192.168.153.0/24, VLAN 3
- TEPs (also used for edges) - 192.168.154.0/24, VLAN 4
- Uplinks (used exclusively for edges and not for vmknic) - 192.168.155.0/24, VLAN 5

The first two vmknic ids are reversed because of the migration of the host IPs from the PCI interface to a VLAN interface. Recent versions of the scripts now allow you to customize the VLAN numbers and subnet ranges by editing the `inventory.json` file.

Note that, other than vmnic0, ESXi does not necessarily perceive the physical interfaces in the same order that they were supplied at the time the bare metal server was created. Since it is difficult to customize the MAC address for a vmnic (in order to force the expected order), I take the approach instead of discovering the order after the host is provisioned. What this means is that I must customize the list of allowed VLANs on each PCI subsequent to creating the bare metal.

## NSX overlay scheme

The automation creates VPC routes to the NSX T0 VIP for the subnets in use on the overlay. The T0 itself has a default route back to the VPC. The network structure is as follows:

- VPC: 192.168.151.0 - 192.168.155.255
  - T0
    - segment-1: 192.168.161.0/24, virtual machine `ubuntu1` is deployed here
    - T1
      - segment-2: 192.168.162.0/24, virtual machine `ubuntu2` is deployed here
      - segment-3: 192.168.163.0/24, virtual machine `ubuntu3` is deployed here

