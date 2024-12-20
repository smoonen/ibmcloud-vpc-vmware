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
- `create-metals.py` - create three bare metal ESXi servers; note that the ESXi image id is not published
- `inventory.ps1` - inventory for PowerShell; minimally create the following variables:
  - `$host1_pci` - vmnic0 IP (initial IP) for host1
  - `$host1_vlan` - vmk0 IP (final IP) for host1
  - `$host1_password` - password for host1
  - `$host2_pci` - vmnic0 IP (initial IP) for host2
  - `$host2_vlan` - vmk0 IP (final IP) for host2
  - `$host2_password` - password for host2
  - `$host3_pci` - vmnic0 IP (initial IP) for host3
  - `$host3_vlan` - vmk0 IP (final IP) for host3
  - `$host3_password` - password for host3
- `server-initialization.ps1` - basic initialization script for hosts; further configuration done in vCenter
