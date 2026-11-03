# NOTE:
#   Requires: Linux, root, findmnt, umount and blockdev (util-linux).
#
#   Dismount-TabulaRasaPartition -Path /dev/sdb1

function Dismount-TabulaRasaPartition {
    <#
    .SYNOPSIS
        Unmounts a partition mounted by Mount-TabulaRasaPartition and makes the device writable again.

    .DESCRIPTION
        Undoes both steps of Mount-TabulaRasaPartition: the mount and the read-only flag.
        Does nothing when the partition is not mounted, so it is safe in finally blocks.

    .EXAMPLE
        PS> Dismount-TabulaRasaPartition -Path /dev/sdb1
    #>

    [CmdletBinding()]
    param (
        <#
        [Required]
        The device path of the partition, e.g. '/dev/sdb1'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Path
    )

    $MOUNT_ROOT = '/run/tabula-rasa/mnt'
    $MountPoint = Join-Path -Path $MOUNT_ROOT -ChildPath (Split-Path -Path $Path -Leaf)

    # findmnt exits with 1 when nothing is mounted there.
    $null = findmnt --noheadings $MountPoint
    if ($LASTEXITCODE -EQ 0) {
        Write-Verbose "[Dismount-TabulaRasaPartition] Unmounting '$MountPoint'."
        umount $MountPoint
        if ($LASTEXITCODE -NE 0) {
            throw [System.InvalidOperationException]::new("umount must release '$MountPoint', got exit code $LASTEXITCODE.")
        }
    }

    # Restores the flag set in Mount-TabulaRasaPartition.
    blockdev --setrw $Path
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("blockdev must set '$Path' writable again, got exit code $LASTEXITCODE.")
    }
}
