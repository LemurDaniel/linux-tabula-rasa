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

    # Validations
    $MountOption = (Get-TabulaRasaMountOption)[$FileSystem]
    if ($null -EQ $MountOption) {
        throw [System.NotSupportedException]::new("File system '$FileSystem' of '$Path' must be one of: $((Get-TabulaRasaMountOption).Keys -join ', ').")
    }

    $MountPoint = Join-Path -Path $MOUNT_ROOT -ChildPath (Split-Path -Path $Path -Leaf)
    $null = New-Item -ItemType Directory -Path $MountPoint -Force

    # Read-only device
    blockdev --setro $Path
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("blockdev must set '$Path' read-only, got exit code $LASTEXITCODE.")
    }

    # Mount
    Write-Verbose "[Mount-TabulaRasaPartition] Mounting '$Path' ($($MountOption.Type), $($MountOption.Options)) at '$MountPoint'."
    # Full path: 'mount' is an alias of New-PSDrive on Windows, the analyzer and the reader would see that.
    & '/usr/bin/mount' -t $MountOption.Type -o $MountOption.Options $Path $MountPoint
    if ($LASTEXITCODE -NE 0) {
        blockdev --setrw $Path
        throw [System.InvalidOperationException]::new("mount must open '$Path' as '$($MountOption.Type)' read-only, got exit code $LASTEXITCODE.")
    }

    # Usage: 'df --output=size,used' prints a header line and one line with two numbers.
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
