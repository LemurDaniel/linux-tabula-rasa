function Show-TabulaRasaDeepScan {
    <#
    .SYNOPSIS
        Runs the deep signature scan over a whole disk with a progress bar and charts the result.

    .DESCRIPTION
        Reads every byte of the disk (Find-TabulaRasaFileSignature -Mode Deep), which takes as long
        as reading the disk once. Asks before it starts, Ctrl+C stops it.

    .EXAMPLE
        PS> Show-TabulaRasaDeepScan -Disk (Get-TabulaRasaDisk | Select-Object -First 1)
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

    $question = Get-SpectreEscapedText -Text "Read all $(Format-TabulaRasaSize -Bytes $Disk.SizeBytes) of $($Disk.Path)? This takes as long as reading the disk once."
    if (-NOT (Read-SpectreConfirm -Message $question -DefaultAnswer 'y')) {
        return
    }

    $Result = Invoke-SpectreCommandWithProgress -ScriptBlock {
        param (
            [Spectre.Console.ProgressContext] $Context
        )
        $task = $Context.AddTask('Deep scan')
        Find-TabulaRasaFileSignature -Path $Disk.Path -SizeBytes $Disk.SizeBytes -Mode Deep -OnProgress {
            param ($Percent, $Hits)
            $task.Value = $Percent
            $task.Description = "Deep scan, $(@($Hits | Measure-Object -Property Count -Sum).Sum) headers"
        }
        $task.Value = 100
    }

    if ($Result.Hits.Count -EQ 0) {
        Write-SpectreHost -Message "[green]No file headers found in $(Format-TabulaRasaSize -Bytes $Result.BytesScanned).[/]"
        Read-SpectrePause
        return
    }

    Write-SpectreHost -Message "[yellow]File headers found in $(Format-TabulaRasaSize -Bytes $Result.BytesScanned):[/]"
    $Result.Hits
    | ForEach-Object { New-SpectreChartItem -Label (Get-SpectreEscapedText -Text $_.Type) -Value $_.Count -Color Orange1 }
    | Format-SpectreBarChart
    | Out-SpectreHost

    Read-SpectrePause
}
