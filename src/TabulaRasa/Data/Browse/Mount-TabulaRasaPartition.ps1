# NOTE:
#   Requires: Linux, root, blockdev, mount and df, the kernel driver of the file system.
#
#   $mount = Mount-TabulaRasaPartition -Path /dev/sdb1 -FileSystem ntfs
#   Dismount-TabulaRasaPartition -Path /dev/sdb1

#
#   Chapters:
#     MOUNT READ-ONLY   Mounts a partition read-only and returns its usage.
#

function Mount-TabulaRasaPartition {
    <#
    .SYNOPSIS
        Mounts a partition read-only under /run/tabula-rasa/mnt and returns its usage.

    .DESCRIPTION
        1. Sets the block device read-only (blockdev --setro), so the kernel refuses every write.
        2. Mounts it with the read-only options from Get-TabulaRasaMountOption.
        3. Reads size and used bytes via df.

        Always pair with Dismount-TabulaRasaPartition, a wipe needs the partition unmounted.

    .EXAMPLE
        PS> $mount = Mount-TabulaRasaPartition -Path /dev/sdb1 -FileSystem ntfs
        PS> Get-TabulaRasaDirectory -MountPoint $mount.MountPoint
        PS> Dismount-TabulaRasaPartition -Path /dev/sdb1
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The device path of the partition, e.g. '/dev/sdb1'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Path,

        <#
        [Required]
        The file system from Get-TabulaRasaPartition, e.g. 'ntfs'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $FileSystem
    )

    $MOUNT_ROOT = '/run/tabula-rasa/mnt'

    # ===========================================================================
    # ===========================   MOUNT READ-ONLY   ===========================
    # ===========================================================================
    #
    #   1. Validations        Fails early on a file system that cannot be mounted,
    #                         then creates the mount point.
    #   2. Read-only device   Sets the block device read-only, the kernel refuses every write.
    #   3. Mount              Mounts the partition with the read-only options of its file system.
    #   4. Usage              Reads size and used bytes via df and returns them.
    #

    # ---------------------------------------------------------------------------
    # Validations
    #   Fails early on a file system that cannot be mounted,
    #   then creates the mount point.
    # ---------------------------------------------------------------------------

    $MountOption = (Get-TabulaRasaMountOption)[$FileSystem]
    if ($null -EQ $MountOption) {
        throw [System.NotSupportedException]::new("File system '$FileSystem' of '$Path' must be one of: $((Get-TabulaRasaMountOption).Keys -join ', ').")
    }

    $MountPoint = Join-Path -Path $MOUNT_ROOT -ChildPath (Split-Path -Path $Path -Leaf)
    $null = New-Item -ItemType Directory -Path $MountPoint -Force

    # ---------------------------------------------------------------------------
    # Read-only device
    #   Sets the block device read-only, the kernel refuses every write.
    # ---------------------------------------------------------------------------

    blockdev --setro $Path
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("blockdev must set '$Path' read-only, got exit code $LASTEXITCODE.")
    }

    # ---------------------------------------------------------------------------
    # Mount
    #   Mounts the partition with the read-only options of its file system.
    # ---------------------------------------------------------------------------

    Write-Verbose "[Mount-TabulaRasaPartition] Mounting '$Path' ($($MountOption.Type), $($MountOption.Options)) at '$MountPoint'."
    # Full path: 'mount' is an alias of New-PSDrive on Windows, the analyzer and the reader would see that.
    $mountOutput = & '/usr/bin/mount' -t $MountOption.Type -o $MountOption.Options $Path $MountPoint 2>&1
    if ($LASTEXITCODE -NE 0) {
        # Kept before the cleanup, blockdev below overwrites $LASTEXITCODE.
        $mountExitCode = $LASTEXITCODE
        blockdev --setrw $Path
        throw [System.InvalidOperationException]::new("mount must open '$Path' as '$($MountOption.Type)' read-only, got exit code $($mountExitCode): $("$mountOutput".Trim())")
    }

    # ---------------------------------------------------------------------------
    # Usage
    #   Reads size and used bytes via df and returns them.
    # ---------------------------------------------------------------------------

    # 'df --output=size,used' prints a header line and one line with two numbers.
    # '     1B-blocks         Used\n 31998951424   4096000000' => 31998951424, 4096000000
    $usageLine = df --block-size=1 --output=size,used $MountPoint | Select-Object -Last 1
    $usage     = $usageLine.Trim() -split '\s+'

    return [PSCustomObject]@{
        Path       = $Path
        MountPoint = $MountPoint
        SizeBytes  = [System.Int64] $usage[0]
        UsedBytes  = [System.Int64] $usage[1]
    }
}
