# NOTE:
#   Requires: Linux, root, lsblk, sleuthkit (fls), PwshSpectreConsole (for Start-TabulaRasa).
#
#   Import-Module /opt/tabula-rasa/TabulaRasa
#   Start-TabulaRasa

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

# Compiled hot loop of the signature scan, see Data/Signature/SignatureScanner.cs.
if ($null -EQ ('TabulaRasa.SignatureScanner' -as [System.Type])) {
    Add-Type -Path $PSScriptRoot/Data/Signature/SignatureScanner.cs
}

# Disk
. $PSScriptRoot/Disk/Resolve-TabulaRasaDiskKind.ps1
. $PSScriptRoot/Disk/ConvertFrom-TabulaRasaLsblk.ps1
. $PSScriptRoot/Disk/Get-TabulaRasaBootDisk.ps1
. $PSScriptRoot/Disk/Get-TabulaRasaDisk.ps1
. $PSScriptRoot/Disk/Compare-TabulaRasaDiskSet.ps1

# Data: samples, partitions, browsing, deleted files, signatures
. $PSScriptRoot/Data/Sample/Get-TabulaRasaSampleOffset.ps1
. $PSScriptRoot/Data/Sample/Test-TabulaRasaDiskData.ps1
. $PSScriptRoot/Data/Partition/ConvertFrom-TabulaRasaPartitionLsblk.ps1
. $PSScriptRoot/Data/Partition/Get-TabulaRasaMountOption.ps1
. $PSScriptRoot/Data/Partition/Get-TabulaRasaPartition.ps1
. $PSScriptRoot/Data/Browse/Mount-TabulaRasaPartition.ps1
. $PSScriptRoot/Data/Browse/Dismount-TabulaRasaPartition.ps1
. $PSScriptRoot/Data/Browse/Get-TabulaRasaDirectory.ps1
. $PSScriptRoot/Data/Deleted/ConvertFrom-TabulaRasaFlsBody.ps1
. $PSScriptRoot/Data/Deleted/Get-TabulaRasaDeletedFile.ps1
. $PSScriptRoot/Data/Signature/Find-TabulaRasaFileSignature.ps1
. $PSScriptRoot/Data/Sample/Get-TabulaRasaDataOverview.ps1

# Wipe
. $PSScriptRoot/Wipe/Resolve-TabulaRasaWipeMethod.ps1
. $PSScriptRoot/Wipe/Invoke-TabulaRasaWipe.ps1

# Menu
. $PSScriptRoot/Menu/Format-TabulaRasaSize.ps1
. $PSScriptRoot/Menu/Start-TabulaRasa.ps1
. $PSScriptRoot/Menu/Show-TabulaRasaDiskMenu.ps1
. $PSScriptRoot/Menu/Show-TabulaRasaWipeDialog.ps1
. $PSScriptRoot/Menu/Data/Select-TabulaRasaPartition.ps1
. $PSScriptRoot/Menu/Data/Show-TabulaRasaDataOverview.ps1
. $PSScriptRoot/Menu/Data/Show-TabulaRasaFileBrowser.ps1
. $PSScriptRoot/Menu/Data/Show-TabulaRasaDeletedFile.ps1
. $PSScriptRoot/Menu/Data/Show-TabulaRasaDeepScan.ps1

Export-ModuleMember -Function @(
    # Disk
    'Get-TabulaRasaDisk'
    'Compare-TabulaRasaDiskSet'
    # Data
    'Test-TabulaRasaDiskData'
    'Get-TabulaRasaPartition'
    'Mount-TabulaRasaPartition'
    'Dismount-TabulaRasaPartition'
    'Get-TabulaRasaDirectory'
    'Get-TabulaRasaDeletedFile'
    'Find-TabulaRasaFileSignature'
    'Get-TabulaRasaDataOverview'
    # Wipe
    'Resolve-TabulaRasaWipeMethod'
    'Invoke-TabulaRasaWipe'
    # Menu
    'Start-TabulaRasa'
)
