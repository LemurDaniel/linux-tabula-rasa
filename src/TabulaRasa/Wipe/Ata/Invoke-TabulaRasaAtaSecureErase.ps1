# NOTE:
#   Requires: Linux, root, hdparm, rtcwake (util-linux) to unfreeze a frozen drive.
#
#   Invoke-TabulaRasaAtaSecureErase -Path /dev/sda

#
#   Chapters:
#     ERASE THE DRIVE   Checks and unfreezes the security state, sets a password and erases.
#

function Invoke-TabulaRasaAtaSecureErase {
    <#
    .SYNOPSIS
        Erases a SATA SSD with the drive's own ATA Secure Erase command.

    .DESCRIPTION
        The controller erases every block itself, also spare and remapped ones overwriting cannot reach.

        1. Status     hdparm -I: security must be supported, not enabled and not locked.
        2. Unfreeze   Most BIOSes freeze the security state at boot. A short suspend to RAM
                      (rtcwake) wakes the drive unfrozen on most machines, tried once.
        3. Password   ATA only erases a drive with a user password, a temporary one is set.
        4. Erase      Enhanced erase when supported (also the spare area), else normal erase.
                      Blocks until the drive is done, the progress is estimated from its own estimate.
        5. Check      The drive clears the password itself after the erase.

        When anything fails after step 3, the password is removed again: otherwise the drive
        would stay locked with a password nobody knows.

    .EXAMPLE
        PS> Invoke-TabulaRasaAtaSecureErase -Path /dev/sda -OnProgress { param ($Percent) $Percent }
    #>

    # Called by Invoke-TabulaRasaWipe after its confirmation. -WhatIf has no meaning here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    # The temporary ATA password is no secret: it only exists for the seconds of the erase.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The device path, e.g. '/dev/sda'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Path,

        <#
        [Optional]
        Called with the estimated percentage about once a second.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.Management.Automation.ScriptBlock]
        $OnProgress = $null
    )

    $PASSWORD        = 'TabulaRasa'
    $SUSPEND_SECONDS = 5

    $getSecurity = {
        $text = hdparm -I $Path 2>&1
        if ($LASTEXITCODE -NE 0) {
            throw [System.InvalidOperationException]::new("hdparm must identify '$Path', got exit code $LASTEXITCODE.")
        }
        return $text | ConvertFrom-TabulaRasaHdparmSecurity
    }
    $disablePassword = {
        $null = hdparm --user-master u --security-disable $PASSWORD $Path 2>&1
        Write-Verbose "[Invoke-TabulaRasaAtaSecureErase] Removed the temporary password from '$Path' (exit code $LASTEXITCODE)."
    }

    # ===========================================================================
    # ===========================   ERASE THE DRIVE   ===========================
    # ===========================================================================
    #
    #   1. Status            Security must be supported, not enabled and not locked.
    #   2. Unfreeze          A short suspend unfreezes a frozen drive, tried once.
    #   3. Password          Sets the temporary user password ATA needs for the erase.
    #   4. Erase and check   Erases and checks, the password is removed again on failure.
    #

    # ---------------------------------------------------------------------------
    # Status
    #   Security must be supported, not enabled and not locked.
    # ---------------------------------------------------------------------------

    $Security = & $getSecurity
    if (-NOT $Security.IsSupported) {
        throw [System.NotSupportedException]::new("'$Path' must support ATA Security, this drive does not. Use Overwrite instead.")
    }
    if ($Security.IsEnabled -OR $Security.IsLocked) {
        throw [System.InvalidOperationException]::new("'$Path' must have no ATA password, it has one set by someone else (enabled: $($Security.IsEnabled), locked: $($Security.IsLocked)).")
    }

    # ---------------------------------------------------------------------------
    # Unfreeze
    #   A short suspend unfreezes a frozen drive, tried once.
    # ---------------------------------------------------------------------------

    if ($Security.IsFrozen) {
        Write-Verbose "[Invoke-TabulaRasaAtaSecureErase] '$Path' is frozen -> suspending for $SUSPEND_SECONDS s to unfreeze it."
        rtcwake --mode mem --seconds $SUSPEND_SECONDS
        Write-Verbose "[Invoke-TabulaRasaAtaSecureErase] rtcwake returned $LASTEXITCODE, the state is read again."
        Start-Sleep -Seconds $SUSPEND_SECONDS
        $Security = & $getSecurity
        if ($Security.IsFrozen) {
            throw [System.InvalidOperationException]::new("'$Path' must not be frozen, it still is after a suspend. Unplug the drive's SATA cable and plug it in again while the system runs, or use another port.")
        }
    }

    # ---------------------------------------------------------------------------
    # Password
    #   Sets the temporary user password ATA needs for the erase.
    # ---------------------------------------------------------------------------

    hdparm --user-master u --security-set-pass $PASSWORD $Path *> $null
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("hdparm must set the temporary password on '$Path', got exit code $LASTEXITCODE.")
    }

    # ---------------------------------------------------------------------------
    # Erase and check
    #   Erases and checks, the password is removed again on failure.
    # ---------------------------------------------------------------------------

    $isEnhanced = $Security.IsEnhancedSupported
    $minutes    = $isEnhanced ? $Security.EnhancedEraseMinutes : $Security.EraseMinutes
    $EraseCall  = @{
        FilePath         = 'hdparm'
        ArgumentList     = @('--user-master', 'u', ($isEnhanced ? '--security-erase-enhanced' : '--security-erase'), $PASSWORD, $Path)
        EstimatedSeconds = $null -EQ $minutes ? 0 : $minutes * 60
        OnProgress       = $OnProgress
    }

    try {
        $Result = Wait-TabulaRasaProcess @EraseCall
        if ($Result.ExitCode -NE 0) {
            throw [System.InvalidOperationException]::new("hdparm must erase '$Path', got exit code $($Result.ExitCode): $($Result.Error.Trim())")
        }

        # Check: a successful erase leaves security disabled.
        if ((& $getSecurity).IsEnabled) {
            throw [System.InvalidOperationException]::new("'$Path' reported the erase as done, but its password is still set. The erase may not have happened.")
        }
    }
    catch {
        & $disablePassword
        throw
    }

    return [PSCustomObject]@{
        Detail  = $isEnhanced ? 'ATA enhanced secure erase' : 'ATA secure erase'
        Seconds = $Result.Seconds
    }
}
