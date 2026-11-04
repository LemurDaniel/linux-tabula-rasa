# NOTE:
#   Requires: write access to the device (root for a block device), or a plain file.
#
#   Invoke-TabulaRasaOverwrite -Path /dev/sdb -SizeBytes 1000204886016

function Invoke-TabulaRasaOverwrite {
    <#
    .SYNOPSIS
        Overwrites a device with zeros from the first to the last byte, one pass.

    .DESCRIPTION
        One pass of zeros is enough for HDDs (NIST SP 800-88 "Clear"), recovering overwritten
        sectors is not possible with today's recording densities. Flushes to the device at the end,
        so the data is on the disk and not only in the page cache when the function returns.
        Works with a plain file too, which is how it is tested.

        OnProgress gets the percentage whenever it changes.

    .EXAMPLE
        PS> Invoke-TabulaRasaOverwrite -Path /dev/sdb -SizeBytes 1000204886016 -OnProgress { param ($Percent) $Percent }
    #>

    # Called by Invoke-TabulaRasaWipe after its confirmation. -WhatIf has no meaning here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
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
        The number of bytes to overwrite, the full size of the device.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateRange(1, [System.Int64]::MaxValue)]
        [System.Int64]
        $SizeBytes,

        <#
        [Optional]
        Called with the percentage whenever it changes.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.Management.Automation.ScriptBlock]
        $OnProgress = $null
    )

    $CHUNK_BYTES = 4MB

    $zeros       = [System.Byte[]]::new($CHUNK_BYTES)
    $written     = [System.Int64] 0
    $lastPercent = -1
    $stopwatch   = [System.Diagnostics.Stopwatch]::StartNew()

    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, 1)
    try {
        while ($written -LT $SizeBytes) {
            # Int64 on both sides: with an Int32 first argument PowerShell picks Math.Min(Int32, Int32)
            # and fails as soon as more than 2 GB are left.
            $count = [System.Int32] [System.Math]::Min([System.Int64] $CHUNK_BYTES, $SizeBytes - $written)
            $stream.Write($zeros, 0, $count)
            $written += $count

            $percent = [System.Math]::Floor(100 * $written / $SizeBytes)
            if ($null -NE $OnProgress -AND $percent -NE $lastPercent) {
                $lastPercent = $percent
                $null = & $OnProgress $percent
            }
        }
        # fsync: the zeros must be on the device, not in the page cache.
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }

    Write-Verbose "[Invoke-TabulaRasaOverwrite] '$Path': $written bytes of zeros in $([System.Math]::Round($stopwatch.Elapsed.TotalSeconds)) s."
    return [PSCustomObject]@{
        Detail       = 'Zeros, one pass'
        BytesWritten = $written
    }
}
