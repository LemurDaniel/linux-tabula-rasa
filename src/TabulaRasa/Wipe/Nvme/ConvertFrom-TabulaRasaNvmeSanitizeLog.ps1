# NOTE:
#   Requires: nothing, pure parsing.
#
#   nvme sanitize-log /dev/nvme0 -o json | ConvertFrom-TabulaRasaNvmeSanitizeLog

function ConvertFrom-TabulaRasaNvmeSanitizeLog {
    <#
    .SYNOPSIS
        Reads status and progress of a running sanitize from 'nvme sanitize-log -o json'.

    .DESCRIPTION
        sstat bits 2:0 hold the status, sprog the progress as fraction of 65536:
        - 0   Never       no sanitize since the drive was made
        - 1   Success     the last sanitize completed
        - 2   InProgress  sprog counts up
        - 3   Failed      the last sanitize failed
        - 4   Success     completed, without deallocating the blocks

        nvme-cli writes the log flat (1.x) or under the device name (2.x), and sstat as
        number or as object with a 'status' field. All shapes are read:

        Shape change:
        { "sprog": 32768, "sstat": 2 }                                       => InProgress, 50 %
        { "nvme0": { "sprog": 65535, "sstat": { "status": 1 } } }           => Success, 100 %

    .EXAMPLE
        PS> nvme sanitize-log /dev/nvme0 -o json | ConvertFrom-TabulaRasaNvmeSanitizeLog
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The JSON of 'nvme sanitize-log -o json', as one string or as lines from the pipeline.
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
        $STATUS_NAMES = @{ 0 = 'Never'; 1 = 'Success'; 2 = 'InProgress'; 3 = 'Failed'; 4 = 'Success' }

        # Flat, or one level down under the device name.
        $Log = $lines -join "`n" | ConvertFrom-Json
        if ($Log.PSObject.Properties.Name -NOTCONTAINS 'sstat') {
            $Log = $Log.PSObject.Properties | Select-Object -First 1 -ExpandProperty Value
        }
        if ($null -EQ $Log -OR $Log.PSObject.Properties.Name -NOTCONTAINS 'sstat') {
            throw [System.IO.InvalidDataException]::new("The sanitize log must contain 'sstat', got: $($lines -join ' ')")
        }

        $statusCode = $Log.sstat -IS [System.Management.Automation.PSCustomObject] ? [System.Int32] $Log.sstat.status : ([System.Int32] $Log.sstat -BAND 0x7)
        $status     = $STATUS_NAMES.ContainsKey($statusCode) ? $STATUS_NAMES[$statusCode] : 'Failed'
        $percent    = $status -EQ 'InProgress' ? [System.Math]::Floor(100 * [System.Int64] $Log.sprog / 65536) : ($status -EQ 'Success' ? 100 : 0)

        return [PSCustomObject]@{
            Status  = $status
            Percent = $percent
        }
    }
}
