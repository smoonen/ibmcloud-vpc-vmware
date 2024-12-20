Set-PowerCliConfiguration -InvalidCertificateAction Prompt

# Source inventory data
. .\inventory.ps1

#######################
# Connect to first host
Connect-VIServer -Server $host1_pci -User root -Password $host1_password

# Create a new portgroup for the management VLAN and correct the VLAN for the VM portgroup
Get-VirtualPortGroup -Name "Management Network" | Set-VirtualPortGroup -Name "Old Management Network"
New-VirtualPortGroup -VirtualSwitch vSwitch0 -Name "Management Network" -VLANId 1
Get-VirtualPortGroup -Name "VM Network" | Set-VirtualPortGroup -VLANId 1

# Unfortunately, Set-VMHostNetworkAdapter supports only DVPGs and not VPGs; therefore we have to create a new vmknic.
# If you're using SDK instead you can probably work around this.
New-VMHostNetworkAdapter -VirtualSwitch vSwitch0 -PortGroup "Management Network" -IP $host1_vlan -SubnetMask 255.255.255.0 -ManagementTrafficEnabled $true -MTU 1500
Connect-ViServer -Server $host1_vlan -User root -Password $host1_password
Get-VMHostNetworkAdapter -Name vmk0 | Remove-VMHostNetworkAdapter
Get-VirtualPortGroup -Name "Old Management Network" | Remove-VirtualPortGroup

# The following assumes that the DNS service has already been created, configured, and connected to this VPC
Get-VMHostNetworkStack -Name defaultTcpipStack | Set-VMHostNetworkStack -DNSAddress 161.26.0.7,161.26.0.8 -DomainName example.com -HostName host001
New-VMHostRoute -Destination 0.0.0.0 -PrefixLength 0 -Gateway 192.168.2.1

########################
# Connect to second host
Connect-VIServer -Server $host2_pci -User root -Password $host2_password

# Create a new portgroup for the management VLAN and correct the VLAN for the VM portgroup
Get-VirtualPortGroup -Name "Management Network" | Set-VirtualPortGroup -Name "Old Management Network"
New-VirtualPortGroup -VirtualSwitch vSwitch0 -Name "Management Network" -VLANId 1
Get-VirtualPortGroup -Name "VM Network" | Set-VirtualPortGroup -VLANId 1

# Unfortunately, Set-VMHostNetworkAdapter supports only DVPGs and not VPGs; therefore we have to create a new vmknic.
# If you're using SDK instead you can probably work around this.
New-VMHostNetworkAdapter -VirtualSwitch vSwitch0 -PortGroup "Management Network" -IP $host2_vlan -SubnetMask 255.255.255.0 -ManagementTrafficEnabled $true -MTU 1500
Connect-ViServer -Server $host2_vlan -User root -Password $host2_password
Get-VMHostNetworkAdapter -Name vmk0 | Remove-VMHostNetworkAdapter
Get-VirtualPortGroup -Name "Old Management Network" | Remove-VirtualPortGroup

# The following assumes that the DNS service has already been created, configured, and connected to this VPC
Get-VMHostNetworkStack -Name defaultTcpipStack | Set-VMHostNetworkStack -DNSAddress 161.26.0.7,161.26.0.8 -DomainName example.com -HostName host002
New-VMHostRoute -Destination 0.0.0.0 -PrefixLength 0 -Gateway 192.168.2.1

#######################
# Connect to third host
Connect-VIServer -Server $host3_pci -User root -Password $host3_password

# Create a new portgroup for the management VLAN and correct the VLAN for the VM portgroup
Get-VirtualPortGroup -Name "Management Network" | Set-VirtualPortGroup -Name "Old Management Network"
New-VirtualPortGroup -VirtualSwitch vSwitch0 -Name "Management Network" -VLANId 1
Get-VirtualPortGroup -Name "VM Network" | Set-VirtualPortGroup -VLANId 1

# Unfortunately, Set-VMHostNetworkAdapter supports only DVPGs and not VPGs; therefore we have to create a new vmknic.
# If you're using SDK instead you can probably work around this.
New-VMHostNetworkAdapter -VirtualSwitch vSwitch0 -PortGroup "Management Network" -IP $host3_vlan -SubnetMask 255.255.255.0 -ManagementTrafficEnabled $true -MTU 1500
Connect-ViServer -Server $host3_vlan -User root -Password $host3_password
Get-VMHostNetworkAdapter -Name vmk0 | Remove-VMHostNetworkAdapter
Get-VirtualPortGroup -Name "Old Management Network" | Remove-VirtualPortGroup

# The following assumes that the DNS service has already been created, configured, and connected to this VPC
Get-VMHostNetworkStack -Name defaultTcpipStack | Set-VMHostNetworkStack -DNSAddress 161.26.0.7,161.26.0.8 -DomainName example.com -HostName host003
New-VMHostRoute -Destination 0.0.0.0 -PrefixLength 0 -Gateway 192.168.2.1

