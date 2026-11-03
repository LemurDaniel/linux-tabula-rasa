# NOTE:
#   Requires: Linux and the TabulaRasa module (Get-TabulaRasaDisk).
#
#   $disk = Resolve-TabulaRasaWebDisk -Name $WebEvent.Parameters['name']

function Resolve-TabulaRasaWebDisk {
    <#
    .SYNOPSIS
        Finds a wipeable disk by its kernel name, $null when there is none.

    .DESCRIPTION
        Every route takes the disk name from the URL. Looking it up in Get-TabulaRasaDisk means
        a request can only reach disks the menu lists: never the boot stick, never a path
        made up in the browser.

    .EXAMPLE
        PS> Resolve-TabulaRasaWebDisk -Name sdb
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The kernel name of the disk, e.g. 'sdb'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [AllowEmptyString()]
        [System.String]
        $Name
    )

    return Get-TabulaRasaDisk | Where-Object -Property Name -CEQ -Value $Name | Select-Object -First 1
}
