# NOTE:
#   Requires: PwshSpectreConsole, an interactive console, Linux and root for the wipe.
#
#   Show-TabulaRasaWipeDialog -Disk (Get-TabulaRasaDisk | Select-Object -First 1)

#
#   Chapters:
#     CONFIRM AND WIPE DISK   Shows the plan, confirms the disk, wipes it and checks the result.
#

function Show-TabulaRasaWipeDialog {
    <#
    .SYNOPSIS
        Confirms and runs the wipe of one disk.

    .DESCRIPTION
        Shows the wipe plan, then confirms the disk the way Resolve-TabulaRasaWipeMethod says:
        > Serial   Model, size and serial are shown, the user confirms with yes (default no).
                   Nobody has to open the case to read the label. Right before the wipe the disk
                   is looked up again: a different disk under the same name cancels the wipe.
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

    # ===========================================================================
    # ========================   CONFIRM AND WIPE DISK   ========================
    # ===========================================================================
    #
    #   1. Plan                  Shows the wipe plan and the warning of the method.
    #   2. Serial confirmation   Shows the serial and asks yes or no when the confirmation is Serial.
    #   3. Replug confirmation   Waits for unplug and plug in when the confirmation is Replug.
    #   4. Wipe                  Runs the wipe with a progress bar,
    #                            estimated for ATA Secure Erase, which reports none.
    #   5. Result                Shows the duration and the zero check of the sampled blocks.
    #

    # ---------------------------------------------------------------------------
    # Plan
    #   Shows the wipe plan and the warning of the method.
    # ---------------------------------------------------------------------------

    $WipeInfo = Resolve-TabulaRasaWipeMethod -Kind $Disk.Kind

    # A Text renderable prints model names like '[ATA]' as they are, a string would be parsed as markup.
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

    # ---------------------------------------------------------------------------
    # Serial confirmation
    #   Shows the serial and asks yes or no when the confirmation is Serial.
    # ---------------------------------------------------------------------------

    if ($WipeInfo.Confirmation -EQ 'Serial') {
        $serial = [System.String]::IsNullOrEmpty($Disk.Serial) ? 'no serial' : $Disk.Serial
        $prompt = Get-SpectreEscapedText -Text "Wipe $($Disk.Model) ($(Format-TabulaRasaSize -Bytes $Disk.SizeBytes), serial $serial) for good?"
        if (-NOT (Read-SpectreConfirm -Message "[red]$prompt[/]" -DefaultAnswer 'n')) {
            Write-SpectreHost -Message '[grey]Cancelled, nothing was wiped.[/]'
            Read-SpectrePause
            return
        }

        # The disk may have been swapped while the question was open: same name, other serial.
        $current = Get-TabulaRasaDisk | Where-Object -Property Name -CEQ -Value $Disk.Name
        if ($null -EQ $current -OR $current.Serial -CNE $Disk.Serial) {
            Write-Verbose "[Show-TabulaRasaWipeDialog] '$($Disk.Name)' is gone or now another disk -> nothing wiped."
            Write-SpectreHost -Message '[yellow]The disk changed while the question was open, nothing was wiped.[/]'
            Read-SpectrePause
            return
        }
        $Target = $current
    }

    # ---------------------------------------------------------------------------
    # Replug confirmation
    #   Waits for unplug and plug in when the confirmation is Replug.
    # ---------------------------------------------------------------------------

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
        # The status command may hand back $null for an empty list, @() would count it as one disk.
        $Remaining = @($Remaining | Where-Object { $null -NE $_ })
        if ($Remaining.Name -CONTAINS $Disk.Name) {
            Write-SpectreHost -Message '[grey]Not unplugged in time, nothing was wiped.[/]'
            Read-SpectrePause
            return
        }

        # Plug in: wait for exactly one new device.
        $Added = Invoke-SpectreCommandWithStatus -Title 'Plug it in again ...' -Spinner Dots -ScriptBlock {
            do {
                Start-Sleep -Milliseconds $REPLUG_POLL_MS
                $added = @((Compare-TabulaRasaDiskSet -Before $Remaining -After @(Get-TabulaRasaDisk)).Added)
            } while ($added.Count -EQ 0 -AND [System.DateTime]::Now -LT $deadline)
            return , $added
        }
        $Added = @($Added | Where-Object { $null -NE $_ })
        if ($Added.Count -NE 1) {
            Write-SpectreHost -Message "[grey]Expected one device to come back, got $($Added.Count). Nothing was wiped.[/]"
            Read-SpectrePause
            return
        }

        $Target = $Added[0]
        $prompt = Get-SpectreEscapedText -Text "Wipe $($Target.Path)  $($Target.Model)  $(Format-TabulaRasaSize -Bytes $Target.SizeBytes)?"
        if (-NOT (Read-SpectreConfirm -Message "[red]$prompt[/]" -DefaultAnswer 'n')) {
            Write-SpectreHost -Message '[grey]Cancelled, nothing was wiped.[/]'
            Read-SpectrePause
            return
        }
    }

    # ---------------------------------------------------------------------------
    # Wipe
    #   Runs the wipe with a progress bar,
    #   estimated for ATA Secure Erase, which reports none.
    # ---------------------------------------------------------------------------

    $TargetInfo = Resolve-TabulaRasaWipeMethod -Kind $Target.Kind
    try {
        $Result = Invoke-SpectreCommandWithProgress -ScriptBlock {
            param (
                [Spectre.Console.ProgressContext] $Context
            )
            $task = $Context.AddTask("Wiping $($Target.Path) ($($TargetInfo.Method))")
            Invoke-TabulaRasaWipe -Path $Target.Path -Method $TargetInfo.Method -Confirm:$false -OnProgress {
                param ($Percent)
                $task.Value = $Percent
            }
            $task.Value = 100
        }
    }
    catch [System.InvalidOperationException], [System.NotSupportedException] {
        # Handled: the reason (frozen drive, foreign mount, failing disk) is shown, the menu stays usable.
        Write-SpectreHost -Message "[red]Wipe failed: $(Get-SpectreEscapedText -Text $_.Exception.Message)[/]"
        Read-SpectrePause
        return
    }

    # ---------------------------------------------------------------------------
    # Result
    #   Shows the duration and the zero check of the sampled blocks.
    # ---------------------------------------------------------------------------

    $check =$Result.IsAllZero ? 'all sampled blocks read zero' : "$($Result.NonZeroCount) of $($Result.SampleCount) sampled blocks are not zero (normal after a crypto erase)"
    Write-SpectreHost -Message "[green]$(Get-SpectreEscapedText -Text "$($Target.Path) wiped with $($Result.Detail) in $($Result.Seconds) s.")[/]"
    Write-SpectreHost -Message "[grey]Check: $(Get-SpectreEscapedText -Text $check).[/]"
    Read-SpectrePause
}
