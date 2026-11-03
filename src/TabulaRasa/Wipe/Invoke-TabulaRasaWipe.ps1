# NOTE:
#   Requires: Linux, root, blockdev and the tool of the method (hdparm and rtcwake, or nvme-cli).
#
#   Invoke-TabulaRasaWipe -Path /dev/sdb -Method Overwrite -WhatIf

#
#   Chapters:
#     WIPE THE DISK   Prepares, wipes with the chosen method, forgets the old table and checks.
#

function Invoke-TabulaRasaWipe {
    <#
    .SYNOPSIS
        Wipes a disk with the given method and checks the result.

    .DESCRIPTION
        1. Prepare   Initialize-TabulaRasaWipeTarget: never the boot stick, nothing mounted.
        2. Wipe      Overwrite         Invoke-TabulaRasaOverwrite, zeros over the full size.
                     AtaSecureErase    Invoke-TabulaRasaAtaSecureErase, the drive erases itself.
                     NvmeSanitize      Invoke-TabulaRasaNvmeSanitize, the controller erases itself.
        3. Forget    The kernel drops the cached partition table of the old content.
        4. Check     Test-TabulaRasaDiskData samples the disk again. After Overwrite every sample
                     must be zero, else the wipe failed. After an erase the drive may return zeros,
                     0xFF or random bytes (crypto erase), so non-zero samples are reported, not fatal.

        The caller confirms the disk first (serial or replug), this function only adds -WhatIf.

    .EXAMPLE
        PS> Invoke-TabulaRasaWipe -Path /dev/sdb -Method Overwrite -WhatIf

    .EXAMPLE
        PS> Invoke-TabulaRasaWipe -Path /dev/sdb -Method Overwrite -Confirm:$false -OnProgress { param ($Percent) Write-Host "$Percent %" }
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The device path, e.g. '/dev/sdb'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Path,

        <#
        [Required]
        The wipe method from Resolve-TabulaRasaWipeMethod.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateSet('Overwrite', 'AtaSecureErase', 'NvmeSanitize')]
        [System.String]
        $Method,

        <#
        [Optional]
        Called with the percentage of the wipe (estimated for ATA Secure Erase).
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.Management.Automation.ScriptBlock]
        $OnProgress = $null
    )

    # ===========================================================================
    # ============================   WIPE THE DISK   ============================
    # ===========================================================================
    #
    #   1. Prepare   Never the boot stick, nothing mounted, reads the size.
    #   2. Wipe      Runs the chosen method: Overwrite, AtaSecureErase or NvmeSanitize.
    #   3. Forget    The kernel drops the cached partition table of the old content.
    #   4. Check     Samples the disk again, after Overwrite every sample must be zero.
    #

    if (-NOT $PSCmdlet.ShouldProcess($Path, "Wipe with '$Method'")) {
        return
    }

    # ---------------------------------------------------------------------------
    # Prepare
    #   Never the boot stick, nothing mounted, reads the size.
    # ---------------------------------------------------------------------------

    Initialize-TabulaRasaWipeTarget -Path $Path
    $SizeBytes = [System.Int64] (blockdev --getsize64 $Path)
    if ($LASTEXITCODE -NE 0 -OR $SizeBytes -LE 0) {
        throw [System.InvalidOperationException]::new("blockdev must read the size of '$Path', got exit code $LASTEXITCODE.")
    }
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    # ---------------------------------------------------------------------------
    # Wipe
    #   Runs the chosen method: Overwrite, AtaSecureErase or NvmeSanitize.
    # ---------------------------------------------------------------------------

    Write-Verbose "[Invoke-TabulaRasaWipe] Wiping '$Path' ($SizeBytes bytes) with '$Method'."
    $Wiped = switch ($Method) {
        'Overwrite'      { Invoke-TabulaRasaOverwrite -Path $Path -SizeBytes $SizeBytes -OnProgress $OnProgress }
        'AtaSecureErase' { Invoke-TabulaRasaAtaSecureErase -Path $Path -OnProgress $OnProgress }
        'NvmeSanitize'   { Invoke-TabulaRasaNvmeSanitize -Path $Path -OnProgress $OnProgress }
    }

    # ---------------------------------------------------------------------------
    # Forget
    #   The kernel drops the cached partition table of the old content.
    # ---------------------------------------------------------------------------

    # A busy disk keeps its old table until the next plug-in, that is only a warning.
    blockdev --flushbufs $Path
    blockdev --rereadpt $Path 2>$null
    if ($LASTEXITCODE -NE 0) {
        Write-Warning "[Invoke-TabulaRasaWipe] The kernel could not reread the partition table of '$Path' (exit code $LASTEXITCODE), it shows the old partitions until the disk is plugged in again."
    }

    # ---------------------------------------------------------------------------
    # Check
    #   Samples the disk again, after Overwrite every sample must be zero.
    # ---------------------------------------------------------------------------

    $Check = Test-TabulaRasaDiskData -Path $Path -SizeBytes $SizeBytes
    if ($Method -EQ 'Overwrite' -AND $Check.HasData) {
        throw [System.InvalidOperationException]::new("'$Path' must read back as zeros after the overwrite, but $($Check.NonZeroCount) of $($Check.SampleCount) sampled blocks hold data. The disk may be failing.")
    }

    Write-Verbose "[Invoke-TabulaRasaWipe] '$Path' wiped ($($Wiped.Detail)), $($Check.NonZeroCount) of $($Check.SampleCount) samples not zero."
    return [PSCustomObject]@{
        Path         = $Path
        Method       = $Method
        Detail       = $Wiped.Detail
        Seconds      = [System.Math]::Round($stopwatch.Elapsed.TotalSeconds)
        SampleCount  = $Check.SampleCount
        NonZeroCount = $Check.NonZeroCount
        IsAllZero    = -NOT $Check.HasData
    }
}
