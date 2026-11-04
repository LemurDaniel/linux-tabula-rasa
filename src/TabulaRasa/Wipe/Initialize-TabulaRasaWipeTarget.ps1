# NOTE:
#   Requires: Linux, root, lsblk and blockdev.
#
#   Initialize-TabulaRasaWipeTarget -Path /dev/sdb

#
#   Chapters:
#     PREPARE THE WIPE TARGET   Refuses the boot stick and foreign mounts, unmounts and unlocks the disk.
#

function Initialize-TabulaRasaWipeTarget {
    <#
    .SYNOPSIS
        Makes sure a disk may be wiped and nothing holds it.

    .DESCRIPTION
        > The disk is the boot stick
            - Refuse, the stick never wipes itself.
        > A partition is mounted by Mount-TabulaRasaPartition (under /run/tabula-rasa/mnt)
            - Unmount it.
        > A partition is mounted anywhere else, or used as swap
            - Refuse, something outside Tabula Rasa uses the disk.
        > Always
            - Make the disk and its partitions writable again (blockdev --setrw).

    .EXAMPLE
        PS> Initialize-TabulaRasaWipeTarget -Path /dev/sdb
    #>

    # Prepares the wipe, the confirmation happened in Invoke-TabulaRasaWipe. -WhatIf has no meaning here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param (
        <#
        [Required]
        The device path of the disk, e.g. '/dev/sdb'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Path
    )

    $MOUNT_ROOT = '/run/tabula-rasa/mnt/'

    # ===========================================================================
    # =======================   PREPARE THE WIPE TARGET   =======================
    # ===========================================================================
    #
    #   1. Boot stick   The boot stick is refused, it never wipes itself.
    #   2. Mounts       Unmounts Tabula Rasa mounts, refuses any other mount or swap.
    #   3. Writable     Makes the disk and its partitions writable again.
    #

    # ---------------------------------------------------------------------------
    # Boot stick
    #   The boot stick is refused, it never wipes itself.
    # ---------------------------------------------------------------------------

    if ((Split-Path -Path $Path -Leaf) -IN @(Get-TabulaRasaBootDisk)) {
        throw [System.InvalidOperationException]::new("'$Path' is the boot stick and must never be wiped.")
    }

    # ---------------------------------------------------------------------------
    # Mounts
    #   Unmounts Tabula Rasa mounts, refuses any other mount or swap.
    # ---------------------------------------------------------------------------

    # The disk and every partition as one flat list.
    # {"blockdevices":[{"path":"/dev/sdb","mountpoint":null},{"path":"/dev/sdb1","mountpoint":"/run/tabula-rasa/mnt/sdb1"}]}
    $LsblkJson = lsblk --json --list --output PATH,MOUNTPOINT $Path
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("lsblk must list '$Path' and its partitions, got exit code $LASTEXITCODE.")
    }
    $Devices = ($LsblkJson | ConvertFrom-Json).blockdevices

    foreach ($device in $Devices | Where-Object { -NOT [System.String]::IsNullOrEmpty($_.mountpoint) }) {
        # A partition is mounted by Mount-TabulaRasaPartition
        if ($device.mountpoint.StartsWith($MOUNT_ROOT, [System.StringComparison]::Ordinal)) {
            Write-Verbose "[Initialize-TabulaRasaWipeTarget] '$($device.path)' is still mounted by Tabula Rasa -> unmounting."
            Dismount-TabulaRasaPartition -Path $device.path
            continue
        }
        # A partition is mounted anywhere else, or used as swap
        throw [System.InvalidOperationException]::new("'$($device.path)' is in use at '$($device.mountpoint)', it must be unmounted before the wipe.")
    }

    # ---------------------------------------------------------------------------
    # Writable
    #   Makes the disk and its partitions writable again.
    # ---------------------------------------------------------------------------

    foreach ($device in $Devices) {
        blockdev --setrw $device.path
        if ($LASTEXITCODE -NE 0) {
            throw [System.InvalidOperationException]::new("blockdev must make '$($device.path)' writable, got exit code $LASTEXITCODE.")
        }
    }
}
