# VMware in IBM Cloud VPC

I created this project to explore the IBM Cloud VPC SDK and also to experiment with how ESXi behaves in IBM Cloud VPC.

## Prerequisites
Install packages `ibm-vpc` and `sshkey-tools`.

## Files
- `inventory.py` - you must create this file yourself and minimally set the `api_key` variable to an IBM Cloud API key with sufficient permissions to create all the necessary VPC resources, and `allowed_ips` to a list of allowed IPs for your bastion VSI
- `vpc_lib.py` - contains a helper class for rudimentary idempotency; defaults to London
- `create-vpc.py` - create a VPC and networks; after completion you should add the output to `inventory.py`
- `create-bastion.py` - create a Windows bastion VSI with access restricted to known source IPs; after completion you should add the RSA private key to `inventory.py`
- `create-metals.py` - create three bare metal ESXi servers; note that the ESXi image id is not published

