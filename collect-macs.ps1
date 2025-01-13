Set-PowerCliConfiguration -InvalidCertificateAction Ignore -DefaultVIServerMode Single -Confirm:$false

# Source inventory data
. .\inventory.ps1

foreach($esxi in $hosts) {
  $silent = Connect-VIServer -Server $esxi.pci -User root -Password $esxi.password
  foreach($intf in @("vmnic1", "vmnic2", "vmnic3", "vmnic4")) {
    $adapt = Get-VMHostNetworkAdapter -Name $intf
    echo "$($esxi.name)_$($intf)_mac = '$($adapt.mac)'"
  }
}

