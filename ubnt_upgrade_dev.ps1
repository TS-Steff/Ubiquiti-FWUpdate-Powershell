<#
    .NAME
    ubnt_upgrade_dev

    .SYNOPSIS
    Update APs, Switches and Gateways

    .SYNTAX
    ubnt_upgrade_dev [[-Server] <string>] [[-username] <string>] [[-password] <string>]

    .DESCRIPTION
    Checks if there are devices with available FW-Upgrade and runs the upgrade

    .PARAMETER Server
    Specifies the ubnt controller server

    .PARAMETER Port
    (Optional) Specifies the ubnt controller server port (Default = 8443)

    .PARAMETER Username
    Username to connect to ubnt server

    .PARAMETER Password
    Password for Username to connect

    .PARAMETER Sites
    (Optional) Update specific sites only

    .PARAMETER ExcludeSite
    (Optional) To use if you would like to update all sites except a couple

    .PARAMETER Info
    (Optional) Output of additional info (Default = False)

    .PARAMETER UpdateAPs
    (Optional) Update Access Points (Default = True)

    .PARAMETER UpdateSwitches
    (Optional) Update Switches (Default = True)

    .PARAMETER UpdateGateways
    (Optional) Update Gateways (Default = True)

    .PARAMETER DryRun
    (Optional) Run full script except do not send update command to APs

    .NOTES
    20220610 Initial Version

#>

#https://community.ui.com/questions/Need-Help-with-Unifi-API-devmgr-and-power-cycle/567cc9ba-40dd-4b07-962a-df05ab88f398
#https://social.technet.microsoft.com/forums/de-DE/160aea25-c10c-4bbd-a12e-d7160ebe6a00/invokerestmethod-issue-with-post-of-json-payload?forum=winserverpowershell
#https://ubntwiki.com/products/software/unifi-controller/api
#https://community.ui.com/questions/PHP-client-class-to-access-the-UniFi-controller-API-updates-and-discussion/86cff6e2-06ad-46a2-8e0d-d91004f78752
#https://github.com/Art-of-WiFi/UniFi-API-client/blob/master/src/Client.php

[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
        [string]$Server = '',

    [Parameter(Mandatory=$false)]
        [string]$Port = '8443',

    [Parameter(Mandatory=$false)]
        [array]$Sites = @(),

    [Parameter(Mandatory=$false)]
        [array]$ExcludeSite = @('4p236c5s'),

    [Parameter(Mandatory=$true)]
        [string]$Username = '',

    [Parameter(Mandatory=$true)]
        [string]$Password = '',

    [Parameter(Mandatory=$false)]
        [switch]$Info = $false,
    
    [Parameter(Mandatory=$false)]
        [switch]$UpdateAPs = $false,

    [Parameter(Mandatory=$false)]
        [switch]$UpdateSwitches = $false,

    [Parameter(Mandatory=$false)]
        [switch]$UpdateGateways = $false,
    
    [Parameter(Mandatory=$false)]
        [switch]$DryRun = $false
)

#Ignore SSL Errors
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}  

#Define supported Protocols
[System.Net.ServicePointManager]::SecurityProtocol = @("Tls12","Tls11","Tls","Ssl3")

# Create $controller and $credential using multiple variables/parameters.
[string]$controller = "https://$($server):$($port)"
[string]$credential = "`{`"username`":`"$username`",`"password`":`"$password`"`}"

try {
    write-host "Connecting to Controller" -ForegroundColor Green
    $null = Invoke-Restmethod -Uri "$controller/api/login" -method post -body $credential -ContentType "application/json; charset=utf-8"  -SessionVariable myWebSession
    sleep -Seconds 1
}catch{
	Write-Warning "Authentication failed"
    Write-Warning $_
	Exit
}

$sitesTable = @()
#if($Sites.Count -eq 0){
    write-host "Getting Sites" -ForegroundColor Green
    try {
        sleep -Seconds 1
        $allSites = Invoke-WebRequest -Uri "$controller/api/self/sites" -WebSession $myWebSession -UseBasicParsing
    }catch{
        write-warning $_
    }

    $allSites = ConvertFrom-Json($allSites)

    
    foreach($Site in $allSites.data){
        # no sites fiven in parameters
        if($Sites.count -eq 0){
            if($ExcludeSite -contains $Site.name -eq $false){
                $siteObject = [PSCustomObject]@{
                    "ID" = $site.name
                    "name" = $site.desc
                }
                $sitesTable += $siteObject
            }
        }else{
        # sites in parameter
            if($Sites -Contains $Site.name -eq $true){
                $siteObject = [PSCustomObject]@{
                    "ID" = $site.name
                    "name" = $site.desc
                }
                $sitesTable += $siteObject
            }
        }
    }
#}

if($info){
    $sitesTable | Format-Table * -AutoSize
}

if($Info){ 
    write-host "Sites to look for updates:"$sitesTable.Count 
    write-host "Update APs: $UpdateAPs"
    write-host "Update Switches: $UpdateSwitches"
    write-host "Update Gateways: $UpdateGateways"
    write-host ""
}


$tableDevicesUpgrd = @()

write-host "Getting Devices for"$sitesTable.count"sites" -ForegroundColor Green


