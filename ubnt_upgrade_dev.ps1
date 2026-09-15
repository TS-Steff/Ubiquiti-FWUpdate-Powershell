<#
    .SYNOPSIS
    Lists or installs available firmware updates for UniFi devices.

    .DESCRIPTION
    Connects to a UniFi OS Server by default, or to a classic UniFi Network
    Controller when -Legacy is specified. Finds firmware updates for access
    points, switches and gateways. Updates are installed only for device types
    explicitly selected with the corresponding update switch.

    .PARAMETER Server
    Hostname or IP address of the UniFi controller, without protocol or port.

    .PARAMETER Port
    HTTPS port. Defaults to 443 for UniFi OS and 8443 with -Legacy.

    .PARAMETER Legacy
    Uses the classic UniFi Network Controller API instead of the UniFi OS API.

    .PARAMETER Username
    Username used to authenticate with the controller.

    .PARAMETER Password
    Password used to authenticate with the controller.

    .PARAMETER Sites
    Site IDs to process. When omitted, all accessible sites are processed.

    .PARAMETER ExcludeSite
    Site IDs to exclude when -Sites is not specified.

    .PARAMETER Info
    Displays additional site and device information.

    .PARAMETER ListSites
    Lists sites containing upgradable devices and exits without upgrading.

    .PARAMETER UpdateAPs
    Installs available firmware updates on access points.

    .PARAMETER UpdateSwitches
    Installs available firmware updates on switches.

    .PARAMETER UpdateGateways
    Installs available firmware updates on gateways.

    .PARAMETER DryRun
    Displays the selected updates without sending upgrade commands.

    .EXAMPLE
    .\ubnt_upgrade_dev.ps1 -Server 'unifi.example.com' -Username 'FWUpgrade' -Password 'secret' -ListSites

    Lists all UniFi OS sites containing devices with available firmware updates.

    .EXAMPLE
    .\ubnt_upgrade_dev.ps1 -Server 'unifi.example.com' -Username 'FWUpgrade' -Password 'secret' -UpdateSwitches -DryRun

    Shows the switches that would be upgraded on a UniFi OS Server.

    .EXAMPLE
    .\ubnt_upgrade_dev.ps1 -Server 'controller.example.com' -Username 'admin' -Password 'secret' -Legacy -UpdateAPs

    Installs available access point updates through a classic controller.

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
        [string]$Port = '',

    [Parameter(Mandatory=$false)]
        [switch]$Legacy = $false,

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
        [switch]$ListSites = $false,
    
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
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Create controller URLs and credentials.
if ([string]::IsNullOrWhiteSpace($Port)) {
    $Port = if ($Legacy) { '8443' } else { '443' }
}

[string]$controller = "https://$($server):$($port)"
[string]$loginPath = if ($Legacy) { '/api/login' } else { '/api/auth/login' }
[string]$apiBase = if ($Legacy) { $controller } else { "$controller/proxy/network" }
[string]$credential = @{
    username = $Username
    password = $Password
} | ConvertTo-Json -Compress

try {
    write-host "Connecting to Controller" -ForegroundColor Green
    write-host "Mode: $(if ($Legacy) { 'Legacy Controller' } else { 'UniFi OS' })" -ForegroundColor Yellow
    write-host "URL: $controller$loginPath" -ForegroundColor Yellow
    write-host "Username: $Username" -ForegroundColor Yellow
    $loginResponse = Invoke-WebRequest -Uri "$controller$loginPath" -Method Post -Body $credential -ContentType "application/json; charset=utf-8" -SessionVariable myWebSession -UseBasicParsing -Verbose
    Start-Sleep -Seconds 1
} catch {
    Write-Warning "Authentication failed"
    Write-Warning $_
    Write-Warning "Error details: $($Error[0].Exception.Message)"
    Exit
}

$requestHeaders = @{}
if (!$Legacy) {
    $csrfToken = [string]$loginResponse.Headers['X-CSRF-Token']

    if ([string]::IsNullOrWhiteSpace($csrfToken)) {
        $tokenCookie = $myWebSession.Cookies.GetCookies([uri]$controller) |
            Where-Object { $_.Name -eq 'TOKEN' } |
            Select-Object -First 1

        if ($tokenCookie) {
            try {
                $jwtPayload = $tokenCookie.Value.Split('.')[1].Replace('-', '+').Replace('_', '/')
                $jwtPayload = $jwtPayload.PadRight($jwtPayload.Length + ((4 - $jwtPayload.Length % 4) % 4), '=')
                $jwtData = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($jwtPayload)) | ConvertFrom-Json
                $csrfToken = [string]$jwtData.csrfToken
            } catch {
                Write-Verbose "CSRF token could not be extracted from the UniFi OS session token."
            }
        }
    }

    if (![string]::IsNullOrWhiteSpace($csrfToken)) {
        $requestHeaders['X-CSRF-Token'] = $csrfToken
    }
}

