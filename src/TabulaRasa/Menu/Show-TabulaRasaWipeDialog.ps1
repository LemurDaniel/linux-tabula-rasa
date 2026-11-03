function Show-TabulaRasaWipeDialog {
    <#
    .SYNOPSIS
        Confirms and runs the wipe of one disk.

    .DESCRIPTION
        Shows the wipe plan, then confirms the disk the way Resolve-TabulaRasaWipeMethod says:
        > Serial   The user types the serial from the label (the device path when there is none).
        > Replug   The user unplugs the device and plugs it in again. The device that shows up
                   is the one wiped, it may come back under a new name (sdc -> sdd).

    .EXAMPLE
        PS> Show-TabulaRasaWipeDialog -Disk (Get-TabulaRasaDisk | Select-Object -First 1)
    #>

    # The dialog is interactive, the serial or the replug is its confirmation. -WhatIf has no meaning here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
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

    $REPLUG_POLL_MS        = 1000
    $REPLUG_TIMEOUT_SECONDS = 120

    $WipeInfo = Resolve-TabulaRasaWipeMethod -Kind $Disk.Kind

    # Plan: a Text renderable prints model names like '[ATA]' as they are, a string would be parsed as markup.
    $Summary = @(
        "Disk:          $($Disk.Path)  $($Disk.Model)  $($Disk.Serial)"
        "Kind:          $($Disk.Kind)"
        "Method:        $($WipeInfo.Method)"
        "Confirmation:  $($WipeInfo.Confirmation)"
    ) -join "`n"
    Format-SpectrePanel -Data ([Spectre.Console.Text]::new($Summary)) -Header 'Wipe plan' -Border Rounded -Color Red
    | Out-SpectreHost

    if ($null -NE $WipeInfo.Warning) {
        Write-SpectreHost -Message "[yellow]$(Get-SpectreEscapedText -Text $WipeInfo.Warning)[/]"
    }

    # When the confirmation is Serial
    if ($WipeInfo.Confirmation -EQ 'Serial') {
        $ConfirmToken = [System.String]::IsNullOrEmpty($Disk.Serial) ? $Disk.Path : $Disk.Serial
        $answer       = Read-SpectreText -Message "Type [red]$(Get-SpectreEscapedText -Text $ConfirmToken)[/] to wipe this disk, anything else cancels" -AllowEmpty

        if ($answer -CNE $ConfirmToken) {
            Write-Verbose "[Show-TabulaRasaWipeDialog] Serial did not match -> nothing wiped."
            Write-SpectreHost -Message '[grey]Cancelled, nothing was wiped.[/]'
            Read-SpectrePause
            return
        }
        $Target = $Disk
    }

    # When the confirmation is Replug
    if ($WipeInfo.Confirmation -EQ 'Replug') {
        $deadline = [System.DateTime]::Now.AddSeconds($REPLUG_TIMEOUT_SECONDS)

        # Unplug: wait until the selected device is gone.
        $Remaining = Invoke-SpectreCommandWithStatus -Title "Unplug $(Get-SpectreEscapedText -Text $Disk.Model) now ..." -Spinner Dots -ScriptBlock {
            do {
                Start-Sleep -Milliseconds $REPLUG_POLL_MS
                $current = @(Get-TabulaRasaDisk)
            } while ($current.Name -CONTAINS $Disk.Name -AND [System.DateTime]::Now -LT $deadline)
            return , $current
        }
        if (@($Remaining).Name -CONTAINS $Disk.Name) {
            Write-SpectreHost -Message '[grey]Not unplugged in time, nothing was wiped.[/]'
            Read-SpectrePause
            return
        }

        # Plug in: wait for exactly one new device.
        $Added = Invoke-SpectreCommandWithStatus -Title 'Plug it in again ...' -Spinner Dots -ScriptBlock {
            do {
                Start-Sleep -Milliseconds $REPLUG_POLL_MS
                $added = @((Compare-TabulaRasaDiskSet -Before @($Remaining) -After @(Get-TabulaRasaDisk)).Added)
            } while ($added.Count -EQ 0 -AND [System.DateTime]::Now -LT $deadline)
            return , $added
        }
        if (@($Added).Count -NE 1) {
            Write-SpectreHost -Message "[grey]Expected one device to come back, got $(@($Added).Count). Nothing was wiped.[/]"
            Read-SpectrePause
            return
        }

        $Target = @($Added)[0]
        $prompt = Get-SpectreEscapedText -Text "Wipe $($Target.Path)  $($Target.Model)  $(Format-TabulaRasaSize -Bytes $Target.SizeBytes)?"
        if (-NOT (Read-SpectreConfirm -Message "[red]$prompt[/]" -DefaultAnswer 'n')) {
            Write-SpectreHost -Message '[grey]Cancelled, nothing was wiped.[/]'
            Read-SpectrePause
            return
        }
    }

    # Wipe
    $TargetInfo = Resolve-TabulaRasaWipeMethod -Kind $Target.Kind
    try {
        Invoke-TabulaRasaWipe -Path $Target.Path -Method $TargetInfo.Method -Confirm:$false
        Write-SpectreHost -Message "[green]$(Get-SpectreEscapedText -Text $Target.Path) wiped.[/]"
    }
    catch [System.NotImplementedException] {
        # Handled: the scaffold has no wipe methods yet, the menu stays usable.
        Write-SpectreHost -Message "[red]$(Get-SpectreEscapedText -Text $_.Exception.Message)[/]"
    }
    Read-SpectrePause
}
