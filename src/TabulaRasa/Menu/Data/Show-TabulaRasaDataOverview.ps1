function Show-TabulaRasaDataOverview {
    <#
    .SYNOPSIS
        Shows what is on a disk at a glance: partitions with usage, sampled blocks and found file types.

    .DESCRIPTION
        1. Partitions   Every partition with file system and label, mountable ones with used space.
        2. Samples      How many sampled blocks are not zero (Test-TabulaRasaDiskData).
        3. Signatures   A quick signature estimate (Find-TabulaRasaFileSignature -Mode Quick).

    .EXAMPLE
        PS> Show-TabulaRasaDataOverview -Disk (Get-TabulaRasaDisk | Select-Object -First 1)
    #>

    [CmdletBinding()]
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

    $Overview = Invoke-SpectreCommandWithStatus -Title "Reading $($Disk.Path) ..." -Spinner Dots -ScriptBlock {
        # Partitions, with usage for every mountable one. Unmounted again right away.
        $partitions = foreach ($partition in @(Get-TabulaRasaPartition -Path $Disk.Path)) {
            $used = 'n/a'
            if ($partition.IsMountable) {
                try {
                    $mount = Mount-TabulaRasaPartition -Path $partition.Path -FileSystem $partition.FileSystem
                    $used  = Format-TabulaRasaSize -Bytes $mount.UsedBytes
                }
                catch [System.InvalidOperationException] {
                    # Handled: a damaged file system just shows no usage, the deep scan still works.
                    $used = 'unreadable'
                }
                finally {
                    Dismount-TabulaRasaPartition -Path $partition.Path
                }
            }
            [PSCustomObject]@{
                Partition  = $partition.Path
                FileSystem = [System.String]::IsNullOrEmpty($partition.FileSystem) ? 'none' : $partition.FileSystem
                Label      = $partition.Label
                Size       = Format-TabulaRasaSize -Bytes $partition.SizeBytes
                Used       = $used
            }
        }

        [PSCustomObject]@{
            Partitions = @($partitions)
            Samples    = Test-TabulaRasaDiskData -Path $Disk.Path -SizeBytes $Disk.SizeBytes
            Signatures = Find-TabulaRasaFileSignature -Path $Disk.Path -SizeBytes $Disk.SizeBytes -Mode Quick
        }
    }

    # Partitions
    if ($Overview.Partitions.Count -GT 0) {
        $Overview.Partitions | Format-SpectreTable -Title 'Partitions' -Border Rounded | Out-SpectreHost
    }
    else {
        Write-SpectreHost -Message '[yellow]No partitions found, maybe quick formatted or never partitioned.[/]'
    }

    # Samples
    $samples = $Overview.Samples
    $color   = $samples.HasData ? 'yellow' : 'green'
    Write-SpectreHost -Message "[$color]$($samples.NonZeroCount) of $($samples.SampleCount) sampled blocks hold data.[/]"

    # Signatures
    if ($Overview.Signatures.Hits.Count -GT 0) {
        Write-SpectreHost -Message "File headers in $(Format-TabulaRasaSize -Bytes $Overview.Signatures.BytesScanned) of samples (estimate, run a deep scan for all):"
        $Overview.Signatures.Hits
        | ForEach-Object { New-SpectreChartItem -Label (Get-SpectreEscapedText -Text $_.Type) -Value $_.Count -Color Orange1 }
        | Format-SpectreBarChart
        | Out-SpectreHost
    }
    else {
        Write-SpectreHost -Message '[green]No file headers found in the samples.[/]'
    }

    Read-SpectrePause
}
