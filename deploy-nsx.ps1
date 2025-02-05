# NOTE: This script not supported in PowerShell 7; it requires PowerShell 5

Set-PowerCliConfiguration -InvalidCertificateAction Ignore -DefaultVIServerMode Single -ParticipateInCeip:$false -Confirm:$false

# Load inventory data
$inventory = (Get-Content inventory.json | ConvertFrom-Json)

# Deploy NSX
$ova = Get-ChildItem Downloads\nsx-unified-appliance*.ova
D:\vcsa\ovftool\win32\ovftool --name=nsx0 --deploymentOption=medium --X:injectOvfEnv --sourceType=OVA --allowExtraConfig --datastore=vsanDatastore --network="dpg-mgmt" --acceptAllEulas --noSSLVerify --diskMode=thin --quiet --hideEula --powerOn --prop:nsx_ip_0=$($inventory.subnets.management.reservations.nsx0.ip) --prop:nsx_netmask_0=$($inventory.subnets.management.netmask) --prop:nsx_gateway_0=$($inventory.subnets.management.gateway) --prop:nsx_dns1_0="161.26.0.7 161.26.0.8" --prop:nsx_domain_0=example.com --prop:nsx_ntp_0=161.26.0.6 --prop:nsx_isSSHEnabled=True --prop:"nsx_passwd_0=$($inventory.passwords.nsx_admin)" --prop:"nsx_cli_passwd_0=$($inventory.passwords.nsx_cli_admin)" --prop:"nsx_cli_audit_passwd_0=$($inventory.passwords.nsx_cli_audit)" --prop:nsx_hostname=nsx0.example.com --prop:nsx_allowSSHRootLogin=True --prop:nsx_role="NSX Manager" --ipProtocol=IPv4 --ipAllocationPolicy="fixedPolicy" $ova[0] "vi://administrator@vsphere.local:$($inventory.passwords.vcenter_administrator)@vcenter.example.com/ibmcloud/host/london"

echo "Wait for NSX to start and reach STABLE status . . ."
$not_connected = $true
while($not_connected) {
  Start-Sleep -Seconds 30

  # Connect to NSX
  try {
    Connect-NsxtServer -Server nsx0.example.com -User admin -Password $inventory.passwords.nsx_admin -ErrorAction Stop
    $not_connected = $false
  } catch {
  }
}
$c = Get-NsxtService "com.vmware.nsx.cluster.status"
do {
  Start-Sleep -Seconds 15
  $status = $c.get()
} until($status.detailed_cluster_status.overall_status -eq "STABLE")

# Note: obtain William Lam thumbprint function from here: https://gist.github.com/lamw/8fedd19e27ff9276169e1bdd5404ca8c

# Connect NSX to vCenter
$n = Get-NsxtService -Name "com.vmware.nsx.fabric.compute_managers"
$c = $n.Help.create.compute_manager.Create()
$c.multi_nsx = $false
$c.origin_type = "vCenter"
$c.server = "vcenter.example.com"
$c.display_name = "vcenter.example.com"
$cred = $n.Help.create.compute_manager.credential.username_password_login_credential.Create()
$cred.username = "administrator@vsphere.local"
$cred.password = $inventory.passwords.vcenter_administrator
$cred.thumbprint = Get-SSLThumbprint256('https://vcenter.example.com')
$c.credential = $cred
$c.create_service_account = $true
$c.set_as_oidc_provider = $true
$cm = $n.create($c)

# Deploy additional nodes
$a = Get-NsxtService -Name "com.vmware.nsx.cluster.nodes.deployments"
$r = $a.Help.create.add_cluster_node_VM_info.Create()
$vc = Connect-VIServer -Server vcenter.example.com -User administrator@vsphere.local -Password $inventory.passwords.vcenter_administrator
$cluster = Get-Cluster -Name "london"
$vsan = Get-Datastore -Name "vsanDatastore"
$mgmt = Get-VDPortGroup -Name "dpg-mgmt"
for($i = 1; $i -le 2; $i++) {
  $node = $a.Help.create.add_cluster_node_VM_info.deployment_requests.Element.Create()
  $node.form_factor = "MEDIUM"
  $node.roles.Add("CONTROLLER")
  $node.roles.Add("MANAGER")
  $node.user_settings.audit_password = $inventory.passwords.nsx_cli_audit
  $node.user_settings.cli_password = $inventory.passwords.nsx_cli_admin
  $node.user_settings.root_password = $inventory.passwords.nsx_cli_admin
  $node.deployment_config = $a.Help.create.add_cluster_node_VM_info.deployment_requests.Element.deployment_config.vsphere_cluster_node_VM_deployment_config.Create()
  $node.deployment_config.compute_id = $cluster.ExtensionData.MoRef.Value
  $node.deployment_config.default_gateway_addresses.Add("$($inventory.subnets.management.gateway)")
  $node.deployment_config.dns_servers.Add("161.26.0.7")
  $node.deployment_config.dns_servers.Add("161.26.0.8")
  $node.deployment_config.hostname = "nsx$i.example.com"
  $node.deployment_config.management_network_id = $mgmt.ExtensionData.MoRef.Value
  $subnet = $a.Help.create.add_cluster_node_VM_info.deployment_requests.Element.deployment_config.vsphere_cluster_node_VM_deployment_config.management_port_subnets.Element.Create()
  $subnet.ip_addresses.Add($inventory.subnets.management.reservations."nsx$i".ip)
  $subnet.prefix_length = $inventory.subnets.management.prefixlen
  $node.deployment_config.management_port_subnets.Add($subnet)
  $node.deployment_config.ntp_servers.Add("161.26.0.6")
  $node.deployment_config.placement_type = "VsphereClusterNodeVMDeploymentConfig"
  $node.deployment_config.storage_id = $vsan.ExtensionData.MoRef.Value
  $node.deployment_config.vc_id = $cm.id
  $r.deployment_requests.Add($node)
}
$a.create($r)

echo "Waiting for cluster to reach STABLE status . . ."
$c = Get-NsxtService "com.vmware.nsx.cluster.status"
$cc = Get-NsxtService "com.vmware.nsx.cluster"
do {
  Start-Sleep -Seconds 15
  $status = $c.get()
  $cluster_details = $cc.get()
} until(($cluster_details.nodes.count -eq 3) -and ($status.detailed_cluster_status.overall_status -eq "STABLE"))

# Set cluster virtual IP
# Note: Usually you would specify "true" only if you wanted to skip duplicate IP checks
# However, I have found that "false" sometimes fails simply if nsx0 is no longer the elected leader at this point
$v = Get-NsxtService "com.vmware.nsx.cluster.api_virtual_ip"
$v.setvirtualip("true", "::", $inventory.subnets.management.reservations.nsx.ip)

# Anti-colocate controllers
$vms = Get-VM -Name "nsx*"
New-DrsRule -Cluster $cluster -KeepTogether:$false -Name "nsx-controller-disperse" -VM $vms

