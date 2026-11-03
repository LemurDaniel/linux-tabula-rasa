# NOTE:
#   Requires: PwshSpectreConsole, an interactive console, Linux, root and sleuthkit (fls).
#
#   Show-TabulaRasaDeletedFile -Disk (Get-TabulaRasaDisk | Select-Object -First 1)

function Show-TabulaRasaDeletedFile {
    <#
    .SYNOPSIS
        Lists the files a partition marks deleted but still holds.

    .DESCRIPTION
        Uses Get-TabulaRasaDeletedFile (sleuthkit), the partition is not mounted.
        Shows the total count, the summed size and the first files as a table.

    .EXAMPLE
        PS> Show-TabulaRasaDeletedFile -Disk (Get-TabulaRasaDisk | Select-Object -First 1)
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

    $TABLE_ROWS = 50

    $Partition = Select-TabulaRasaPartition -Disk $Disk
    if ($null -EQ $Partition) {
        return
    }

    $Result = Invoke-SpectreCommandWithStatus -Title "Reading the file system of $($Partition.Path) ..." -Spinner Dots -ScriptBlock {
        Get-TabulaRasaDeletedFile -Path $Partition.Path
    }

    if (-NOT $Result.IsSupported) {
        Write-SpectreHost -Message '[yellow]The file system cannot be read (quick formatted, encrypted or unknown). The deep scan still finds file headers.[/]'
        Read-SpectrePause
        return
    }
    if ($Result.TotalCount -EQ 0) {
        Write-SpectreHost -Message '[green]No deleted files found in the file system.[/]'
        Read-SpectrePause
        return
    }

    $TotalBytes = ($Result.Files | Measure-Object -Property SizeBytes -Sum).Sum
    Write-SpectreHost -Message "[yellow]$($Result.TotalCount) deleted files, the first $($Result.Files.Count) hold $(Format-TabulaRasaSize -Bytes $TotalBytes).[/]"

    $Result.Files
    | Select-Object -First $TABLE_ROWS
    | Select-Object -Property Path, @{ Name = 'Size'; Expression = { Format-TabulaRasaSize -Bytes $_.SizeBytes } }, LastWriteTime
    | Format-SpectreTable -Title "Deleted files (first $TABLE_ROWS)" -Border Rounded
    | Out-SpectreHost

    Read-SpectrePause
}
