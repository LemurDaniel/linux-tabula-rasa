# NOTE:
#   Requires: Linux, findmnt, lsblk, losetup and blkid (util-linux), a system booted by live-boot.
#
#   Get-TabulaRasaBootDisk

#
#   Chapters:
#     FIND THE BOOT DISKS   Every disk below the live medium, plus every Ventoy stick.
#

function Get-TabulaRasaBootDisk {
    <#
    .SYNOPSIS
        Returns the kernel names of the disks the live system runs from, e.g. 'sdb'. Never wiped, never listed.

    .DESCRIPTION
        live-boot mounts the boot medium at /run/live/medium. Its source can be:
        - a partition or a whole disk       /dev/sdb1, /dev/sdb, /dev/sr0  (a flashed stick, a DVD)
        - a device-mapper device             /dev/dm-0                      (Ventoy maps the ISO this way)
        - a loop device over an ISO file     /dev/loop0                     (findiso= on a file system)
        lsblk --inverse walks from the source up to the disks it lives on. A loop device is first
        followed to the partition that holds its ISO file.

        Every disk with a partition labeled 'Ventoy' counts as boot disk too: a second Ventoy stick
        is hidden rather than risking the one the system runs from.

    .EXAMPLE
        PS> Get-TabulaRasaBootDisk
        sdb
    #>

    [CmdletBinding()]
    [OutputType([System.String[]])]
    param ()

    $LIVE_MEDIUM_PATH = '/run/live/medium'
    $VENTOY_LABEL     = 'Ventoy'

    # ===========================================================================
    # =========================   FIND THE BOOT DISKS   =========================
    # ===========================================================================
    #
    #   1. Live medium   Resolves the source of the live medium, a loop device to its file system.
    #   2. Disks below   Walks from the source up to the disks it lives on.
    #   3. Ventoy        Adds every disk with a partition labeled Ventoy.
    #

    # ---------------------------------------------------------------------------
    # Live medium
    #   Resolves the source of the live medium, a loop device to its file system.
    # ---------------------------------------------------------------------------

    $source = "$(findmnt --noheadings --output SOURCE $LIVE_MEDIUM_PATH 2>$null)".Trim()

    # A loop device: the disk is the one that holds its ISO file.
    if ($source -LIKE '/dev/loop*') {
        $backingFile = "$(losetup --noheadings --output BACK-FILE $source 2>$null)".Trim()
        if (-NOT [System.String]::IsNullOrEmpty($backingFile)) {
            Write-Verbose "[Get-TabulaRasaBootDisk] Live medium '$source' is the file '$backingFile'."
            $source = "$(findmnt --noheadings --output SOURCE --target $backingFile 2>$null)".Trim()
        }
    }

    # ---------------------------------------------------------------------------
    # Disks below
    #   Walks from the source up to the disks it lives on.
    # ---------------------------------------------------------------------------

    $BootDisks = [System.Collections.Generic.List[System.String]]::new()

    if ([System.String]::IsNullOrEmpty($source)) {
        Write-Verbose "[Get-TabulaRasaBootDisk] '$LIVE_MEDIUM_PATH' is not mounted -> only Ventoy sticks are hidden."
    }
    else {
        # 'lsblk --inverse --list' prints the source and everything it depends on, one line each:
        # 'dm-0 dm', 'sdb1 part', 'sdb disk' => sdb
        $chain = lsblk --inverse --list --noheadings --output NAME,TYPE $source 2>$null
        foreach ($line in $chain) {
            $name, $type = "$line".Trim() -split '\s+', 2
            # loop: an ISO on a file system, or a test image. Get-TabulaRasaDisk lists type 'disk' only anyway.
            if ($type -IN @('disk', 'rom', 'loop') -AND $name -NOTIN $BootDisks) {
                $BootDisks.Add($name)
            }
        }
        Write-Verbose "[Get-TabulaRasaBootDisk] Live medium '$source' lives on: $($BootDisks -join ', ')."
    }

    # ---------------------------------------------------------------------------
    # Ventoy
    #   Adds every disk with a partition labeled Ventoy.
    # ---------------------------------------------------------------------------

    foreach ($partition in @(blkid --output device --match-token "LABEL=$VENTOY_LABEL" 2>$null)) {
        $disk = "$(lsblk --noheadings --nodeps --output PKNAME $partition 2>$null)".Trim()
        if (-NOT [System.String]::IsNullOrEmpty($disk) -AND $disk -NOTIN $BootDisks) {
            Write-Verbose "[Get-TabulaRasaBootDisk] '$partition' is a Ventoy partition -> hiding '$disk'."
            $BootDisks.Add($disk)
        }
    }

    return [System.String[]] $BootDisks
}
