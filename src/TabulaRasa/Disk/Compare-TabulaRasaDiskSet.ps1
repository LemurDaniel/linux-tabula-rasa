# NOTE:
#   Requires: nothing, pure comparison of two disk lists.
#
#   (Compare-TabulaRasaDiskSet -Before $before -After (Get-TabulaRasaDisk)).Added

function Compare-TabulaRasaDiskSet {
    <#
    .SYNOPSIS
        Compares two disk lists by kernel name and returns the added and the removed disks.

    .DESCRIPTION
        Drives the replug confirmation for USB sticks and SD cards: the user unplugs the device
        (it shows up in Removed) and plugs it in again (it shows up in Added, maybe under a new name).

    .EXAMPLE
        PS> $before = Get-TabulaRasaDisk
        PS> # ... user plugs in a stick ...
        PS> (Compare-TabulaRasaDiskSet -Before $before -After (Get-TabulaRasaDisk)).Added
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The disks before the change, from Get-TabulaRasaDisk. May be empty.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [AllowEmptyCollection()]
        [PSCustomObject[]]
        $Before,

        <#
        [Required]
        The disks after the change, from Get-TabulaRasaDisk. May be empty.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [AllowEmptyCollection()]
        [PSCustomObject[]]
        $After
    )

    $beforeNames = @($Before | ForEach-Object { $_.Name })
    $afterNames  = @($After | ForEach-Object { $_.Name })

    return [PSCustomObject]@{
        Added   = @($After | Where-Object { $_.Name -NOTIN $beforeNames })
        Removed = @($Before | Where-Object { $_.Name -NOTIN $afterNames })
    }
}
