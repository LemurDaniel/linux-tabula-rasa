# NOTE:
#   Requires: Linux, lsblk and findmnt (util-linux).
#
#   Get-TabulaRasaDisk | Format-Table Path, Kind, Model, Serial

function Get-TabulaRasaDisk {
    <#
    .SYNOPSIS
        Lists every disk that can be wiped, without the disk the live system booted from.

    .DESCRIPTION
        Reads the disks via lsblk and parses them with ConvertFrom-TabulaRasaLsblk.
        The boot disks (Get-TabulaRasaBootDisk, also a Ventoy stick) are always hidden, so the stick
        cannot wipe itself.

    .EXAMPLE
        PS> Get-TabulaRasaDisk | Format-Table Path, Kind, Model, Serial
    #>

    [CmdletBinding()]
    param ()

    $LSBLK_COLUMNS = 'NAME,PATH,TYPE,SIZE,MODEL,SERIAL,TRAN,ROTA,RM'

    $LsblkJson = lsblk --json --bytes --nodeps --output $LSBLK_COLUMNS
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("lsblk must list the disks, got exit code $LASTEXITCODE.")
    }

    $BootDisks = @(Get-TabulaRasaBootDisk)

    return $LsblkJson
    | ConvertFrom-TabulaRasaLsblk
    | Where-Object { $_.Name -NOTIN $BootDisks }
}
