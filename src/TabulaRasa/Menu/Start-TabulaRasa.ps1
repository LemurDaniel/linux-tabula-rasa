function Start-TabulaRasa {
    <#
    .SYNOPSIS
        Starts the interactive text menu of the live system.

    .DESCRIPTION
        Runs in a loop until the user powers off or reboots:
        lists every disk except the boot stick and opens Show-TabulaRasaDiskMenu for the picked one.

        Started by root's .bash_profile on tty1. Alt+F2 opens a plain root shell next to it.

    .EXAMPLE
        PS> Import-Module /opt/tabula-rasa/TabulaRasa
        PS> Start-TabulaRasa
    #>

    # The menu is interactive, every destructive step has its own confirmation. -WhatIf has no meaning here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param ()

    $TITLE = 'Tabula Rasa'

    :MENU while ($true) {
        Clear-Host
        Write-SpectreFigletText -Text $TITLE -Color Orange1
        Write-SpectreRule -Title 'secure disk wipe' -Color Grey

        # Disks
        $Disks = @(Invoke-SpectreCommandWithStatus -Title 'Detecting disks ...' -Spinner Dots -ScriptBlock {
            Get-TabulaRasaDisk
        })

        if ($Disks.Count -GT 0) {
            $Disks
            | Select-Object -Property Path, Kind, @{ Name = 'Size'; Expression = { Format-TabulaRasaSize -Bytes $_.SizeBytes } }, Model, Serial
            | Format-SpectreTable -Title 'Disks' -Border Rounded
            | Out-SpectreHost
        }
        else {
            Write-SpectreHost -Message '[yellow]No disks found. Plug one in and refresh.[/]'
        }

        # Selection
        $Choices = @(
            foreach ($disk in $Disks) {
                [PSCustomObject]@{
                    Label  = Get-SpectreEscapedText -Text "$($disk.Path)  $($disk.Kind)  $(Format-TabulaRasaSize -Bytes $disk.SizeBytes)  $($disk.Model)"
                    Action = 'Disk'
                    Disk   = $disk
                }
            }
            [PSCustomObject]@{ Label = 'Refresh';   Action = 'Refresh';  Disk = $null }
            [PSCustomObject]@{ Label = 'Reboot';    Action = 'Reboot';   Disk = $null }
            [PSCustomObject]@{ Label = 'Power off'; Action = 'PowerOff'; Disk = $null }
        )
        $Choice = Read-SpectreSelection -Message 'Select a disk' -Choices $Choices -ChoiceLabelProperty Label

        Write-Verbose "[Start-TabulaRasa] Selected action '$($Choice.Action)'."
        switch ($Choice.Action) {
            'Refresh'  { continue MENU }
            'Reboot'   { systemctl reboot; return }
            'PowerOff' { systemctl poweroff; return }
            'Disk'     { Show-TabulaRasaDiskMenu -Disk $Choice.Disk }
        }
    }
}
