Set-PowerCliConfiguration -InvalidCertificateAction Ignore -DefaultVIServerMode Single -ParticipateInCeip:$false -Confirm:$false

# Load inventory data
$inventory = (Get-Content inventory.json | ConvertFrom-Json)

$vc = Connect-VIServer -Server vcenter.example.com -User administrator@vsphere.local -Password $inventory.passwords.vcenter_administrator

# Create datacenter
foreach($folder in Get-Folder) {
  if($folder.name -eq "Datacenters") {
    $dc_folder = $folder
  }
}
$dc = New-Datacenter -Location $dc_folder -Name ibmcloud

# Create cluster and add hosts
# Note that we do not specify -HAAdmissionControlEnabled / -HAFailoverLevel 1 only because the cluster is relatively small
$cluster = New-Cluster -Location $dc -Name london -DrsEnabled -DrsAutomationLevel FullyAutomated -HAEnabled -VsanEnabled -VsanEsaEnabled
# Loop through hosts
$inventory.bare_metals | Get-Member -Type NoteProperty | ForEach-Object {
  $esxi = $_.Name
  Add-VMHost -Location $cluster -Name "$esxi.example.com" -User root -Password $inventory.bare_metals.$esxi.password -Force
}

# Create switches
$mgmt_switch = New-VDSwitch -Location $dc -Name dswitch-mgmt -Mtu 1500 -NumUplinkPorts 1
$vmotion_switch = New-VDSwitch -Location $dc -Name dswitch-vmotion -Mtu 9000 -NumUplinkPorts 1
$vsan_switch = New-VDSwitch -Location $dc -Name dswitch-vsan -Mtu 9000 -NumUplinkPorts 1
$tep_switch = New-VDSwitch -Location $dc -Name dswitch-tep -Mtu 9000 -NumUplinkPorts 1
$uplink_switch = New-VDSwitch -Location $dc -Name dswitch-uplink -Mtu 1500 -NumUplinkPorts 1

# Add hosts to switches
$host_list = Get-VMHost
foreach($esxi in $host_list) {
  Add-VDSwitchVMHost -VDSwitch $mgmt_switch -VMHost $esxi
  Add-VDSwitchVMHost -VDSwitch $vmotion_switch -VMHost $esxi
  Add-VDSwitchVMHost -VDSwitch $vsan_switch -VMHost $esxi
  Add-VDSwitchVMHost -VDSwitch $tep_switch -VMHost $esxi
  Add-VDSwitchVMHost -VDSwitch $uplink_switch -VMHost $esxi
}

# Set allowed VLANs. Note that although this approach is deprecated, I have not been able to get Set-VDVlanConfiguration to work on uplinks.
Get-VDPortGroup -VDSwitch $mgmt_switch | Set-VDPortGroup -VlanTrunkRange "$($inventory.vlans.management)"
Get-VDPortGroup -VDSwitch $vmotion_switch | Set-VDPortGroup -VlanTrunkRange "$($inventory.vlans.vmotion)"
Get-VDPortGroup -VDSwitch $vsan_switch | Set-VDPortGroup -VlanTrunkRange "$($inventory.vlans.vsan)"
Get-VDPortGroup -VDSwitch $tep_switch | Set-VDPortGroup -VlanTrunkRange "$($inventory.vlans.tep)"
Get-VDPortGroup -VDSwitch $uplink_switch | Set-VDPortGroup -VlanTrunkRange "$($inventory.vlans.uplink)"

# Create portgroups. Note that we do not create a TEP portgroup; the edge TEPs will use a VLAN-backed segment instead.
$mgmt_portgroup = New-VDPortGroup -VDSwitch $mgmt_switch -Name dpg-mgmt -VlanId $inventory.vlans.management
$vmotion_portgroup = New-VDPortGroup -VDSwitch $vmotion_switch -Name dpg-vmotion -VlanId $inventory.vlans.vmotion
$vsan_portgroup = New-VDPortGroup -VDSwitch $vsan_switch -Name dpg-vsan -VlanId $inventory.vlans.vsan
$uplink_portgroup = New-VDPortGroup -VDSwitch $uplink_switch -Name dpg-uplink -VlanId $inventory.vlans.uplink

