Set-PowerCliConfiguration -InvalidCertificateAction Ignore -DefaultVIServerMode Single -Confirm:$false

# Source inventory data
. .\inventory.ps1

# Connect to NSX
$body = @{ j_username = "admin"; j_password = $nsx_password }
$response = Invoke-WebRequest -Method POST -Uri https://nsx.example.com/api/session/create -Body $body -SessionVariable session -SkipCertificateCheck
$session.Headers['X-XSRF-TOKEN'] = $response.Headers['X-XSRF-TOKEN']

# Set Avi VIP
$body = ConvertTo-Json @{ cluster_ip = $nsx[6].ip; cluster_name = "alb_controller_cluster" }
$result = Invoke-RestMethod -Method POST -Uri https://nsx.example.com/policy/api/v1/alb/controller-nodes/clusterconfig -Body $body -ContentType "application/json" -WebSession $session -SkipCertificateCheck
$clusterid = $result.id

# Get NSX and vCenter details for Avi deployment
$result = Invoke-RestMethod -Method GET -Uri https://nsx.example.com/api/v1/fabric/compute-managers -WebSession $session -SkipCertificateCheck
$vcenterid = $result.results[0].id

$vc = Connect-VIServer -Server vcenter.example.com -User administrator@vsphere.local -Password $vcenter_sso_password
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

# Deploy controllers
$body = @{ deployment_requests = @() }
for($i = 7; $i -lt 10; $i++) {
  $body.deployment_requests += @{
    form_factor = "SMALL";
    #clustering_id = $clusterid;
    deployment_config = @{
      placement_type = "AlbControllerVsphereClusterNodeVmDeploymentConfig";
      display_name = "avi$($i - 7)";
      hostname = "avi$($i - 7).example.com";
      vc_id = $vcenterid;
      default_gateway_addresses = @( "192.168.1.1" );
      management_port_subnets = @( @{ ip_addresses = @( $nsx[$i].ip ); prefix_length = 24; } );
      compute_id = $cluster.extensiondata.moref.value;
      management_network_id = $pg.extensiondata.moref.value;
      storage_id = $ds.extensiondata.moref.value;
      storage_policy_id = $policy.id;
    }
    user_settings = @{ admin_password = $avi_admin_password }
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