foreach ($Site in $sitesTable){
    $siteID = $Site.ID
    

    if($Info){
        write-host "Site:"$Site.name"("$Site.ID")" -ForegroundColor yellow
    }
    
    try{
        $jsonSiteDevs = Invoke-Restmethod -Uri "$controller/api/s/$siteID/stat/device-basic" -WebSession $myWebSession
        sleep -Milliseconds 250
    }catch{
        Write-Warning $_
        Exit
    }
    $SiteDevs = $jsonSiteDevs.data
    #write-host $SiteDevs -ForegroundColor Blue

    #write-host $SiteDevs.count "Devices"
    $tableSiteDevices = @()

    foreach($device in $siteDevs){
        #write-host $device -ForegroundColor Red

        # all 
        $devMAC = $device.mac

        $jsonDevice = Invoke-Restmethod -Uri "$controller/api/s/$siteID/stat/device/$devMAC" -WebSession $myWebSession
        $deviceData = $jsonDevice.data
        
        if($info){ write-host $deviceData -ForegroundColor Magenta }

        $objSiteAP = [PSCustomObject]@{
            "siteID"   = $Site.ID
            "sitename" = $Site.name
            "name"     = $deviceData.name
            "type"     = $deviceData.type
            "mac"      = $deviceData.mac
            "model"    = $deviceData.model
            "serial"   = $deviceData.serial
            "CurrFW"   = $deviceData.version
            "NextFW"   = $deviceData.upgrade_to_firmware
            "state"    = $deviceData.state
        }
        $tableSiteDevices += $objSiteAP

        if($deviceData.upgrade_to_firmware){ $tableDevicesUpgrd += $objSiteAP } 
    }
    
    if($Info){
        write-host
        write-host "TableSiteDevs" -ForegroundColor red
        $tableSiteDevices | Format-Table * -AutoSize
        write-host "------------------" -ForegroundColor Red
    }


}

if($Info){ 
    write-host
    write-host "TableDevicesUpgrd" -ForegroundColor DarkYellow
    $tableDevicesUpgrd | FT * -AutoSize 
    write-host "------------------" -ForegroundColor DarkYellow    
}



$uapUpgradable = $tableDevicesUpgrd | Where-Object {($_.type -eq "uap") -and ($_.state -eq 1)}
$uswUpgradable = $tableDevicesUpgrd | Where-Object {($_.type -eq "usw") -and ($_.state -eq 1)}
$ugwUpgradable = $tableDevicesUpgrd | Where-Object {($_.type -eq "ugw") -and ($_.state -eq 1)}


#$uapUpgradable | FT * -AutoSize

$uapUpgradableCnt = $uapUpgradable.count
$uswUpgradableCnt = $uswUpgradable.count
$ugwUpgradableCnt = $ugwUpgradable.count

write-host $uapUpgradableCnt "UAP Upgradable" -ForegroundColor Yellow
write-host $uswUpgradableCnt "USW Upgradable" -ForegroundColor Yellow
write-host $ugwUpgradableCnt "UGW Upgradable" -ForegroundColor Yellow

$doUpgreads = @()
if($UpdateAPs){      $doUpgreads += $tableDevicesUpgrd | Where-Object {($_.type -eq "uap") -and ($_.state -eq 1)} }
if($UpdateSwitches){ $doUpgreads += $tableDevicesUpgrd | Where-Object {($_.type -eq "usw") -and ($_.state -eq 1)} } 
if($UpdateGateways){ $doUpgreads += $tableDevicesUpgrd | Where-Object {($_.type -eq "ugw") -and ($_.state -eq 1)} } 
  

if($Info){ write-host; write-host "Do Upgrades Table" -ForegroundColor Green; $doUpgreads | ft * -AutoSize; write-host "----------------" -ForegroundColor Green }

if($doUpgreads.Count -ne 0){
    if(!$DryRun){
        write-host "do update" -ForegroundColor Yellow
        write-host
        write-host "Updating $uapUpgradableCnt UAPs" -ForegroundColor Green
        foreach($device in $doUpgreads){

            write-host "send request to "$device.mac -ForegroundColor DarkYellow
            $siteID = $device.siteID
        
            $JSON = @{
                "cmd" = "upgrade"
                "mac" = $device.mac
            } | ConvertTo-Json

            try{
                $upgradeRequestReturn = Invoke-RestMethod -Uri "$controller/api/s/$siteID/cmd/devmgr/upgrade/$devMAC" -WebSession $myWebSession -ContentType "application/json; charset=utf-8" -Method post -Body $JSON    
                $upgradeRequestReturn.data
                sleep -Seconds 1
            }catch{
                Write-Warning $_
            }
        }
    }else{
        write-host "dry run" -ForegroundColor yellow
        $doUpgreads | ft * -AutoSize
        exit
    }
}else{ write-warning "No Devices to Update" }

exit
#if($UpdateAPs){

#}else{
#    write-warning "no ap update"
#}


<#
#logoff
try {
    $null = Invoke-WebRequest -Uri "$controller/api/logout" -WebSession $myWebSession
}catch{
	Write-Warning "Authentication failed"
    Write-Warning $_
	Exit
}
#>