# Create vSAN and vMotion interfaces before we configure management, since we have to migrate vCenter
$inventory.bare_metals | Get-Member -Type NoteProperty | ForEach-Object {
  $esxi = $_.Name

  $vmhost = Get-VMHost -Name "$esxi.example.com"
  foreach($stack in Get-VMHostNetworkStack -VMHost $vmhost) {
    if($stack.ID -eq "vmotion") {
      New-VMHostNetworkAdapter -VMHost $vmhost -VirtualSwitch $vmotion_switch -NetworkStack $stack -PortGroup $vmotion_portgroup -IP $inventory.subnets.vmotion.reservations.$esxi.ip -SubnetMask $inventory.subnets.vmotion.netmask -Mtu 9000
    }
  }
  New-VMHostNetworkAdapter -VMHost $vmhost -VirtualSwitch $vsan_switch -PortGroup $vsan_portgroup -IP $inventory.subnets.vsan.reservations.$esxi.ip -SubnetMask $inventory.subnets.vsan.netmask -ConsoleNic:$false -ManagementTrafficEnabled:$false -VmotionEnabled:$false -VsanTrafficEnabled:$true -Mtu 9000
  Get-VMHostNetwork -VMHost $vmhost | Set-VMHostNetwork -VMKernelGatewayDevice vmk2 -VMKernelGateway $inventory.subnets.vsan.gateway

  $vmnic1 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name vmnic1
  Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vmotion_switch -VMHostPhysicalNIC $vmnic1 -Confirm:$false
  $vmnic2 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name vmnic2
  Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $vsan_switch -VMHostPhysicalNIC $vmnic2 -Confirm:$false
  $vmnic3 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name vmnic3
  Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $tep_switch -VMHostPhysicalNIC $vmnic3 -Confirm:$false
  $vmnic4 = Get-VMHostNetworkAdapter -VMHost $vmhost -Name vmnic4
  Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $uplink_switch -VMHostPhysicalNIC $vmnic4 -Confirm:$false
}
foreach($stack in Get-VMHostNetworkStack -Id vmotion) {
  Set-VMHostNetworkStack -NetworkStack $stack -VMKernelGateway $inventory.subnets.vmotion.gateway
}

# First migrate managment of host003
$host3 = Get-VMHost -Name host003.example.com
$host3_vmnic0 = Get-VMHostNetworkAdapter -VMHost $host3 -Name vmnic0
$host3_vmk1 = Get-VMHostNetworkAdapter -VMHost $host3 -Name vmk1
Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $mgmt_switch -VMHostPhysicalNIC $host3_vmnic0 -VMHostVirtualNic $host3_vmk1 -VirtualNicPortGroup $mgmt_portgroup -Confirm:$false

# Move vcenter to host003; temporarily disable vSphere HA
$vcenter = Get-VM -Name vcenter
$datastores = Get-Datastore -RelatedObject $host3 -Name "datastore1*"
$adapters = Get-NetworkAdapter -VM $vcenter
Set-Cluster -Cluster $cluster -HAEnabled:$false -Confirm:$false
Move-VM -VM $vcenter -Destination $host3 -Datastore $datastores[0] -NetworkAdapter $adapters -PortGroup $mgmt_portgroup -VMotionPriority High
Set-Cluster -Cluster $cluster -HAEnabled:$true -Confirm:$false

# Now migrate management of host001 and host002
foreach($i in @(1, 2)) {
  $esxi = Get-VMHost -Name "host00$i.example.com"
  $vmnic0 = Get-VMHostNetworkAdapter -VMHost $esxi -Name vmnic0
  $vmk1 = Get-VMHostNetworkAdapter -VMHost $esxi -Name vmk1
  Add-VDSwitchPhysicalNetworkAdapter -DistributedSwitch $mgmt_switch -VMHostPhysicalNIC $vmnic0 -VMHostVirtualNic $vmk1 -VirtualNicPortGroup $mgmt_portgroup -Confirm:$false
}

# Claim disks
foreach($esxi in Get-VMHost) {
  $disks = Get-VsanEsaEligibleDisk -VMHost $esxi
  $canonical_names = $disks | % { $_.CanonicalName }
  Add-VsanStoragePoolDisk -VMHost $esxi -VsanStoragePoolDiskType "singleTier" -DiskCanonicalName $canonical_names
}

# Migrate vCenter to vSAN datastore
$vsan_ds = Get-Datastore -RelatedObject $cluster -Name vsanDatastore
$policy = Get-SpbmStoragePolicy -Name "vSAN ESA Default Policy - RAID5"
Move-VM -VM $vcenter -Datastore $vsan_ds -StoragePolicy $policy -VMotionPriority High

# Mark vSAN Quickstart as complete
$cluster.ExtensionData.AbandonHciWorkflow()

# Apply VCF and vSAN keys
$mgr = Get-View $global:DefaultVIServer.ExtensionData.Content.LicenseManager
$assign_mgr = Get-View $mgr.LicenseAssignmentManager
$assign_mgr.UpdateAssignedLicense($vc.InstanceUuid, $inventory.license_keys.vcf, $null)
foreach($esxi in Get-VMHost) {
  $assign_mgr.UpdateAssignedLicense($esxi.ExtensionData.MoRef.Value, $inventory.license_keys.vcf, $null)
}
$assign_mgr.UpdateAssignedLicense($cluster.ExtensionData.MoRef.Value, $inventory.license_keys.vsan, $null)

# Set desired image to most recent
$images = Get-LcmImage -Type "BaseImage"
Set-Cluster -Cluster $cluster -BaseImage $images[0] -Confirm:$false

