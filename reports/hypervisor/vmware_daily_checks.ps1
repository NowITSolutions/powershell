############################################
## This script is designed to do a quick  ##
## health check on our VMware environment ##
##                                        ##
## Currently run on NIT-UTIL02            ##
##                                        ##
## Created by Joshua Perry                ##
## Last updated 20/03/2020                ##
############################################
############################################
## Import VMware Modules
############################################

    Get-Module -Name VMware* -ListAvailable | Import-Module
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
    Set-PowerCLIConfiguration -ParticipateInCeip $false -Confirm:$false
    Set-PowerCLIConfiguration -DefaultVIServerMode multiple -Confirm:$false
    
############################################
## Start Logging
############################################

    Start-Transcript -Path "C:\temp\snaplog.txt"

############################################
## Settings
############################################

    #-ExecutionPolicy Bypass C:\Scripts\Test.ps1
    $currentdate = Get-Date –f yyyyMMddHHmm
    $smtpServer = “smtp1.nowitsolutions.com.au”
    $smtp = New-Object Net.Mail.SmtpClient($SmtpServer, 25)
    $msgfrom = "vmware@nowitsolutions.com.au"
    $msgto = @(
        "vcsareports@nowitsolutions.com.au",
        "paul.paki@spirit.com.au",
        "joshua.perry@spirit.com.au",
        "john.mizuno@spirit.com.au",
        "dinesh.herath@spirit.com.au",
        "darren.brown@spirit.com.au"
        )

