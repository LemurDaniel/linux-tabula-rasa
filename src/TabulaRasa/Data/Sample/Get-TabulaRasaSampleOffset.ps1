# NOTE:
#   Requires: nothing, pure calculation.
#
#   Get-TabulaRasaSampleOffset -SizeBytes 500107862016 -BlockSize 4096 -SampleCount 64

function Get-TabulaRasaSampleOffset {
    <#
    .SYNOPSIS
        Returns block-aligned byte offsets spread evenly across a disk.

    .DESCRIPTION
        Always contains the first and the last full block, plus SampleCount blocks in between.
        Duplicates (on tiny disks) are removed, so the result can be shorter than SampleCount + 2.

        Shape change (SizeBytes 1 MiB, BlockSize 4096, SampleCount 3):
        => 0, 258048, 520192, 782336, 1044480

    .EXAMPLE
        PS> Get-TabulaRasaSampleOffset -SizeBytes 500107862016 -BlockSize 4096 -SampleCount 64
    #>

    [CmdletBinding()]
    [OutputType([System.Int64[]])]
    param (
        <#
        [Required]
        The size of the disk in bytes.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateRange(1, [System.Int64]::MaxValue)]
        [System.Int64]
        $SizeBytes,

        <#
        [Required]
        The size of one sample block in bytes, offsets are aligned to it.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateRange(512, 16777216)]
        [System.Int32]
        $BlockSize,

        <#
        [Required]
        The number of blocks spread between the first and the last block.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateRange(0, 100000)]
        [System.Int32]
        $SampleCount
    )

    $LastOffset = [System.Math]::Max(0, [System.Math]::Floor(($SizeBytes - $BlockSize) / $BlockSize) * $BlockSize)

    $Offsets = @(0) + @(
        for ($index = 1; $index -LE $SampleCount; $index++) {
            [System.Math]::Floor(($LastOffset * $index / ($SampleCount + 1)) / $BlockSize) * $BlockSize
        }
    ) + @($LastOffset)
    | ForEach-Object { [System.Int64] $_ }
    | Select-Object -Unique

    return [System.Int64[]] $Offsets
}
