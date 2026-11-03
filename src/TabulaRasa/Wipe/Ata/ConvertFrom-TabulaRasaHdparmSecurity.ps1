# NOTE:
#   Requires: nothing, pure parsing.
#
#   hdparm -I /dev/sda | ConvertFrom-TabulaRasaHdparmSecurity

function ConvertFrom-TabulaRasaHdparmSecurity {
    <#
    .SYNOPSIS
        Reads the Security section of 'hdparm -I' into the states ATA Secure Erase depends on.

    .DESCRIPTION
        The section lists one state per line, negated states carry a 'not' in front:

        Shape change:
        Security:
                Master password revision code = 65534
                        supported
                not     enabled
                not     locked
                        frozen
                not     expired: security count
                        supported: enhanced erase
                2min for SECURITY ERASE UNIT. 4min for ENHANCED SECURITY ERASE UNIT.
        => IsSupported = $true; IsEnabled = $false; IsLocked = $false; IsFrozen = $true
           IsEnhancedSupported = $true; EraseMinutes = 2; EnhancedEraseMinutes = 4

        The minutes may read '>508min', the number is taken as is.

    .EXAMPLE
        PS> hdparm -I /dev/sda | ConvertFrom-TabulaRasaHdparmSecurity
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The output of 'hdparm -I', as one string or as lines from the pipeline.
        #>
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true
        )]
        [AllowEmptyString()]
        [System.String[]]
        $Text
    )

    BEGIN {
        $lines = [System.Collections.Generic.List[System.String]]::new()
    }
    PROCESS {
        $lines.AddRange($Text)
    }
    END {
        # The section runs from 'Security:' to the next line without indentation.
        $section   = [System.Collections.Generic.List[System.String]]::new()
        $isSection = $false
        foreach ($line in ($lines -join "`n") -split "`n") {
            if ($line -MATCH '^Security:') {
                $isSection = $true
                continue
            }
            if ($isSection -AND $line -MATCH '^\S') {
                break
            }
            if ($isSection) {
                # 'not\tenabled' and '\t\tenabled' => 'not enabled' and 'enabled'
                $section.Add(($line -replace '\s+', ' ').Trim())
            }
        }

        $hasState = { param ($State) $section -CONTAINS $State }
        $minutes  = { param ($Pattern) $match = [System.Text.RegularExpressions.Regex]::Match(($section -join ' '), $Pattern); $match.Success ? [System.Int32] $match.Groups[1].Value : $null }

        return [PSCustomObject]@{
            IsSupported          = & $hasState 'supported'
            IsEnabled            = & $hasState 'enabled'
            IsLocked             = & $hasState 'locked'
            IsFrozen             = & $hasState 'frozen'
            IsEnhancedSupported  = & $hasState 'supported: enhanced erase'
            EraseMinutes         = & $minutes '(\d+)min for SECURITY ERASE UNIT'
            EnhancedEraseMinutes = & $minutes '(\d+)min for ENHANCED SECURITY ERASE UNIT'
        }
    }
}
