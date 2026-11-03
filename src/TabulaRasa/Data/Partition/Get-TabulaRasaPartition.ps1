function Get-TabulaRasaPartition {
    <#
    .SYNOPSIS
        Lists the partitions of a disk with file system and label.

    .DESCRIPTION
        Reads the disk via lsblk and parses it with ConvertFrom-TabulaRasaPartitionLsblk.
        IsMountable says whether Mount-TabulaRasaPartition can open the file system.

        lsblk takes file system and label from the udev database, which lags behind right after
        a device is plugged in (and is missing without udev). Partitions without a file system are
        probed again with 'blkid -p', which reads the superblock directly.

    .EXAMPLE
        PS> Get-TabulaRasaPartition -Path /dev/sdb
    #>

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

    $LSBLK_COLUMNS = 'NAME,PATH,TYPE,SIZE,FSTYPE,LABEL'

    $LsblkJson = lsblk --json --bytes --output $LSBLK_COLUMNS $Path
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("lsblk must list the partitions of '$Path', got exit code $LASTEXITCODE.")
    }

    $MountableFileSystems = (Get-TabulaRasaMountOption).Keys

    $Partitions = @($LsblkJson | ConvertFrom-TabulaRasaPartitionLsblk)

    # Probe again where udev had no file system. blkid exits with 2 when it finds none.
    foreach ($partition in $Partitions | Where-Object { [System.String]::IsNullOrEmpty($_.FileSystem) }) {
        $probed = blkid -p -o value -s TYPE $partition.Path 2>$null
        if ($LASTEXITCODE -EQ 0 -AND -NOT [System.String]::IsNullOrWhiteSpace($probed)) {
            Write-Verbose "[Get-TabulaRasaPartition] udev knew no file system on '$($partition.Path)', blkid found '$probed'."
            # Interpolated: blkid prints nothing for a missing label, and a cast of no output is $null.
            $partition.FileSystem = "$probed".Trim()
            $partition.Label      = "$(blkid -p -o value -s LABEL $partition.Path 2>$null)".Trim()
        }
    }

    return $Partitions
    | Select-Object -Property *, @{ Name = 'IsMountable'; Expression = { $_.FileSystem -IN $MountableFileSystems } }
}
