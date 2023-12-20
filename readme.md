# Ubiquiti Firmware Update PowerShell Script

## Skript
[ubnt_upgrade_dev.ps1](T:\GitHub\Ubiquiti-FWUpdate-Powershell\ubnt_upgrade_dev.ps1)

## Parameters
### Parameterübersicht

| Parameter       | Wert                                  | Beispiel                                   | Mandatory | Default  |
|-----------------|---------------------------------------|--------------------------------------------|-----------|----------|
| Server          | Serveradresse                         | ubnt.ts-man.ch                            | true      | -        |
| Port            | HTTPS Port des Servers                 | 8443                                       | false     | 8443     |
| Sites           | Sites die geprüft werden sollen        | 'default','4p236c5s'                      | false     | -        |
| ExcludeSites    | Seiten die nicht geprüft werden sollen | '4p236c5s'                                | false     | -        |
| Username        | Benutzername eines Admin users         | updAdmin                                   | true      | -        |
| Password        | Passwort des Admin Users                | mySecurePass                              | true      | -        |
| Info            | Gibt mehr Infos aus                     | $true / $false                            | false     | $false   |
| UpdateAPs       | APs aktualisieren                       | $true                                     | false     | $false   |
| UpdateSwitches  | Switches aktualisieren                  | $true                                     | false     | $false   |
| UpdateGateways  | Firewalls aktualisieren                 | $false                                    | false     | $false   |
| DryRun          | Führt das Skript aus, aktualisiert die Geräte NICHT | $true                            | false     | $false   |

## Sites zum Ausschliessen

| SiteName  | SiteID   |
|-----------|----------|
| Site A    | imywerwc |
| Site B    | ai0cgmek |
| Site C    | 4p236c5s |
| Site D    | 83o05okv |

## Beispiel

Zuerst Firewalls aktualisieren, dann Switches, dann APs:

```powershell
.\ubnt_upgrade_dev.ps1 -Server 'clodu.test.com' -Port 443 -Username 'admin' -Password '**********' -ExcludeSite imywerwc,ai0cgmek,4p236c5s,83o05okv -UpdateAPs -UpdateSwitches -UpdateGateways -DryRun