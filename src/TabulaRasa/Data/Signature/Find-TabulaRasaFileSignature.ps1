# NOTE:
#   Requires: read access to the device (root), the loaded TabulaRasa module
#             (TabulaRasa.SignatureScanner) and data.signatures.psd1 next to this file.
#
#   Find-TabulaRasaFileSignature -Path /dev/sdb -SizeBytes 32000000000 -Mode Quick

#
#   Chapters:
#     SCAN FOR FILE HEADERS   Loads the signatures, scans the disk and returns the found types.
#

function Find-TabulaRasaFileSignature {
    <#
    .SYNOPSIS
        Counts file headers (JPEG, PDF, ZIP, ...) on a disk, also where no file system is left.

    .DESCRIPTION
        File carving in short: a file usually starts at a sector boundary with fixed magic bytes
        (a JPEG with FF D8 FF). Those headers survive a quick format, so counting them shows
        what could still be recovered. The signatures come from data.signatures.psd1.

        Modes:
        - Quick   Reads 256 blocks of 64 KiB spread across the disk (16 MiB), seconds.
                  An estimate, not an inventory.
        - Deep    Reads the whole disk in 4 MiB chunks, as fast as the disk can deliver.

        OnProgress is called whenever the percentage changes, with the percentage and the current
        hits. When it returns $false, the scan stops and the result is marked IsCancelled.

    .EXAMPLE
        PS> Find-TabulaRasaFileSignature -Path /dev/sdb -SizeBytes 32000000000 -Mode Quick

    .EXAMPLE
        Deep scan with a progress line:

        PS> Find-TabulaRasaFileSignature -Path /dev/sdb -SizeBytes 32000000000 -Mode Deep -OnProgress {
                param ($Percent, $Hits)
                Write-Host "$Percent %"
            }
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The device path of the disk or partition, e.g. '/dev/sdb'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Path,

        <#
        [Required]
        The size in bytes, from Get-TabulaRasaDisk. Block devices report no file length.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateRange(1, [System.Int64]::MaxValue)]
        [System.Int64]
        $SizeBytes,

        <#
        [Optional]
        Quick samples the disk, Deep reads all of it. Default is Quick.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [ValidateSet('Quick', 'Deep')]
        [System.String]
        $Mode = 'Quick',

        <#
        [Optional]
        Called with (Percent, Hits) whenever the percentage changes. Returning $false cancels.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.Management.Automation.ScriptBlock]
        $OnProgress = $null
    )

    $SECTOR_SIZE        = 512
    $QUICK_BLOCK_SIZE   = 65536
    $QUICK_SAMPLE_COUNT = 254       # plus first and last block = 256 blocks
    $DEEP_CHUNK_SIZE    = 4194304   # a multiple of the sector size, so no header crosses a chunk

    # ===========================================================================
    # ========================   SCAN FOR FILE HEADERS   ========================
    # ===========================================================================
    #
    #   1. Signatures   Loads the magic bytes from data.signatures.psd1.
    #   2. Scan         Quick reads the sample offsets, Deep the whole disk.
    #   3. Result       Returns the found types, most frequent first.
    #

    # ---------------------------------------------------------------------------
    # Signatures
    #   Loads the magic bytes from data.signatures.psd1.
    # ---------------------------------------------------------------------------

    $Signatures = (Import-PowerShellDataFile -Path (Join-Path -Path $PSScriptRoot -ChildPath 'data.signatures.psd1')).Signatures
    # The leading ',' keeps every byte array whole, the pipeline would unroll it into single bytes.
    $Magics     = [System.Byte[][]] @($Signatures | ForEach-Object { , [System.Convert]::FromHexString($_.Magic) })
    $Offsets    = [System.Int32[]] @($Signatures | ForEach-Object { $_.Offset })
    $Counts     = [System.Int64[]]::new($Signatures.Count)

    # Turns the raw counters into a list of the found types, most frequent first.
    $getHits = {
        for ($index = 0; $index -LT $Signatures.Count; $index++) {
            if ($Counts[$index] -GT 0) {
                [PSCustomObject]@{ Type = $Signatures[$index].Type; Count = $Counts[$index] }
            }
        }
    }

    # ---------------------------------------------------------------------------
    # Scan
    #   Quick reads the sample offsets, Deep the whole disk.
    # ---------------------------------------------------------------------------

    # > Quick   one read per sample offset
    # > Deep    sequential reads from 0 to the end
    $SampleOffsets = $Mode -EQ 'Quick' ? (Get-TabulaRasaSampleOffset -SizeBytes $SizeBytes -BlockSize $QUICK_BLOCK_SIZE -SampleCount $QUICK_SAMPLE_COUNT) : @()

    $bufferSize   = $Mode -EQ 'Quick' ? $QUICK_BLOCK_SIZE : $DEEP_CHUNK_SIZE
    $buffer       = [System.Byte[]]::new($bufferSize)
    $BytesScanned = [System.Int64] 0
    $IsCancelled  = $false
    $lastPercent  = -1

    $stream = [System.IO.FileStream]::new($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite, 1, [System.IO.FileOptions]::SequentialScan)
    try {
        $readIndex = 0
        while ($true) {
            # Next read: a sample offset, or the next chunk.
            if ($Mode -EQ 'Quick') {
                if ($readIndex -GE $SampleOffsets.Count) {
                    break
                }
                $null = $stream.Seek($SampleOffsets[$readIndex], [System.IO.SeekOrigin]::Begin)
                $percent = [System.Math]::Floor(100 * ($readIndex + 1) / $SampleOffsets.Count)
            }
            else {
                if ($BytesScanned -GE $SizeBytes) {
                    break
                }
                $percent = [System.Math]::Floor(100 * $BytesScanned / $SizeBytes)
            }

            $readCount = $stream.Read($buffer, 0, $bufferSize)
            if ($readCount -LE 0) {
                break
            }
            [TabulaRasa.SignatureScanner]::CountSignatures($buffer, $readCount, $SECTOR_SIZE, $Magics, $Offsets, $Counts)

            $BytesScanned += $readCount
            $readIndex++

            # Progress and cancellation, only when the percentage changed.
            if ($null -NE $OnProgress -AND $percent -NE $lastPercent) {
                $lastPercent = $percent
                if ((& $OnProgress $percent @(& $getHits)) -EQ $false) {
                    Write-Verbose "[Find-TabulaRasaFileSignature] Cancelled at $percent %."
                    $IsCancelled = $true
                    break
                }
            }
        }
    }
    finally {
        $stream.Dispose()
    }

    # ---------------------------------------------------------------------------
    # Result
    #   Returns the found types, most frequent first.
    # ---------------------------------------------------------------------------

    $Hits = @(& $getHits | Sort-Object -Property Count -Descending)
    Write-Verbose "[Find-TabulaRasaFileSignature] '$Path' ($Mode): $($Hits.Count) types found in $BytesScanned bytes."

    return [PSCustomObject]@{
        Path         = $Path
        Mode         = $Mode
        BytesScanned = $BytesScanned
        IsCancelled  = $IsCancelled
        Hits         = $Hits
    }
}
