. .\inventory.ps1

# Deploy NSX
$ova = Get-ChildItem Downloads\nsx-unified-appliance*.ova
D:\vcsa\ovftool\win32\ovftool --name=nsx0 --deploymentOption=medium --X:injectOvfEnv --sourceType=OVA --allowExtraConfig --datastore=vsanDatastore --network="dpg-mgmt" --acceptAllEulas --noSSLVerify --diskMode=thin --quiet --hideEula --powerOn --prop:nsx_ip_0=$($nsx[1].ip) --prop:nsx_netmask_0=255.255.255.0 --prop:nsx_gateway_0=192.168.1.1 --prop:nsx_dns1_0="161.26.0.7 161.26.0.8" --prop:nsx_domain_0=example.com --prop:nsx_ntp_0=161.26.0.6 --prop:nsx_isSSHEnabled=True --prop:"nsx_passwd_0=$nsx_password" --prop:"nsx_cli_passwd_0=$nsx_cli_password" --prop:"nsx_cli_audit_passwd_0=$nsx_cli_audit_password" --prop:nsx_hostname=nsx0.example.com --prop:nsx_allowSSHRootLogin=True --prop:nsx_role="NSX Manager" --ipProtocol=IPv4 --ipAllocationPolicy="fixedPolicy" $ova[0] "vi://administrator@vsphere.local:$vcenter_sso_password@vcenter.example.com/ibmcloud/host/london"

echo "Wait for NSX to start . . ."
Start-Sleep -Seconds 300

# Connect to NSX
Connect-NsxtServer -Server nsx0.example.com -User admin -Password $nsx_password

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
$cred.password = $vcenter_sso_password
$cred.thumbprint = Get-SSLThumbprint256('https://vcenter.example.com')
$c.credential = $cred
$c.create_service_account = $true
$c.set_as_oidc_provider = $true
$cm = $n.create($c)

# Deploy additional nodes
$a = Get-NsxtService -Name "com.vmware.nsx.cluster.nodes.deployments"
$r = $a.Help.create.add_cluster_node_VM_info.Create()
$cluster = Get-Cluster -Name "london"
$vsan = Get-Datastore -Name "vsanDatastore"
$mgmt = Get-VDPortGroup -Name "dpg-mgmt"
for($i = 1; $i -le 2; $i++) {
  $node = $a.Help.create.add_cluster_node_VM_info.deployment_requests.Element.Create()
  $node.form_factor = "MEDIUM"
  $node.roles.Add("CONTROLLER")
  $node.roles.Add("MANAGER")
  $node.user_settings.audit_password = $nsx_cli_audit_password
  $node.user_settings.cli_password = $nsx_cli_password
  $node.user_settings.root_password = $nsx_cli_password
  $node.deployment_config = $a.Help.create.add_cluster_node_VM_info.deployment_requests.Element.deployment_config.vsphere_cluster_node_VM_deployment_config.Create()
  $node.deployment_config.compute_id = $cluster.ExtensionData.MoRef.Value
  $node.deployment_config.default_gateway_addresses.Add("192.168.1.1")
  $node.deployment_config.dns_servers.Add("161.26.0.7")
  $node.deployment_config.dns_servers.Add("161.26.0.8")
  $node.deployment_config.hostname = "nsx$i.example.com"
  $node.deployment_config.management_network_id = $mgmt.ExtensionData.MoRef.Value
  $subnet = $a.Help.create.add_cluster_node_VM_info.deployment_requests.Element.deployment_config.vsphere_cluster_node_VM_deployment_config.management_port_subnets.Element.Create()
  $subnet.ip_addresses.Add($nsx[$i + 1].ip)
  $subnet.prefix_length = 24
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
do {
  Start-Sleep -Seconds 15
  $status = $c.get()
} until($status.detailed_cluster_status.overall_status -eq "STABLE")

# Set cluster virtual IP
$v = Get-NsxtService "com.vmware.nsx.cluster.api_virtual_ip"
$v.setvirtualip("false", "::", $nsx[0].ip)

# Anti-colocate controllers
$vms = Get-VM -Name "nsx*"
New-DrsRule -Cluster $cluster -KeepTogether:$false -Name "nsx-controller-disperse" -VM $vms

