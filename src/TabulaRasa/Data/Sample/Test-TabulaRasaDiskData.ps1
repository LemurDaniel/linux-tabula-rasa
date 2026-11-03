function Test-TabulaRasaDiskData {
    <#
    .SYNOPSIS
        Reads sample blocks across a disk and counts the ones that are not all zero.

    .DESCRIPTION
        Read only. Samples the blocks from Get-TabulaRasaSampleOffset.
        A block that is not all zero holds data or a pattern.

        Reading the result:
        - Before a wipe     NonZeroCount > 0 means there is something to wipe.
        - After Overwrite   NonZeroCount must be 0.
        - After an erase    0 is expected, but a secure erase may also leave 0xFF or random bytes
                            (crypto erase), so non-zero blocks there are no proof of a failed wipe.

    .EXAMPLE
        Check a disk with the default 64 samples:

        PS> Test-TabulaRasaDiskData -Path /dev/sdb -SizeBytes 500107862016
    #>

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
        The size of the disk in bytes, from Get-TabulaRasaDisk. Block devices report no file length.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateRange(1, [System.Int64]::MaxValue)]
        [System.Int64]
        $SizeBytes,

        <#
        [Optional]
        The number of blocks spread between the first and the last block. Default is 64.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [ValidateRange(0, 100000)]
        [System.Int32]
        $SampleCount = 64
    )

    $BLOCK_SIZE = 4096

    $Offsets      = Get-TabulaRasaSampleOffset -SizeBytes $SizeBytes -BlockSize $BLOCK_SIZE -SampleCount $SampleCount
    $buffer       = [System.Byte[]]::new($BLOCK_SIZE)
    $zeroBlock    = [System.Byte[]]::new($BLOCK_SIZE)
    $NonZeroCount = 0

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        foreach ($offset in $Offsets) {
            $null      = $stream.Seek($offset, [System.IO.SeekOrigin]::Begin)
            $readCount = $stream.Read($buffer, 0, $BLOCK_SIZE)

            # A short read at the very end leaves old bytes in the buffer, so only the read part counts.
            if ($readCount -LT $BLOCK_SIZE) {
                [System.Array]::Clear($buffer, $readCount, $BLOCK_SIZE - $readCount)
            }
            if (-NOT [System.Linq.Enumerable]::SequenceEqual($buffer, $zeroBlock)) {
                $NonZeroCount++
            }
        }
    }
    finally {
        $stream.Dispose()
    }

    Write-Verbose "[Test-TabulaRasaDiskData] '$Path': $NonZeroCount of $($Offsets.Count) sampled blocks are not zero."
    return [PSCustomObject]@{
        Path         = $Path
        SampleCount  = $Offsets.Count
        NonZeroCount = $NonZeroCount
        HasData      = $NonZeroCount -GT 0
    }
}
