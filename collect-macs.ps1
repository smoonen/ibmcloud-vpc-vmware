Set-PowerCliConfiguration -InvalidCertificateAction Ignore -DefaultVIServerMode Single -ParticipateInCeip:$false -Confirm:$false

# Load inventory data
$inventory = (Get-Content inventory.json | ConvertFrom-Json)

# Connect to each host in turn and collect its MAC addresses
$inventory.bare_metals | Get-Member -Type NoteProperty | ForEach-Object {
  $esxi = $_.Name

  $silent = Connect-VIServer -Server  $inventory.subnets.pci.reservations."$esxi-management".ip -User root -Password $inventory.bare_metals.$esxi.password
  foreach($intf in @("vmnic1", "vmnic2", "vmnic3", "vmnic4")) {
    $adapt = Get-VMHostNetworkAdapter -Name $intf
    $inventory.bare_metals.$esxi | Add-Member -MemberType NoteProperty -Name "$($intf)_mac" -Value $adapt.mac
  }
}

# Write updated inventory back to disk
$inventory | ConvertTo-Json -Depth 100 | Out-File inventory.json

echo "If you are running correct-pcis.py on a different system, transfer your inventory.json file back to that system now."

