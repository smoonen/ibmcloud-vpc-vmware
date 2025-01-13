Set-PowerCliConfiguration -InvalidCertificateAction Ignore

# Source inventory data
. .\inventory.ps1

# Loop through hosts
foreach($esxi in $hosts) {
  # Connect first to PCI interface
  Connect-VIServer -Server $esxi.pci -User root -Password $esxi.password

  # Create a new portgroup for the management VLAN and correct the VLAN for the VM portgroup
  Get-VirtualPortGroup -Name "Management Network" | Set-VirtualPortGroup -Name "Old Management Network"
  New-VirtualPortGroup -VirtualSwitch vSwitch0 -Name "Management Network" -VLANId 1
  Get-VirtualPortGroup -Name "VM Network" | Set-VirtualPortGroup -VLANId 1

  # Unfortunately, Set-VMHostNetworkAdapter supports only DVPGs and not VPGs; therefore we have to create a new vmknic.
  # If you're using SDK instead you can probably work around this.
  New-VMHostNetworkAdapter -VirtualSwitch vSwitch0 -PortGroup "Management Network" -IP $esxi.vlan -SubnetMask 255.255.255.0 -ManagementTrafficEnabled $true -MTU 1500
  # Now reconnect to this vmk
  Connect-ViServer -Server $esxi.vlan -User root -Password $esxi.password
  Get-VMHostNetworkAdapter -Name vmk0 | Remove-VMHostNetworkAdapter -Confirm:$false
  Get-VirtualPortGroup -Name "Old Management Network" | Remove-VirtualPortGroup -Confirm:$false

  # The following assumes that the DNS service has already been created, configured, and connected to this VPC
  Get-VMHostNetworkStack -Name defaultTcpipStack | Set-VMHostNetworkStack -DNSAddress 161.26.0.7,161.26.0.8 -DomainName example.com -HostName $esxi.name
  New-VMHostRoute -Destination 0.0.0.0 -PrefixLength 0 -Gateway 192.168.1.1 -Confirm:$false
  Add-VMHostNTPServer -NTPServer 161.26.0.6
}

