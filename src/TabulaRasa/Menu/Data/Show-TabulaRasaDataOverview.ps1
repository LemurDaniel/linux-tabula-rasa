# NOTE:
#   Requires: PwshSpectreConsole, an interactive console, Linux and root to read the disk.
#
#   Show-TabulaRasaDataOverview -Disk (Get-TabulaRasaDisk | Select-Object -First 1)

#
#   Chapters:
#     RENDER DATA OVERVIEW   Reads the overview and renders partitions, samples and file headers.
#

function Show-TabulaRasaDataOverview {
    <#
    .SYNOPSIS
        Shows what is on a disk at a glance: partitions with usage, sampled blocks and found file types.

    .DESCRIPTION
        Renders Get-TabulaRasaDataOverview: a partition table, the sampled blocks and a bar chart
        of the file headers found in the samples.

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

    # ===========================================================================
    # ========================   RENDER DATA OVERVIEW   =========================
    # ===========================================================================
    #
    #   1. Overview     Reads partitions, sampled blocks and file headers of the disk.
    #   2. Partitions   Shows the partitions with file system, size and usage.
    #   3. Samples      Shows how many sampled blocks hold data.
    #   4. Signatures   Charts the file headers found in the samples, then waits for a key.
    #

    # ---------------------------------------------------------------------------
    # Overview
    #   Reads partitions, sampled blocks and file headers of the disk.
    # ---------------------------------------------------------------------------

    $Overview =Invoke-SpectreCommandWithStatus -Title "Reading $($Disk.Path) ..." -Spinner Dots -ScriptBlock {
        Get-TabulaRasaDataOverview -Disk $Disk
    }

    # ---------------------------------------------------------------------------
    # Partitions
    #   Shows the partitions with file system, size and usage.
    # ---------------------------------------------------------------------------

    if ($Overview.Partitions.Count -GT 0) {
        $Overview.Partitions
        | Select-Object -Property @(
            @{ Name = 'Partition';  Expression = { $_.Path } }
            @{ Name = 'FileSystem'; Expression = { [System.String]::IsNullOrEmpty($_.FileSystem) ? 'none' : $_.FileSystem } }
            'Label'
            @{ Name = 'Size';       Expression = { Format-TabulaRasaSize -Bytes $_.SizeBytes } }
            @{ Name = 'Used';       Expression = { $null -EQ $_.UsedBytes ? $_.State : (Format-TabulaRasaSize -Bytes $_.UsedBytes) } }
        )
        | Format-SpectreTable -Title 'Partitions' -Border Rounded
        | Out-SpectreHost
    }
    else {
        Write-SpectreHost -Message '[yellow]No partitions found, maybe quick formatted or never partitioned.[/]'
    }

    # ---------------------------------------------------------------------------
    # Samples
    #   Shows how many sampled blocks hold data.
    # ---------------------------------------------------------------------------

    $samples = $Overview.Samples
    $color   = $samples.HasData ? 'yellow' : 'green'
    Write-SpectreHost -Message "[$color]$($samples.NonZeroCount) of $($samples.SampleCount) sampled blocks hold data.[/]"

    # ---------------------------------------------------------------------------
    # Signatures
    #   Charts the file headers found in the samples, then waits for a key.
    # ---------------------------------------------------------------------------

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
