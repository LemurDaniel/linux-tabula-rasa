# NOTE:
#   Requires: Linux, findmnt and lsblk (util-linux), a system booted by live-boot.
#
#   Get-TabulaRasaBootDisk

function Get-TabulaRasaBootDisk {
    <#
    .SYNOPSIS
        Returns the kernel name of the disk the live system booted from, e.g. 'sdb'.

    .DESCRIPTION
        live-boot mounts the boot medium at /run/live/medium. Its source is a partition
        (/dev/sdb1) or the whole disk (/dev/sr0, /dev/sdb), lsblk resolves the parent disk.
        Returns $null when the live system was not booted from a medium (e.g. toram or a VM test).

    .EXAMPLE
        PS> Get-TabulaRasaBootDisk
        sdb
    #>

    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    $LIVE_MEDIUM_PATH = '/run/live/medium'

    $source = findmnt --noheadings --output SOURCE $LIVE_MEDIUM_PATH
    if ($LASTEXITCODE -NE 0 -OR [System.String]::IsNullOrWhiteSpace($source)) {
        Write-Verbose "[Get-TabulaRasaBootDisk] '$LIVE_MEDIUM_PATH' is not mounted -> no boot disk to hide."
        return $null
    }

    # A partition has a parent disk, a whole disk has none and is the boot disk itself.
    $parent = lsblk --noheadings --nodeps --output PKNAME $source.Trim()
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("lsblk must resolve the boot medium '$source', got exit code $LASTEXITCODE.")
    }

    $BootDisk = [System.String]::IsNullOrWhiteSpace($parent) ? (Split-Path -Path $source.Trim() -Leaf) : $parent.Trim()
    Write-Verbose "[Get-TabulaRasaBootDisk] Boot medium '$source' lives on disk '$BootDisk'."
    return $BootDisk
}
