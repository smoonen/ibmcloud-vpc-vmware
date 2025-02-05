Set-PowerCliConfiguration -InvalidCertificateAction Ignore -DefaultVIServerMode Single -ParticipateInCeip:$false -Confirm:$false

# Load inventory data
$inventory = (Get-Content inventory.json | ConvertFrom-Json)

# This enables SSH on the host's vmknic / VLAN IP
# You can alternately use the vmnic / PCI IP if you are earlier in the process
$inventory.bare_metals | Get-Member -Type NoteProperty | ForEach-Object {
  $esxi = $_.Name

  $silent = Connect-ViServer -Server $inventory.subnets.management.reservations.$esxi.ip -User root -Password $inventory.bare_metals.$esxi.password

  foreach($service in Get-VMHostService) {
    if(($service.key -eq "TSM") -or ($service.key -eq "TSM-SSH")) {
      Start-VMHostService -HostService $service
    }
  }
}

