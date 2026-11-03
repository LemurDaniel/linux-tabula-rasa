# NOTE:
#   Requires: nothing, pure parsing of the lsblk JSON.
#
#   lsblk --json --bytes --nodeps --output NAME,PATH,TYPE,SIZE,MODEL,SERIAL,TRAN,ROTA,RM | ConvertFrom-TabulaRasaLsblk

function ConvertFrom-TabulaRasaLsblk {
    <#
    .SYNOPSIS
        Turns the JSON of 'lsblk --json --bytes --nodeps' into disk objects.

    .DESCRIPTION
        Keeps only real disks (type 'disk', size above 0, no zram or ram devices) and resolves
        their kind. Separate from Get-TabulaRasaDisk, so the parsing is testable without lsblk.

        Shape change:
        { "blockdevices": [ { "name": "sda", "path": "/dev/sda", "type": "disk", "size": 500107862016,
                              "model": "Samsung SSD 870 ", "serial": "S5Y1", "tran": "sata", "rota": false, "rm": false } ] }
        => [PSCustomObject]@{ Name = 'sda'; Path = '/dev/sda'; Kind = 'SataSsd'; SizeBytes = 500107862016;
                              Model = 'Samsung SSD 870'; Serial = 'S5Y1'; Transport = 'sata'; IsRemovable = $false }

    .EXAMPLE
        PS> lsblk --json --bytes --nodeps --output NAME,PATH,TYPE,SIZE,MODEL,SERIAL,TRAN,ROTA,RM | ConvertFrom-TabulaRasaLsblk
    #>

    [CmdletBinding()]
    param (
        <#
        [Required]
        The raw JSON output of lsblk, as one string or as lines from the pipeline.
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
        $Devices = ($lines -join "`n" | ConvertFrom-Json).blockdevices

        foreach ($device in $Devices) {
            if ($device.type -NE 'disk' -OR [System.Int64] $device.size -LE 0) {
                Write-Verbose "[ConvertFrom-TabulaRasaLsblk] '$($device.name)' is type '$($device.type)' with size $($device.size) -> skipping."
                continue
            }
            if ($device.name -LIKE 'zram*' -OR $device.name -LIKE 'ram*') {
                Write-Verbose "[ConvertFrom-TabulaRasaLsblk] '$($device.name)' is a RAM disk -> skipping."
                continue
            }

            # Older util-linux reports flags as "0"/"1", newer as JSON booleans.
            # Compared as strings: '$true -EQ "0"' is $true, because a non-empty string casts to $true.
            $isRotational = ([System.String] $device.rota) -IN @('True', '1')
            $isRemovable  = ([System.String] $device.rm) -IN @('True', '1')
            $transport    = [System.String] $device.tran

            [PSCustomObject]@{
                Name        = $device.name
                Path        = $device.path
                Kind        = Resolve-TabulaRasaDiskKind -Name $device.name -Transport $transport -IsRotational $isRotational
                SizeBytes   = [System.Int64] $device.size
                Model       = ([System.String] $device.model).Trim()
                Serial      = ([System.String] $device.serial).Trim()
                Transport   = $transport
                IsRemovable = $isRemovable
            }
        }
    }
}
