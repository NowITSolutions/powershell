############################################
## This script is designed to monitor     ##
## VMware tasks, and email once complete  ##
##                                        ##
## Created by Joshua Perry                ##
## Last updated 14/11/2021                ##
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

$currentdate = Get-Date –f yyyyMMddHHmm
Start-Transcript -Path "C:\temp\vmwarenotification$($currentdate).txt"

############################################
## Settings
############################################

clear
$smtpServer = Read-Host -Prompt "SMTP Server"
$mon_email = Read-Host -Prompt "Email Noitifcation Recipient Address"
$msgfrom = Read-Host -Prompt "Email address to send from"
$vcenters = @()
$vcenters = Read-Host -Prompt "vCenter to connect to"

Write-Host "$($mon_email) will be notified when the following task completes or fails" -ForegroundColor Yellow
Write-Host "DO NOT CANCEL OR CLOSE OUT OF THIS WINDOW, OR THE NOTIFICATION WILL NOT BE SENT" -ForegroundColor Red

###########################################
## Get Vcenters
###########################################


############################################
## Format Output
############################################

$Header = @("
<style>
TABLE {border-width: 0px; border-style: solid; border-color: black; border-collapse: collapse;}
TH {border-width: 0px; padding: 3px; border-style: solid; border-color: black; background-color: #21c465;}
TD {border-width: 0px; padding: 3px; border-style: solid; border-color: black;}
</style>
")

###########################################
## Connect to Vcenter
###########################################

    foreach ($vcenter in $vcenters) {
        Connect-VIServer $vcenter
    }

###########################################
## Monitor Task & Strucuture Email
###########################################

# Setup HTML Table

    $taskresult = "<table>`n"
    $taskresult += "    <th></th>"
    $taskresult += "    <th></th>"

#        $taskresult += "    <th style='font-weight:bold'>EntityName</th>"
#        $taskresult += "    <th style='font-weight:bold'>VirtualMachine</th>"
#        $taskresult += "    <th style='font-weight:bold'>Datastore</th>"
#        $taskresult += "    <th style='font-weight:bold'>Initiatior</th>"
#        $taskresult += "    <th style='font-weight:bold'>Description</th>"
#        $taskresult += "    <th style='font-weight:bold'>id</th>"
#        $taskresult += "    <th style='font-weight:bold'>State</th>"
#        $taskresult += "    <th style='font-weight:bold'>StartTime</th>"
#        $taskresult += "    <th style='font-weight:bold'>Progress(%)</th>"
#        $taskresult += "    <th style='font-weight:bold'>LastChecked</th>"
#        $taskresult += "    <th style='font-weight:bold'>Datacenter</th>"
#        $taskresult += "    <th style='font-weight:bold'>ComputeResource</th>"
#        $taskresult += "    <th style='font-weight:bold'>Host</th>"

        
# Get list of running tasks

    $tasks = get-task | where {$_.State -eq "Running"}
    $results = @()
    $resultcount = -1
    
    foreach ($task in $tasks) {
        $resultcount++
        $vievent = get-vievent -start (get-task -id $task.id).StartTime -Finish ((get-task -id $task.id).StartTime).AddSeconds(30) | 
                    where {$_.FullFormattedMessage -notlike "*logged out*" -and $_.FullFormattedMessage -notlike "*logged in*" -and $_.FullFormattedMessage -notlike "*cannot login*"} | 
                    where {$_.DestHost -ne $null}
    
        $results += $task | select @{N="Task No#";E={$resultcount}},
                    @{N="EntityName";E={(get-task -id $_.Id).Extensiondata.Info.EntityName}},
                    @{N="VirtualMachine";E={$vievent.vm.name}},
                    @{N="Datastore";E={$vievent.ds.name}},
                    @{N="Initiatior";E={(get-task -id $_.Id).Extensiondata.Info.Reason.UserName}},
                    Description,
                    id,
                    State,
                    StartTime,
                    @{N="Progress(%)";E={$task.PercentComplete}},
                    @{N="LastChecked";E={get-date -format g}},
                    @{N="Datacenter";E={$vievent.datacenter.name}},
                    @{N="ComputeResource";E={$vievent.computeresource.name}},
                    @{N="Host";E={$vievent.host.name}}
    }
    
 # Prompt User for Task to monitor, and email address to send notification to

    clear
    $results | format-table * | Out-String|% {Write-Host $_}
    write-host "Press Ctrl-C to exit" -ForegroundColor Yellow
    $mon_task = Read-Host -Prompt "Task No# to monitor"
       
    Write-Host "$($mon_email) will be notified when the following task completes or fails" -ForegroundColor Yellow
    Write-Host "DO NOT CANCEL OR CLOSE OUT OF THIS WINDOW, OR THE NOTIFICATION WILL NOT BE SENT" -ForegroundColor Red

# Monitor task until it finishes
    
    Do {
        $percent = (get-task -id $results[$mon_task].id).PercentComplete
        Write-Host "Task to migrate " -NoNewline; Write-Host "$($results[$mon_task].VirtualMachine)" -ForegroundColor Yellow -NoNewline; Write-Host "\" -NoNewline; Write-Host "$($results[$mon_task].EntityName) " -ForegroundColor Yellow -NoNewline; Write-Host "is " -NoNewline; Write-Host "$($percent)% Complete " -ForegroundColor Green -NoNewline; Write-Host "DO NOT CANCEL OR CLOSE OUT OF THIS WINDOW, OR THE NOTIFICATION WILL NOT BE SENT" -ForegroundColor Red
        Start-Sleep 5
        }
    While ($percent -lt 100)

    $finishtime = (get-task -id $($results[$mon_task].id)).FinishTime
    $taskstatus = (get-task -id $($results[$mon_task].id)).state
    



# Create email content  
    
    $results[$mon_task]

    $taskresult += "  <tr>`n"
    $taskresult += "    <td>EntityName</td>`n"
    $taskresult += "    <td>$($results[$mon_task].EntityName)</td>`n"
    $taskresult += "  </tr>`n"
    $taskresult += "  <tr>`n"
    $taskresult += "    <td>VirtualMachine</td>`n"
    $taskresult += "    <td>$($results[$mon_task].VirtualMachine)</td>`n"
    $taskresult += "  </tr>`n"
    $taskresult += "  <tr>`n"
    $taskresult += "    <td>Datastore</td>`n"
    $taskresult += "    <td>$($results[$mon_task].Datastore)</td>`n"
    $taskresult += "  </tr>`n"
    $taskresult += "  <tr>`n"
    $taskresult += "    <td>Initiatior</td>`n"
    $taskresult += "    <td>$($results[$mon_task].Initiatior)</td>`n"
    $taskresult += "  </tr>`n"
    $taskresult += "  <tr>`n"
    $taskresult += "    <td>Description</td>`n"
    $taskresult += "    <td>$($results[$mon_task].Description)</td>`n"
    $taskresult += "  </tr>`n"
    $taskresult += "  <tr>`n"
    $taskresult += "    <td>id</td>`n"
    $taskresult += "    <td>$($results[$mon_task].id)</td>`n"
    $taskresult += "  </tr>`n"
    $taskresult += "  <tr>`n"
    $taskresult += "    <td>State</td>`n"
    $taskresult += "    <td>$($taskstatus)</td>`n"
    $taskresult += "  </tr>`n"
    $taskresult += "  <tr>`n"
    $taskresult += "    <td>StartTime</td>`n"
    $taskresult += "    <td>$($results[$mon_task].StartTime)</td>`n"
    $taskresult += "  </tr>`n"
#        $taskresult += "  <tr>`n"
#        $taskresult += "    <td>Progress(%)</td>`n"
#        $taskresult += "    <td>$($results[$mon_task].'Progress(%)')</td>`n"
#        $taskresult += "  </tr>`n"
    $taskresult += "  <tr>`n"
    $taskresult += "    <td>Finishtime</td>`n"
    $taskresult += "    <td>$($finishtime)</td>`n"
    $taskresult += "  </tr>`n"
    $taskresult += "  <tr>`n"
    $taskresult += "    <td>Datacenter</td>`n"
    $taskresult += "    <td>$($results[$mon_task].Datacenter)</td>`n"
    $taskresult += "  </tr>`n"
    $taskresult += "  <tr>`n"
    $taskresult += "    <td>ComputeResource</td>`n"
    $taskresult += "    <td>$($results[$mon_task].ComputeResource)</td>`n"
    $taskresult += "  </tr>`n"
    $taskresult += "  <tr>`n"
    $taskresult += "    <td>Host</td>`n"
    $taskresult += "    <td>$($results[$mon_task].Host)</td>`n"
    $taskresult += "  </tr>`n"

# HTML Table Close

    $taskresult += "</table>`n"

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

$smtp = New-Object Net.Mail.SmtpClient($SmtpServer, 25)
$msg = new-object Net.Mail.MailMessage
   
#From Address
$msg.From = $msgfrom
#To Address, Copy the below line for multiple recipients
$msg.To.Add($mon_email)

#Message Body
$msg.IsBodyHtml = $true
$msg.Body=$header
$msg.Body+=”<strong>Task Result:</strong>`n <br />”
$msg.Body+=”`n <br />”
$msg.Body+=$taskresult

#Message Subject
$msg.Subject = “Monitored task for $($results[$mon_task].EntityName) & $($results[$mon_task].VirtualMachine) has completed”

$smtp.Send($msg)
echo $msg | fl
$msg.Dispose();


###########################################
## Pause Output for User
###########################################

 # Display task state

 if ($taskstatus -eq "Success") {
     Write-Host "Task successfully completed, sending notification" -ForegroundColor Green
 } else {
     Write-Host "Task Failed, sending notification" -ForegroundColor Red
 }

pause

############################################
## Stop Logging
############################################

Stop-Transcript