<#
.DESCRIPTION
  This is a report to check the health of hypervisors (vmware and rhv).
.PARAMETER <Parameter_Name>
  None yet
.INPUTS
  Requires Windows Vault entry for "hypervisor-query"
.OUTPUTS
  Log file stored in "C:\temp\hypervisor_daily_checks$(Get-Date –f yyyy-MM-dd-HHmm).log"
  Email will be sent to list of addresses in $msgto array.
.NOTES
  Version:        1.0
  Author:         Joshua Perry
  Creation Date:  16/11/2022
  Purpose/Change: This is an evolution of a previous script (vmware_daily_checks.ps1) to include multiple hypervisors.
  
.EXAMPLE
  <Example goes here. Repeat this attribute for more than one example>
#>

#----------------------------------------------------------[Logging Start]---------------------------------------------------------

# Begin Log

    Start-Transcript -Path "C:\temp\hypervisor_daily_checks$(Get-Date –f yyyy-MM-dd-HHmm).log"

#---------------------------------------------------------[Initialisations]--------------------------------------------------------

# Set Error Action to Silently Continue
    $ErrorActionPreference = "SilentlyContinue"

# Import PowerCLI Powershell Modules

    Get-Module -Name VMware* -ListAvailable | Import-Module
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
    Set-PowerCLIConfiguration -ParticipateInCeip $false -Confirm:$false
    Set-PowerCLIConfiguration -DefaultVIServerMode multiple -Confirm:$false

# Enforce TLS Version

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# SSL Error Handling & Bypass

    if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type)
    {
    $certCallback = @"
        using System;
        using System.Net;
        using System.Net.Security;
        using System.Security.Cryptography.X509Certificates;
        public class ServerCertificateValidationCallback
        {
            public static void Ignore()
            {
                if(ServicePointManager.ServerCertificateValidationCallback ==null)
                {
                    ServicePointManager.ServerCertificateValidationCallback += 
                        delegate
                        (
                            Object obj, 
                            X509Certificate certificate, 
                            X509Chain chain, 
                            SslPolicyErrors errors
                        )
                        {
                            return true;
                        };
                }
            }
        }
"@ # I can't tab this line in, it is driving me crazy!!!  It is a limitation of 'here-strings'.
        Add-Type $certCallback
    }
    [ServerCertificateValidationCallback]::Ignore()

# Initialise Arrays

    $datacenters = @()
    $clusters = @()
    $hosts = @()
    $vms = @()
    $results = @()
    $hvconns = @()

