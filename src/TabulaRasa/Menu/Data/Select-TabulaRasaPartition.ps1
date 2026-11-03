function Select-TabulaRasaPartition {
    <#
    .SYNOPSIS
        Lets the user pick a partition of a disk, returns $null on 'Back' or when there is none.

    .DESCRIPTION
        A disk with exactly one fitting partition skips the question.
        With -MountableOnly only partitions Mount-TabulaRasaPartition can open are offered.

    .EXAMPLE
        PS> Select-TabulaRasaPartition -Disk $disk -MountableOnly
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
        $Disk,

        <#
        [Optional]
        Only offers partitions with a mountable file system.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.Management.Automation.SwitchParameter]
        $MountableOnly
    )

    $Partitions = @(Get-TabulaRasaPartition -Path $Disk.Path | Where-Object { -NOT $MountableOnly -OR $_.IsMountable })

    if ($Partitions.Count -EQ 0) {
        Write-SpectreHost -Message '[yellow]No readable partition found. The deep scan still works without a file system.[/]'
        Read-SpectrePause
        return $null
    }
    if ($Partitions.Count -EQ 1) {
        return $Partitions[0]
    }

    $Choices = @(
        foreach ($partition in $Partitions) {
            [PSCustomObject]@{
                Label     = Get-SpectreEscapedText -Text "$($partition.Path)  $($partition.FileSystem)  $(Format-TabulaRasaSize -Bytes $partition.SizeBytes)  $($partition.Label)"
                Partition = $partition
            }
        }
        [PSCustomObject]@{ Label = 'Back'; Partition = $null }
    )
    return (Read-SpectreSelection -Message 'Select a partition' -Choices $Choices -ChoiceLabelProperty Label).Partition
}
