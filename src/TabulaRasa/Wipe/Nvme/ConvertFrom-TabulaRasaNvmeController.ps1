# NOTE:
#   Requires: nothing, pure parsing.
#
#   nvme id-ctrl /dev/nvme0 -o json | ConvertFrom-TabulaRasaNvmeController

function ConvertFrom-TabulaRasaNvmeController {
    <#
    .SYNOPSIS
        Reads the erase capabilities of an NVMe controller from 'nvme id-ctrl -o json'.

    .DESCRIPTION
        sanicap (Sanitize Capabilities), bits:
        - 0   Crypto Erase     destroys the media encryption key, instant
        - 1   Block Erase      erases every block, including spare and remapped ones
        - 2   Overwrite        writes a pattern over every block, slow
        fna (Format NVM Attributes), bit 2: Format with Secure Erase can do a crypto erase.

        Shape change:
        { "vid": 5197, "sanicap": 3, "fna": 4, ... }
        => IsCryptoErase = $true; IsBlockErase = $true; IsOverwrite = $false; IsFormatCryptoErase = $true

    .EXAMPLE
        PS> nvme id-ctrl /dev/nvme0 -o json | ConvertFrom-TabulaRasaNvmeController
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The JSON of 'nvme id-ctrl -o json', as one string or as lines from the pipeline.
        #>
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        [AllowEmptyString()]
        [System.String[]]
        $Json
    )

    BEGIN {
        $lines = [System.Collections.Generic.List[System.String]]::new()
    }
    PROCESS {
        $lines.AddRange($Json)
    }
    END {
        $Controller = $lines -join "`n" | ConvertFrom-Json
        $sanicap    = [System.Int64] $Controller.sanicap
        $fna        = [System.Int64] $Controller.fna

        return [PSCustomObject]@{
            IsCryptoErase       = ($sanicap -BAND 0x1) -NE 0
            IsBlockErase        = ($sanicap -BAND 0x2) -NE 0
            IsOverwrite         = ($sanicap -BAND 0x4) -NE 0
            IsFormatCryptoErase = ($fna -BAND 0x4) -NE 0
        }
    }
}
