Set-PowerCliConfiguration -InvalidCertificateAction Ignore -DefaultVIServerMode Single -ParticipateInCeip:$false -Confirm:$false

# Load inventory data
$inventory = (Get-Content inventory.json | ConvertFrom-Json)

# Loop through hosts
$inventory.bare_metals | Get-Member -Type NoteProperty | ForEach-Object {
  $esxi = $_.Name

  # Connect first to PCI interface
  Connect-VIServer -Server $inventory.subnets.pci.reservations."$esxi-management".ip -User root -Password $inventory.bare_metals.$esxi.password

  # Create a new portgroup for the management VLAN and correct the VLAN for the VM portgroup
  Get-VirtualPortGroup -Name "Management Network" | Set-VirtualPortGroup -Name "Old Management Network"
  New-VirtualPortGroup -VirtualSwitch vSwitch0 -Name "Management Network" -VLANId $inventory.vlans.management
  Get-VirtualPortGroup -Name "VM Network" | Set-VirtualPortGroup -VLANId $inventory.vlans.management

  # Unfortunately, Set-VMHostNetworkAdapter supports only DVPGs and not VPGs; therefore we have to create a new vmknic.
  # If you're using SDK instead you can probably work around this.
  New-VMHostNetworkAdapter -VirtualSwitch vSwitch0 -PortGroup "Management Network" -IP $inventory.subnets.management.reservations.$esxi.ip -SubnetMask $inventory.subnets.management.netmask -ManagementTrafficEnabled $true -MTU 1500
  # Now reconnect to this vmk
  Connect-ViServer -Server $inventory.subnets.management.reservations.$esxi.ip -User root -Password $inventory.bare_metals.$esxi.password
  Get-VMHostNetworkAdapter -Name vmk0 | Remove-VMHostNetworkAdapter -Confirm:$false
  Get-VirtualPortGroup -Name "Old Management Network" | Remove-VirtualPortGroup -Confirm:$false

  # The following assumes that the DNS service has already been created, configured, and connected to this VPC
  Get-VMHostNetworkStack -Name defaultTcpipStack | Set-VMHostNetworkStack -DNSAddress 161.26.0.7,161.26.0.8 -DomainName example.com -HostName $esxi
  New-VMHostRoute -Destination 0.0.0.0 -PrefixLength 0 -Gateway $inventory.subnets.management.gateway -Confirm:$false
  Add-VMHostNTPServer -NTPServer 161.26.0.6
}

