# NOTE:
#   Requires: nothing, pure parsing of the lsblk JSON.
#
#   lsblk --json --bytes --output NAME,PATH,TYPE,SIZE,FSTYPE,LABEL /dev/sdb | ConvertFrom-TabulaRasaPartitionLsblk

function ConvertFrom-TabulaRasaPartitionLsblk {
    <#
    .SYNOPSIS
        Turns the JSON of 'lsblk --json --bytes <disk>' into partition objects.

    .DESCRIPTION
        > The disk has partitions      Returns every child of type 'part'.
        > The disk has none            Returns the disk itself when it holds a file system
                                       directly (a "superfloppy" USB stick), else nothing.

        Shape change:
        { "blockdevices": [ { "name": "sdb", "path": "/dev/sdb", "type": "disk", "size": 32000000000, "fstype": null, "label": null,
                              "children": [ { "name": "sdb1", "path": "/dev/sdb1", "type": "part", "size": 31999000000, "fstype": "exfat", "label": "STICK" } ] } ] }
        => [PSCustomObject]@{ Name = 'sdb1'; Path = '/dev/sdb1'; SizeBytes = 31999000000; FileSystem = 'exfat'; Label = 'STICK' }

    .EXAMPLE
        PS> lsblk --json --bytes --output NAME,PATH,TYPE,SIZE,FSTYPE,LABEL /dev/sdb | ConvertFrom-TabulaRasaPartitionLsblk
    #>

    [CmdletBinding()]
    param (
        <#
        [Required]
        The raw JSON output of lsblk for one disk, as one string or as lines from the pipeline.
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
        $Disk = ($lines -join "`n" | ConvertFrom-Json).blockdevices | Select-Object -First 1
        if ($null -EQ $Disk) {
            return
        }

        $Children   = $Disk.PSObject.Properties.Name -CONTAINS 'children' ? $Disk.children : @()
        $Partitions = @($Children | Where-Object -Property type -EQ -Value 'part')

        # A disk without partitions only counts when it carries a file system itself.
        if ($Partitions.Count -EQ 0) {
            $Partitions = @(@($Disk) | Where-Object { -NOT [System.String]::IsNullOrEmpty($_.fstype) })
        }

        foreach ($partition in $Partitions) {
            [PSCustomObject]@{
                Name       = $partition.name
                Path       = $partition.path
                SizeBytes  = [System.Int64] $partition.size
                FileSystem = [System.String] $partition.fstype
                Label      = [System.String] $partition.label
            }
        }
    }
}
