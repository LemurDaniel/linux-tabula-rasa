# NOTE:
#   Requires: PwshSpectreConsole, an interactive console, Linux and root for the data views and the wipe.
#
#   Show-TabulaRasaDiskMenu -Disk (Get-TabulaRasaDisk | Select-Object -First 1)

function Show-TabulaRasaDiskMenu {
    <#
    .SYNOPSIS
        Shows the actions for one disk: the three data views and the wipe.

    .DESCRIPTION
        > Overview        Partitions, sampled blocks and a quick signature estimate (stage 1).
        > Browse files    Mounts a partition read-only and walks its folders (stage 1).
        > Deleted files   Files the file system marks deleted but still holds (stage 2).
        > Deep scan       Counts file headers over the whole disk (stage 3).
        > Wipe            Opens Show-TabulaRasaWipeDialog.
        Returns to the disk list on 'Back' or after a wipe.

    .EXAMPLE
        PS> Show-TabulaRasaDiskMenu -Disk (Get-TabulaRasaDisk | Select-Object -First 1)
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

    $Choices = @(
        [PSCustomObject]@{ Label = 'Overview';       Action = 'Overview' }
        [PSCustomObject]@{ Label = 'Browse files';   Action = 'Browse' }
        [PSCustomObject]@{ Label = 'Deleted files';  Action = 'Deleted' }
        [PSCustomObject]@{ Label = 'Deep scan';      Action = 'DeepScan' }
        [PSCustomObject]@{ Label = '[red]Wipe[/]';   Action = 'Wipe' }
        [PSCustomObject]@{ Label = 'Back';           Action = 'Back' }
    )

    while ($true) {
        Clear-Host
        Write-SpectreRule -Title (Get-SpectreEscapedText -Text "$($Disk.Path)  $($Disk.Kind)  $(Format-TabulaRasaSize -Bytes $Disk.SizeBytes)  $($Disk.Model)") -Color Orange1

        $Choice = Read-SpectreSelection -Message 'What do you want to do?' -Choices $Choices -ChoiceLabelProperty Label
        Write-Verbose "[Show-TabulaRasaDiskMenu] '$($Disk.Path)': selected action '$($Choice.Action)'."

        switch ($Choice.Action) {
            'Overview' { Show-TabulaRasaDataOverview -Disk $Disk }
            'Browse'   { Show-TabulaRasaFileBrowser -Disk $Disk }
            'Deleted'  { Show-TabulaRasaDeletedFile -Disk $Disk }
            'DeepScan' { Show-TabulaRasaDeepScan -Disk $Disk }
            'Wipe'     { Show-TabulaRasaWipeDialog -Disk $Disk; return }
            'Back'     { return }
        }
    }
}