# Create HTML Header

    $Header = @("
    <style>
    TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
    TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #21c465;}
    TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
    </style>
    ")

#----------------------------------------------------------[Declarations]----------------------------------------------------------

    # General
    
        $currentdate = Get-Date –f yyyyMMddHHmm
    
    # Hypervisors
    
        $vcenters = @(
            "dc3-vcsa01.nowitsolutions.com.au",
            "dc4-vcsa01.nowitsolutions.com.au"
            )

        $rhvmgrs = @(
            "qld-ndb2-vm-02.mgmt.spirit.net.au",
            "dc4-rhvm01.nowitsolutions.com.au"
            )
    
    # SMTP Settings
    
        $smtpServer = “smtp1.nowitsolutions.com.au”
        $smtp = New-Object Net.Mail.SmtpClient($SmtpServer, 25)
        $msgfrom = "vmware@nowitsolutions.com.au"
        $msgto = "jperry@nowitsolutions.com.au"
        #$msgto = @(
        #    "vcsareports@nowitsolutions.com.au",
        #    "paul.paki@spirit.com.au",
        #    "joshua.perry@spirit.com.au",
        #    "john.mizuno@spirit.com.au",
        #    "dinesh.herath@spirit.com.au",
        #    "darren.brown@spirit.com.au"
        #    )
    
#-----------------------------------------------------------[Functions]------------------------------------------------------------

# N/A

#-----------------------------------------------------------[Execution]------------------------------------------------------------

# Get Account for Hypervisor Authentication

    [Windows.Security.Credentials.PasswordVault,Windows.Security.Credentials,ContentType=WindowsRuntime]
    $vaultresource="hypervisor-query" # Be sure to store hypervisor readonly credentials in password vault with this resource name
    $vault = New-Object Windows.Security.Credentials.PasswordVault
    $username = ( $vault.RetrieveAll() | Where-Object { $_.Resource -eq $vaultresource } | Select-Object -First 1 ).UserName
    $password = ( $vault.Retrieve( $vaultresource, $username ) | Select-Object -First 1 ).Password
    $securepass = ConvertTo-SecureString -String $password -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($username, $securepass)
    Remove-Variable password # So that we don't have the unsecure password lingering in memory

# Connect to Hypervisor

    # VCSAs

        foreach ($vcenter in $vcenters) {
            $vcsaconn = Connect-VIServer $vcenter -Credential $credential
            $hvconns += New-Object -TypeName PSObject -Property @{
                name = $vcsaconn.Name;
                user = $vcsaconn.User;
                hypervisor = "vCenter"
                version = {$Global:DefaultVIServers | where {$_.Name -eq $vcenter} | select Version}
            }
        }

    # RHV Ovirt-Engine (not required, but closest equivilent and a good test, if this step fails, others are likely to as well)

            foreach ($rhvmgr in $rhvmgrs) {
            $rhvmgrconn = invoke-restmethod -uri "https://$rhvmgr/ovirt-engine/api" -credential $credential
            $hvconns += New-Object -TypeName PSObject -Property @{
                name = $rhvmgr;
                user = $rhvmgrconn.api.authenticated_user;
                hypervisor = $rhvmgrconn.api.product_info.name
                version = $rhvmgrconn.api.product_info.version;
            }
        }

# Get Hosts with Unhealthy Storage

    # VCSA

        $vmhosts = get-vmhost
        foreach ($vmhost in $vmhosts) {
            $luns = get-vmhost $vmhost | Get-ScsiLun -LunType disk | where {$_.ExtensionData.OperationalState -ne "ok"}
            foreach ($lun in $luns) {
                $unhstorage =  += New-Object -TypeName PSObject -Property @{
                    datacenter = {(Get-Datacenter -VMHost $vmhost).name};
                    cluster = {if($vmhost.ExtensionData.Parent.Type -ne "ClusterComputeResource"){"Stand alone host"} 
                        else{ 
                            Get-view -Id $vmhost.ExtensionData.Parent | Select -ExpandProperty Name 
                        }};
                    host = $vmhost.name;
                    vendor = $lun.vendor;
                    state = $lun.extensiondata.operationalstate;
                    name = $lun.canonicalname;
                    capacitygb = $lun.capacitygb;
                }
            }
        }

    # RHV Ovirt-Engine



#-------------------------------------------------------[Build HTML Tables]--------------------------------------------------------

# Build Hypervisor Connection Table

    # Setup HTML Table & Headings

        $hvconn_html = "<table>`n"
        $hvconn_html += "    <th style='font-weight:bold'>Name</th>"
        $hvconn_html += "    <th style='font-weight:bold'>User</th>"
        $hvconn_html += "    <th style='font-weight:bold'>Hypervisor</th>"
        $hvconn_html += "    <th style='font-weight:bold'>Version</th>"
    
    # Populate Table

        foreach ($hvconn in $hvconns) {
            $hvconn_html += "  <tr>`n"
            $hvconn_html += "    <td>$($hvconn.Name)</td>`n"
            $hvconn_html += "    <td>$($hvconn.User)</td>`n"
            $hvconn_html += "    <td>$($hvconn.Hypervisor)</td>`n"
            $hvconn_html += "    <td>$($hvconn.Version)</td>`n"
            $hvconn_html += "  </tr>`n"
        }
    
    # Close HTML Table

        $hvconn_html += "</table>`n"


#---------------------------------------------------------[Logging  Stop]----------------------------------------------------------

# Stop Log

    Stop-Transcript