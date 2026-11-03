# NOTE:
#   Requires: the TabulaRasa module next to this one, Pode, NetworkManager (nmcli), qrencode.
#
#   Import-Module /opt/tabula-rasa/TabulaRasaWeb
#   Start-TabulaRasaServer

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# Session
. $PSScriptRoot/Session/Enter-TabulaRasaWebSession.ps1
. $PSScriptRoot/Session/Test-TabulaRasaWebSession.ps1
. $PSScriptRoot/Session/Exit-TabulaRasaWebSession.ps1

# Jobs and replug
. $PSScriptRoot/Job/New-TabulaRasaWebJob.ps1
. $PSScriptRoot/Job/Invoke-TabulaRasaWebJob.ps1
. $PSScriptRoot/Replug/Update-TabulaRasaWebReplug.ps1

# Network
. $PSScriptRoot/Network/Get-TabulaRasaWebNetwork.ps1
. $PSScriptRoot/Network/Start-TabulaRasaWebHotspot.ps1

# Server
. $PSScriptRoot/Server/Write-TabulaRasaWebError.ps1
. $PSScriptRoot/Server/Resolve-TabulaRasaWebDisk.ps1
. $PSScriptRoot/Server/Start-TabulaRasaServer.ps1

Export-ModuleMember -Function @(
    # Session
    'Enter-TabulaRasaWebSession'
    'Test-TabulaRasaWebSession'
    'Exit-TabulaRasaWebSession'
    # Jobs and replug
    'New-TabulaRasaWebJob'
    'Invoke-TabulaRasaWebJob'
    'Update-TabulaRasaWebReplug'
    # Network
    'Get-TabulaRasaWebNetwork'
    'Start-TabulaRasaWebHotspot'
    # Server
    'Write-TabulaRasaWebError'
    'Resolve-TabulaRasaWebDisk'
    'Start-TabulaRasaServer'
)
