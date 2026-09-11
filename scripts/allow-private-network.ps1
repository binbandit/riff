# Run as Administrator on Windows if the normal Windows Firewall prompt did not appear.
param([Parameter(Mandatory = $true)][string]$CompanionPath)
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path $CompanionPath).Path
if ([IO.Path]::GetFileName($exe) -ne 'Riff.Companion.exe') { throw 'Choose Riff.Companion.exe.' }
New-NetFirewallRule -DisplayName 'Riff companion (private local network)' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 49321 -Program $exe -Profile Private -RemoteAddress LocalSubnet