$sitesTable = @()
#if($Sites.Count -eq 0){
    write-host "Getting Sites" -ForegroundColor Green
    try {
        Start-Sleep -Seconds 1
        $allSites = Invoke-WebRequest -Uri "$apiBase/api/self/sites" -WebSession $myWebSession -UseBasicParsing
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
        $jsonSiteDevs = Invoke-Restmethod -Uri "$apiBase/api/s/$siteID/stat/device-basic" -WebSession $myWebSession
        Start-Sleep -Milliseconds 250
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

        $jsonDevice = Invoke-Restmethod -Uri "$apiBase/api/s/$siteID/stat/device/$devMAC" -WebSession $myWebSession
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
    $tableDevicesUpgrd | Format-Table * -AutoSize 
    write-host "------------------" -ForegroundColor DarkYellow    
}

if ($ListSites) {
    $siteUpgradeTable = @(
        foreach ($site in $sitesTable) {
            $siteDevices = @($tableDevicesUpgrd | Where-Object {
                $_.siteID -eq $site.ID -and $_.state -eq 1
            })
            $uapCount = @($siteDevices | Where-Object { $_.type -eq 'uap' }).Count
            $uswCount = @($siteDevices | Where-Object { $_.type -eq 'usw' }).Count
            $ugwCount = @($siteDevices | Where-Object { $_.type -eq 'ugw' }).Count

            if (($uapCount + $uswCount + $ugwCount) -gt 0) {
                [PSCustomObject][ordered]@{
                    'SiteID'    = $site.ID
                    'Site Name' = $site.name
                    'UAP Num'   = $uapCount
                    'USW Num'   = $uswCount
                    'UGW Num'   = $ugwCount
                }
            }
        }
    )

    if ($siteUpgradeTable.Count -gt 0) {
        $siteUpgradeTable | Format-Table -AutoSize
    } else {
        Write-Warning 'No sites with upgradable devices found.'
    }

    exit
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

if (!$UpdateAPs -and !$UpdateSwitches -and !$UpdateGateways) {
    Write-Warning "No device types selected. Use -UpdateAPs, -UpdateSwitches and/or -UpdateGateways."
    exit
}

$doUpgreads = @()
if($UpdateAPs){      $doUpgreads += $tableDevicesUpgrd | Where-Object {($_.type -eq "uap") -and ($_.state -eq 1)} }
if($UpdateSwitches){ $doUpgreads += $tableDevicesUpgrd | Where-Object {($_.type -eq "usw") -and ($_.state -eq 1)} } 
if($UpdateGateways){ $doUpgreads += $tableDevicesUpgrd | Where-Object {($_.type -eq "ugw") -and ($_.state -eq 1)} } 
  

if($Info){ write-host; write-host "Do Upgrades Table" -ForegroundColor Green; $doUpgreads | Format-Table * -AutoSize; write-host "----------------" -ForegroundColor Green }

if($doUpgreads.Count -ne 0){
    if(!$DryRun){
        write-host "do update" -ForegroundColor Yellow
        write-host
        write-host "Updating $uapUpgradableCnt UAPs" -ForegroundColor Green
        foreach($device in $doUpgreads){

            write-host "send request to "$device.mac -ForegroundColor DarkYellow
            $siteID = $device.siteID
        
            $JSON = @{
                "mac" = $device.mac
            } | ConvertTo-Json

            try{
                $upgradeRequestReturn = Invoke-RestMethod -Uri "$apiBase/api/s/$siteID/cmd/devmgr/upgrade" -WebSession $myWebSession -Headers $requestHeaders -ContentType "application/json; charset=utf-8" -Method post -Body $JSON
                $upgradeRequestReturn.data
                Start-Sleep -Seconds 1
            }catch{
                Write-Warning $_
            }
        }
    }else{
        Start-Sleep -Seconds 1
        write-host "dry run" -ForegroundColor yellow
        $doUpgreads | Format-Table * -AutoSize
        exit
    }
}else{ write-warning "No upgradeable devices found for the selected device types." }

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