############################################
## Format Output
############################################

    $Header = @("
    <style>
    TABLE {border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
    TH {border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #21c465;}
    TD {border-width: 1px; padding: 3px; border-style: solid; border-color: black;}
    </style>
    ")

###########################################
## Get Vcenters
###########################################

    $vcenters = @(
    "dc3-vcsa01.nowitsolutions.com.au",
    "dc4-vcsa01.nowitsolutions.com.au"
    )

###########################################
## Authentication
###########################################

    $password = Get-Content "C:\Scripts\INFRA\Creds\sanmon.service.txt" | ConvertTo-SecureString -Key (Get-Content "C:\Scripts\INFRA\Creds\sanmon.service.key")
    $credential = New-Object System.Management.Automation.PsCredential("nowitsolutions\sanmon.service",$password)
    $vcuser = $credential.UserName
    $vcpasswd = ($credential.GetNetworkCredential()).Password

###########################################
## Connect to Vcenter
###########################################

    # Setup HTML Table

        $viconn = "<table>`n"
        $viconn += "    <th style='font-weight:bold'>Name</th>"
        $viconn += "    <th style='font-weight:bold'>Port</th>"
        $viconn += "    <th style='font-weight:bold'>User</th>"
    
    # Command

        foreach ($vcenter in $vcenters) {
            $vcsaconn = Connect-VIServer $vcenter -User $vcuser -Password $vcpasswd
            $viconn += "  <tr>`n"
            $viconn += "    <td>$($vcsaconn.Name)</td>`n"
            $viconn += "    <td>$($vcsaconn.Port)</td>`n"
            $viconn += "    <td>$($vcsaconn.User)</td>`n"
            $viconn += "  </tr>`n"
        }
    
    # HTML Table Close

        $viconn += "</table>`n"
    
######################################################
## Hosts with disconected USB
######################################################

    # Setup HTML Table

        $disusb = "<table>`n"
        $disusb += "    <th style='font-weight:bold'>Datacenter</th>"
        $disusb += "    <th style='font-weight:bold'>Cluster</th>"
        $disusb += "    <th style='font-weight:bold'>VMHost</th>"
        $disusb += "    <th style='font-weight:bold'>Vendor</th>"
        $disusb += "    <th style='font-weight:bold'>Operational State</th>"
        $disusb += "    <th style='font-weight:bold'>Runtime Name</th>"
        $disusb += "    <th style='font-weight:bold'>Capacity GB</th>"

    # Command
    
        $vmhosts = get-vmhost
        $results = $null

        foreach ($vmhost in $vmhosts) {
            $luns = get-vmhost $vmhost | Get-ScsiLun -LunType disk
            $results += $luns | Select @{N="Datacenter"; e={(Get-Datacenter -VMHost $_.VMHost).name}},
                @{N="Cluster";E={ 
                    if($_.VMHost.ExtensionData.Parent.Type -ne "ClusterComputeResource"){"Stand alone host"} 
                    else{ 
                        Get-view -Id $_.VMHost.ExtensionData.Parent | Select -ExpandProperty Name 
                    } 
                    }},
                VMHost,
                Vendor,
                @{N="OperationalState";E={$_.ExtensionData.OperationalState}},
                RuntimeName,
                CapacityGB
        }
        
        $results | where-object {$_.OperationalState -ne "ok"} | foreach-object {
                write-host "$($_.VMHost) has an inaccessible USB device"
                $disusb += "  <tr>`n"
                $disusb += "    <td>$($_.Datacenter)</td>`n"
                $disusb += "    <td>$($_.Cluster)</td>`n"
                $disusb += "    <td>$($_.VMHost)</td>`n"
                $disusb += "    <td>$($_.Vendor)</td>`n"
                $disusb += "    <td>$($_.OperationalState)</td>`n"
                $disusb += "    <td>$($_.RuntimeName)</td>`n"
                $disusb += "    <td>$($_.CapacityGB)</td>`n"
                $disusb += "  </tr>`n"
        }

        if ($disusb -notmatch '<tr>') {
            $disusb += "  <tr>`n"
            $disusb += "    <td colspan='7'>No Hosts with inaccessible USBs found</td> `n"
            $disusb += "  </tr>`n"
        }
        
    # HTML Table Close

        $disusb += "</table>`n"

    # Reset Variables

        $luns = $null
        $vmhost = $null
        $vmhosts = $null
        $results = $null

######################################################
## VMs with Incompatible Virtual Hardware (HD Audio)
######################################################

    # Setup HTML Table

        $incompathw = "<table>`n"
        $incompathw += "    <th style='font-weight:bold'>Name</th>"
        $incompathw += "    <th style='font-weight:bold'>Power State</th>"
        $incompathw += "    <th style='font-weight:bold'>Datacenter</th>"
        $incompathw += "    <th style='font-weight:bold'>Device</th>"
    
    # Command

        $vms = get-vm
        $results = @()
        $hdaudio = $null
        
        foreach ($vm in $vms) {
            $vmdevices = $vm.ExtensionData.Config.Hardware.Device | %{$_.GetType().Name}
            $hdaudio = $null
        
            if ($vmdevices -match 'VirtualHdAudioCard') {
                write-host "$($vm) has an incompatible virtual hardware device (HD Audio)"
                $results += $vm
                $incompathw += "  <tr>`n"
                $incompathw += "    <td>$($vm.Name)</td>`n"
                $incompathw += "    <td>$($vm.PowerState)</td>`n"
                $incompathw += "    <td>VirtualHdAudioCard</td>`n"
                $incompathw += "    <td>$($vm.Uid.Substring($vm.Uid.IndexOf('@')+1).Split(":")[0])</td>`n"
                $incompathw += "  </tr>`n"
            }
        }

        if ($incompathw -notmatch '<tr>') {
            $incompathw += "  <tr>`n"
            $incompathw += "    <td colspan='4'>No VMs with incompatible Virtual Hardware found</td> `n"
            $incompathw += "  </tr>`n"
        }

    # HTML Table Close

        $incompathw += "</table>`n"

    # Reset Variables

        $vms = $null
        $results = $null
        $hdaudio = $null

###########################################
## List datastores with less than 100GB free
###########################################

    # Setup HTML Table

        $ds100result = "<table>`n"
        $ds100result += "    <th style='font-weight:bold'>Name</th>"
        $ds100result += "    <th style='font-weight:bold'>Free Space (GB)</th>"
        $ds100result += "    <th style='font-weight:bold'>Capacity (GB)</th>"
    
    # Command

        $datastores = Get-Datastore | where {$_.CapacityGB -le 3072 -and $_.FreeSpaceGB -lt 100 -and $_.Name -notlike "*exch*" -and $_.Name -notlike "*logs*" -and $_.Name -notlike "*log*" -and $_.Name -notlike "*pf01*"}
        foreach ($datastore in $datastores) {
            $dslt100 = $datastore | Select Name,@{N='FreeSpaceGB';E={[math]::Round($_.FreeSpaceGB,2)}},@{N='CapacityGB';E={[math]::Round($_.CapacityGB,2)}} | sort -Property FreeSpaceGB
            $ds100result += "  <tr>`n"
            $ds100result += "    <td>$($dslt100.Name)</td>`n"
            $ds100result += "    <td>$($dslt100.FreeSpaceGB)</td>`n"
            $ds100result += "    <td>$($dslt100.CapacityGB)</td>`n"
            $ds100result += "  </tr>`n"
        }

        if ($ds100result -notmatch '<tr>') {
            $ds100result += "  <tr>`n"
            $ds100result += "    <td colspan='3'>No Datastores with less than 100GB free</td> `n"
            $ds100result += "  </tr>`n"
        }

    # HTML Table Close

        $ds100result += "</table>`n"


###########################################
## List datastores with less than 300GB free
###########################################

    # Setup HTML Table

        $ds300result = "<table>`n"
        $ds300result += "    <th style='font-weight:bold'>Name</th>"
        $ds300result += "    <th style='font-weight:bold'>Free Space (GB)</th>"
        $ds300result += "    <th style='font-weight:bold'>Capacity (GB)</th>"
    
    # Command

        $datastores = Get-Datastore | where {$_.CapacityGB -ge 3072 -and $_.FreeSpaceGB -lt 300 -and $_.Name -notlike "*exch*" -and $_.Name -notlike "*logs*" -and $_.Name -notlike "*pf01*"}
        foreach ($datastore in $datastores) {
            $dslt300 = $datastore | Select Name,@{N='FreeSpaceGB';E={[math]::Round($_.FreeSpaceGB,2)}},@{N='CapacityGB';E={[math]::Round($_.CapacityGB,2)}} | sort -Property FreeSpaceGB
            $ds300result += "  <tr>`n"
            $ds300result += "    <td>$($dslt300.Name)</td>`n"
            $ds300result += "    <td>$($dslt300.FreeSpaceGB)</td>`n"
            $ds300result += "    <td>$($dslt300.CapacityGB)</td>`n"
            $ds300result += "  </tr>`n"
        }

        if ($ds300result -notmatch '<tr>') {
            $ds300result += "  <tr>`n"
            $ds300result += "    <td colspan='3'>No Datastores with less than 300GB free</td> `n"
            $ds300result += "  </tr>`n"
        }

    # HTML Table Close

        $ds300result += "</table>`n"


###########################################
## List VMs with mounted CDs
###########################################

    # Setup HTML Table

        $cdresult = "<table>`n"
        $cdresult += "    <th style='font-weight:bold'>Name</th>"
        $cdresult += "    <th style='font-weight:bold'>Cluster</th>"
        $cdresult += "    <th style='font-weight:bold'>ISO</th>"
    
    # Command

        $cdfilter = {$_.IsoPath -ne $null}
        $mountedcds = Get-VM | Get-CDDrive | where $cdfilter
        foreach ($mountedcd in $mountedcds) {
            $vmcluster = get-vm $($mountedcd.parent) | select @{N="Cluster";E={Get-Cluster -VM $_}}
            if ($($mountedcd.IsoPath) -eq "[]") {
                Get-VM $($mountedcd.parent) | Get-CDDRive | Where-Object {$_.IsoPath} | Set-CDDrive -NoMedia -Confirm:$false #-WhatIf
            }
            $cdresult += "  <tr>`n"
            $cdresult += "    <td>$($mountedcd.Parent)</td>`n"
            $cdresult += "    <td>$($vmcluster.cluster.name)</td>`n"
            $cdresult += "    <td>$($mountedcd.IsoPath)</td>`n"
            $cdresult += "  </tr>`n"
        }

        if ($cdresult -notmatch '<tr>') {
            $cdresult += "  <tr>`n"
            $cdresult += "    <td colspan='3'>No VMs found with CD/ISOs mounted</td> `n"
            $cdresult += "  </tr>`n"
        }

    # HTML Table Close

        $cdresult += "</table>`n"

    # If '[]' is returned, then there is an empty 'Datastore ISO File' "mounted".
    # Have written a command to set it back to 'Client Device'.

###########################################
## List Hosts with Alarms
###########################################

    # Setup HTML Table

        $hsalarms = "<table>`n"
        $hsalarms += "    <th style='font-weight:bold'>Name</th>"
        $hsalarms += "    <th style='font-weight:bold'>OverallStatus</th>"
        $hsalarms += "    <th style='font-weight:bold'>Alarm</th>"
    
    # Command

        $hostalarms = Get-View -ViewType HostSystem | where {$_.TriggeredAlarmstate -ne "{}"}
        foreach ($alarm in $hostalarms) {
            $alarmkey = $alarm.TriggeredAlarmState.alarm.value
            $alarmkey = "Alarm-$($alarmkey)"
            $alarmdef = Get-AlarmDefinition -id $alarmkey
            $hsalarms += "  <tr>`n"
            $hsalarms += "    <td>$($alarm.Name)</td>`n"
            $hsalarms += "    <td>$($alarm.OverallStatus)</td>`n"
            $hsalarms += "    <td>$($alarmdef[0].name)</td>`n"
            $hsalarms += "  </tr>`n"
        }

        if ($hsalarms -notmatch '<tr>') {
            $hsalarms += "  <tr>`n"
            $hsalarms += "    <td colspan='3'>No Host with alarms found</td> `n"
            $hsalarms += "  </tr>`n"
        }

    # HTML Table Close

        $hsalarms += "</table>`n"

    

###########################################
## List Datastores with Alarms
###########################################

    # Setup HTML Table

        $dsalarms = "<table>`n"
        $dsalarms += "    <th style='font-weight:bold'>Name</th>"
        $dsalarms += "    <th style='font-weight:bold'>OverallStatus</th>"
        $dsalarms += "    <th style='font-weight:bold'>Alarm</th>"
        $dsalarms += "    <th style='font-weight:bold'>Capacity (GB)</th>"
        $dsalarms += "    <th style='font-weight:bold'>Free Space (GB)</th>"
    
    # Command

        $datastorealarms = Get-View -ViewType DataStore | where {$_.TriggeredAlarmstate -ne "{}"}
        foreach ($alarm in $datastorealarms) {
            $alarmkey = $alarm.TriggeredAlarmState.alarm.value
            $alarmkey = "Alarm-$($alarmkey)"
            $alarmdef = Get-AlarmDefinition -entity Datastore -id $alarmkey
            $alarmds = Get-Datastore -id $($alarm.MoRef)
            $alarmcap = ($($alarmds.CapacityGB),2)
            $alarmfree = ([math]::Round($($alarmds.FreeSpaceGB),2))
            $dsalarms += "  <tr>`n"
            $dsalarms += "    <td>$($alarm.Name)</td>`n"
            $dsalarms += "    <td>$($alarm.OverallStatus)</td>`n"
            $dsalarms += "    <td>$($alarmdef[0].name)</td>`n"
            $dsalarms += "    <td>$($alarmcap)</td>`n"
            $dsalarms += "    <td>$($alarmfree)</td>`n"
            $dsalarms += "  </tr>`n"
        }

        if ($dsalarms -notmatch '<tr>') {
            $dsalarms += "  <tr>`n"
            $dsalarms += "    <td colspan='5'>No Datastores with alarms found</td> `n"
            $dsalarms += "  </tr>`n"
        }

    # HTML Table Close

        $dsalarms += "</table>`n"

###########################################
## List VMs with Snapshots
###########################################

    # Setup HTML Table

        $snapresult = "<table>`n"
        $snapresult += "    <th style='font-weight:bold'>VM Name</th>"
        $snapresult += "    <th style='font-weight:bold'>Cluster</th>"
        $snapresult += "    <th style='font-weight:bold'>Snapshot Name</th>"
        $snapresult += "    <th style='font-weight:bold'>Date Created</th>"
        $snapresult += "    <th style='font-weight:bold'>Size (GB)</th>"
        $snapresult += "    <th style='font-weight:bold'>Description</th>"
            
    # Command

        $snapshots = get-vm | get-snapshot | select vm,name,created,@{N='sizegb';E={[math]::Round($_.sizegb,2)}},description
        foreach ($snapshot in $snapshots) {
            $vmcluster = get-vm $($snapshot.vm) | select @{N="Cluster";E={Get-Cluster -VM $_}}
            $snapresult += "  <tr>`n"
            $snapresult += "    <td>$($snapshot.vm)</td>`n"
            $snapresult += "    <td>$($vmcluster.cluster.name)</td>`n"
            $snapresult += "    <td>$($snapshot.name)</td>`n"
            $snapresult += "    <td>$($snapshot.created)</td>`n"
            $snapresult += "    <td>$($snapshot.sizegb)</td>`n"
            $snapresult += "    <td>$($snapshot.description)</td>`n"
            $snapresult += "  </tr>`n"
        }

        if ($snapresult -notmatch '<tr>') {
            $snapresult += "  <tr>`n"
            $snapresult += "    <td colspan='5'>No Snapshots found</td> `n"
            $snapresult += "  </tr>`n"
        }

    # HTML Table Close

        $snapresult += "</table>`n"

###########################################
## Disconnect from Vcenter
###########################################
    
    foreach ($vcenter in $vcenters)
    {
         Disconnect-VIServer -Server $vcenter -confirm:$False
    }

###########################################
## Generate email and send email to client
###########################################

    $msg = new-object Net.Mail.MailMessage
       
    #From Address
    $msg.From = $msgfrom

    #To Address, to add additional recipients, update the array $msgto at the top of this script.
    foreach ($recipient in $msgto) {
        $msg.To.Add($recipient)
        }
    
    #Message Body
    $msg.IsBodyHtml = $true
    $msg.Body=$header
    $msg.Body+=”<strong>vCenter Connections:</strong>`n <br />”
    $msg.Body+=”`n <br />”
    $msg.Body+=$viconn
    $msg.Body+=”`n <br />”
    $msg.Body+=”<strong>Hosts with inaccessible USB device:</strong>`n <br />”
    $msg.Body+=”`n <br />”
    $msg.Body+=$disusb
    $msg.Body+=”`n <br />”
    $msg.Body+=”<strong>VMs with Incompatible Virtual Hardware (HD Audio)</strong>`n <br />”
    $msg.Body+=”`n <br />”
    $msg.Body+=$incompathw
    $msg.Body+=”`n <br />”
    $msg.Body+=”<strong>Datastores (under 3TB) with less than 100GB free:</strong>`n <br />”
    $msg.Body+=”`n <br />”
    $msg.Body+=$ds100result
    $msg.Body+=”`n <br />”
    $msg.Body+=”<strong>Datastores (over 3TB) with less than 300GB free:</strong>`n <br />”
    $msg.Body+=”`n <br />”
    $msg.Body+=$ds300result
    $msg.Body+=”`n <br />”
    $msg.Body+=”<strong>VMs with mounted CDs:</strong>`n <br />”
    $msg.Body+=”`n <br />”
    $msg.Body+=$cdresult
    $msg.Body+=”`n <br />”
    $msg.Body+=”<strong>Host Alarms:</strong>`n <br />”
    $msg.Body+=”`n <br />”
    $msg.Body+=$hsalarms
    $msg.Body+=”`n <br />”
    $msg.Body+=”<strong>Datastore Alarms:</strong>`n <br />”
    $msg.Body+=”`n <br />”
    $msg.Body+=$dsalarms
    $msg.Body+=”`n <br />”
    $msg.Body+=”<strong>Current Snapshots:</strong>`n <br />”
    $msg.Body+=”`n <br />”
    $msg.Body+=$snapresult
    
    #Message Subject
    $msg.Subject = “VMware Report”
    
    $smtp.Send($msg)
    echo $msg | fl
    $msg.Dispose();

############################################
## Stop Logging
############################################

Stop-Transcript