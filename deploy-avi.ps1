# NOTE: This script requires PowerShell 7

Set-PowerCliConfiguration -InvalidCertificateAction Ignore -DefaultVIServerMode Single -ParticipateInCeip:$false -Confirm:$false

# Load inventory data
$inventory = (Get-Content inventory.json | ConvertFrom-Json)

# Connect to NSX
$body = @{ j_username = "admin"; j_password = $inventory.passwords.nsx_admin }
$response = Invoke-WebRequest -Method POST -Uri https://nsx.example.com/api/session/create -Body $body -SessionVariable session -SkipCertificateCheck
$session.Headers['X-XSRF-TOKEN'] = $response.Headers['X-XSRF-TOKEN']

# Set Avi VIP
$body = ConvertTo-Json @{ cluster_ip = $inventory.subnets.management.reservations.avi.ip; cluster_name = "alb_controller_cluster" }
$result = Invoke-RestMethod -Method POST -Uri https://nsx.example.com/policy/api/v1/alb/controller-nodes/clusterconfig -Body $body -ContentType "application/json" -WebSession $session -SkipCertificateCheck
$clusterid = $result.id

# Get NSX and vCenter details for Avi deployment
$result = Invoke-RestMethod -Method GET -Uri https://nsx.example.com/api/v1/fabric/compute-managers -WebSession $session -SkipCertificateCheck
$vcenterid = $result.results[0].id

$vc = Connect-VIServer -Server vcenter.example.com -User administrator@vsphere.local -Password $inventory.passwords.vcenter_administrator
$ds = Get-Datastore -Name vsanDatastore
$cluster = Get-Cluster -Name "london"
$pg = Get-VDPortgroup "dpg-mgmt"
$policy = Get-SpbmStoragePolicy -Name "vSAN ESA Default Policy - RAID5"

# Upload Avi OVA
# NOTE: You should use an OVA from the 22.x stream; 30.x is not currently supported.
# See: https://techdocs.broadcom.com/us/en/vmware-cis/nsx/vmware-nsx/4-2/installation-guide/install-nsx-advanced-load-balancer.html
$form = @{
  file      = Get-Item -Path Downloads\controller*.ova
  file_type = "OVA"
  product   = "ALB_CONTROLLER"
}
$result = Invoke-RestMethod -Method POST -Uri https://nsx.example.com/api/v1/repository/bundles?action=upload -Form $form -WebSession $session -SkipCertificateCheck

echo "Wait for upload to complete processing"
$in_progress = $true
while($in_progress) {
  Start-Sleep -Seconds 30
  $result = Invoke-RestMethod -Method GET -Uri "https://nsx.example.com/api/v1/repository/bundles?product=ALB_CONTROLLER&file_type=OVA" -WebSession $session -SkipCertificateCheck
  if(-not ($result.in_progress)) {
    $in_progress = $false
  }
}

# Deploy controllers
$body = @{ deployment_requests = @() }
for($i = 0; $i -lt 3; $i++) {
  $body.deployment_requests += @{
    form_factor = "MEDIUM";
    deployment_config = @{
      placement_type = "AlbControllerVsphereClusterNodeVmDeploymentConfig";
      display_name = "avi$i";
      hostname = "avi$i.example.com";
      vc_id = $vcenterid;
      default_gateway_addresses = @( $inventory.subnets.management.gateway );
      dns_servers = @( "161.26.0.7"; "161.26.0.8");
      ntp_servers = @( "161.26.0.6" );
      management_port_subnets = @( @{ ip_addresses = @( $inventory.subnets.management.reservations."avi$i".ip ); prefix_length = $inventory.subnets.management.prefixlen; } );
      compute_id = $cluster.extensiondata.moref.value;
      management_network_id = $pg.extensiondata.moref.value;
      storage_id = $ds.extensiondata.moref.value;
      storage_policy_id = $policy.id;
    }
    user_settings = @{ admin_password = $inventory.passwords.avi_admin }
  }
}

$json = ConvertTo-Json $body -Depth 10
$result = Invoke-RestMethod -Method POST -Uri https://nsx.example.com/policy/api/v1/alb/controller-nodes/deployments -Body $json -ContentType "application/json" -WebSession $session -SkipCertificateCheck

echo "Wait for Avi deployment to complete . . ."
$in_progress = $true
while($in_progress) {
  Start-Sleep -Seconds 30
  $result = Invoke-RestMethod -Method GET -uri https://nsx.example.com/policy/api/v1/alb/controller-nodes/cluster -WebSession $session -SkipCertificateCheck
  if($result.error.error_code -ne 94510) {
    $in_progress = $false
  }
}

# After deployment, a set of (currently) manual operations needed:
# 1. Upgrade to Avi 31.x
# 2. Install Avi license or initiate cloud services connection
# 3. Connect Avi to NSX or vCenter
# . . .
#
# Note: William Lam has some post deploy scripting to consider here: https://github.com/lamw/vsphere-with-tanzu-nsx-advanced-lb-automated-lab-deployment/blob/master/vsphere-with-tanzu-nsx-advanced-lb-lab-deployment.ps1

