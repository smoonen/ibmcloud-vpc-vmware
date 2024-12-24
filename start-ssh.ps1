Set-PowerCliConfiguration -InvalidCertificateAction Prompt

# Source inventory data
. .\inventory.ps1

foreach($esxi in $hosts) {
  $silent = Connect-VIServer -Server $esxi.pci -User root -Password $esxi.password
  foreach($service in Get-VMHostService) {
    if(($service.key -eq "TSM") -or ($service.key -eq "TSM-SSH")) {
      Start-VMHostService -HostService $service
    }
  }
}

