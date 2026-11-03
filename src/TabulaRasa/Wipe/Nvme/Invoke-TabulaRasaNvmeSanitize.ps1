# NOTE:
#   Requires: Linux, root, nvme-cli.
#
#   Invoke-TabulaRasaNvmeSanitize -Path /dev/nvme0n1

#
#   Chapters:
#     SANITIZE THE DRIVE   Validates the namespace, sanitizes, or formats as fallback.
#

function Invoke-TabulaRasaNvmeSanitize {
    <#
    .SYNOPSIS
        Erases an NVMe drive with the controller's own Sanitize command, or Format as fallback.

    .DESCRIPTION
        Sanitize erases the whole controller: every namespace, the caches and the spare blocks.
        So it is refused when the controller has more than one namespace, the others are no
        disks the user picked.

        Order of precedence:
        - Sanitize Crypto Erase   destroys the media key, instant
        - Sanitize Block Erase    erases every block
        - Sanitize Overwrite      writes every block, slow
        - Format with Secure Erase, crypto when supported, else user data erase
          (for drives without Sanitize, older or cheap ones)

        Sanitize runs in the background on the drive, its log is polled for the progress.

    .EXAMPLE
        PS> Invoke-TabulaRasaNvmeSanitize -Path /dev/nvme0n1 -OnProgress { param ($Percent) $Percent }
    #>

    # Called by Invoke-TabulaRasaWipe after its confirmation. -WhatIf has no meaning here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The device path of the namespace, e.g. '/dev/nvme0n1'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Path,

        <#
        [Optional]
        Called with the percentage of the sanitize whenever it is polled.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.Management.Automation.ScriptBlock]
        $OnProgress = $null
    )

    $POLL_SECONDS = 2

    # ===========================================================================
    # =========================   SANITIZE THE DRIVE   ==========================
    # ===========================================================================
    #
    #   1. Validations   A namespace alone on its controller, then the controller capabilities.
    #   2. Sanitize      The strongest supported sanitize action, its log polled for progress.
    #   3. Format        Format with Secure Erase, for drives without Sanitize.
    #

    # ---------------------------------------------------------------------------
    # Validations
    #   A namespace alone on its controller, then the controller capabilities.
    # ---------------------------------------------------------------------------

    # '/dev/nvme0n1' => controller '/dev/nvme0'
    if ($Path -NOTMATCH '^(/dev/(nvme\d+))n\d+$') {
        throw [System.ArgumentException]::new("Path must be an NVMe namespace like '/dev/nvme0n1', got '$Path'.")
    }
    $Controller     = $Matches[1]
    $ControllerName = $Matches[2]

    # Namespaces show up as nvme0n1, nvme0n2 (or nvme0c0n1 with multipath) below the controller.
    $namespaceCount = @(Get-ChildItem -Path "/sys/class/nvme/$ControllerName" -Directory
        | Where-Object -Property Name -MATCH -Value "^$($ControllerName)(c\d+)?n\d+$").Count
    if ($namespaceCount -GT 1) {
        throw [System.InvalidOperationException]::new("'$Controller' must have exactly one namespace, it has $namespaceCount. Sanitize would erase all of them.")
    }

    $ControllerJson = nvme id-ctrl $Controller --output-format=json
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("nvme must identify '$Controller', got exit code $LASTEXITCODE.")
    }
    $Capability = $ControllerJson | ConvertFrom-TabulaRasaNvmeController

    # ---------------------------------------------------------------------------
    # Sanitize
    #   The strongest supported sanitize action, its log polled for progress.
    # ---------------------------------------------------------------------------

    $sanitizeAction = $null
    if ($Capability.IsCryptoErase) {
        $sanitizeAction = @{ Code = 4; Detail = 'NVMe sanitize, crypto erase' }
    }
    elseif ($Capability.IsBlockErase) {
        $sanitizeAction = @{ Code = 2; Detail = 'NVMe sanitize, block erase' }
    }
    elseif ($Capability.IsOverwrite) {
        $sanitizeAction = @{ Code = 3; Detail = 'NVMe sanitize, overwrite' }
    }

    if ($null -NE $sanitizeAction) {
        Write-Verbose "[Invoke-TabulaRasaNvmeSanitize] Starting '$($sanitizeAction.Detail)' on '$Controller'."
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        nvme sanitize $Controller "--sanact=$($sanitizeAction.Code)"
        if ($LASTEXITCODE -NE 0) {
            throw [System.InvalidOperationException]::new("nvme must start the sanitize on '$Controller', got exit code $LASTEXITCODE.")
        }

        do {
            Start-Sleep -Seconds $POLL_SECONDS
            $logJson = nvme sanitize-log $Controller --output-format=json
            if ($LASTEXITCODE -NE 0) {
                throw [System.InvalidOperationException]::new("nvme must read the sanitize log of '$Controller', got exit code $LASTEXITCODE.")
            }
            $log = $logJson | ConvertFrom-TabulaRasaNvmeSanitizeLog
            if ($null -NE $OnProgress) {
                $null = & $OnProgress $log.Percent
            }
        } while ($log.Status -EQ 'InProgress')

        if ($log.Status -NE 'Success') {
            throw [System.InvalidOperationException]::new("The sanitize of '$Controller' must succeed, the drive reports '$($log.Status)'.")
        }

        # The namespace comes back fresh, the kernel reads it again.
        nvme ns-rescan $Controller
        return [PSCustomObject]@{
            Detail  = $sanitizeAction.Detail
            Seconds = [System.Math]::Round($stopwatch.Elapsed.TotalSeconds)
        }
    }

    # ---------------------------------------------------------------------------
    # Format
    #   Format with Secure Erase, for drives without Sanitize.
    # ---------------------------------------------------------------------------

    $secureErase = $Capability.IsFormatCryptoErase ? 2 : 1
    $detail      = $secureErase -EQ 2 ? 'NVMe format, crypto erase' : 'NVMe format, user data erase'
    Write-Verbose "[Invoke-TabulaRasaNvmeSanitize] No sanitize on '$Controller' -> '$detail'."

    $Result = Wait-TabulaRasaProcess -FilePath 'nvme' -ArgumentList @('format', $Path, "--ses=$secureErase", '--force')
    if ($Result.ExitCode -NE 0) {
        throw [System.InvalidOperationException]::new("nvme must format '$Path', got exit code $($Result.ExitCode): $($Result.Error.Trim())")
    }

    return [PSCustomObject]@{
        Detail  = $detail
        Seconds = $Result.Seconds
    }
}
