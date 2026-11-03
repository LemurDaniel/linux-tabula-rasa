# NOTE:
#   Requires: Linux, root, lsblk and mount, the loaded TabulaRasa module.
#
#   Get-TabulaRasaDataOverview -Disk (Get-TabulaRasaDisk | Select-Object -First 1)

function Get-TabulaRasaDataOverview {
    <#
    .SYNOPSIS
        Collects what is on a disk at a glance: partitions with usage, sampled blocks and found file types.

    .DESCRIPTION
        1. Partitions   Every partition with file system and label. Mountable ones are mounted
                        read-only for a moment to read the used space, then unmounted again.
        2. Samples      How many sampled blocks are not zero (Test-TabulaRasaDiskData).
        3. Signatures   A quick signature estimate (Find-TabulaRasaFileSignature -Mode Quick).

        Used by the text menu (Show-TabulaRasaDataOverview) and the web server.

    .EXAMPLE
        PS> Get-TabulaRasaDataOverview -Disk (Get-TabulaRasaDisk | Select-Object -First 1)
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The disk from Get-TabulaRasaDisk.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [PSCustomObject]
        $Disk
    )

    # Partitions
    $Partitions = foreach ($partition in @(Get-TabulaRasaPartition -Path $Disk.Path)) {
        $usedBytes = $null
        $state     = $partition.IsMountable ? 'Readable' : 'NotMountable'

        if ($partition.IsMountable) {
            try {
                $usedBytes = (Mount-TabulaRasaPartition -Path $partition.Path -FileSystem $partition.FileSystem).UsedBytes
            }
            catch [System.InvalidOperationException] {
                # Handled: a damaged file system just shows no usage, the deep scan still works.
                Write-Verbose "[Get-TabulaRasaDataOverview] '$($partition.Path)' cannot be mounted -> no usage."
                $state = 'Unreadable'
            }
            finally {
                Dismount-TabulaRasaPartition -Path $partition.Path
            }
        }

        [PSCustomObject]@{
            Name       = $partition.Name
            Path       = $partition.Path
            FileSystem = $partition.FileSystem
            Label      = $partition.Label
            SizeBytes  = $partition.SizeBytes
            UsedBytes  = $usedBytes
            State      = $state
        }
    }

    return [PSCustomObject]@{
        Disk       = $Disk
        Partitions = @($Partitions)
        Samples    = Test-TabulaRasaDiskData -Path $Disk.Path -SizeBytes $Disk.SizeBytes
        Signatures = Find-TabulaRasaFileSignature -Path $Disk.Path -SizeBytes $Disk.SizeBytes -Mode Quick
    }
}
