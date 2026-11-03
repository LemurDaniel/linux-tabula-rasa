# NOTE:
#   Requires: nothing, pure mapping.
#
#   Resolve-TabulaRasaWipeMethod -Kind Nvme

function Resolve-TabulaRasaWipeMethod {
    <#
    .SYNOPSIS
        Picks the wipe method and the confirmation for a disk kind and says how reliable the wipe is.

    .DESCRIPTION
        > HDD             Overwrite with zeros, one pass reaches every sector.
        > SATA SSD        ATA Secure Erase, the controller also erases spare and remapped blocks.
        > NVMe            NVMe Sanitize, same reason as above.
        > USB, SD card    Overwrite, the controller offers no secure erase command and may keep
                          remapped blocks out of reach. Physical destruction for sensitive data.
        > Unknown         Overwrite, with the same warning.

        Confirmation:
        - Serial   HDDs, SSDs and NVMe drives carry their serial on the label, the user types it.
        - Replug   USB sticks and SD cards rarely show a serial (or a fake one), the user unplugs
                   and plugs in the device instead, which selects it physically.

    .EXAMPLE
        PS> Resolve-TabulaRasaWipeMethod -Kind Nvme
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The disk kind from Resolve-TabulaRasaDiskKind.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateSet('Hdd', 'SataSsd', 'Nvme', 'Usb', 'SdCard', 'Unknown')]
        [System.String]
        $Kind
    )

    $UNREACHABLE_BLOCKS_WARNING = 'The controller may keep remapped blocks out of reach. Destroy the device physically if the data is sensitive.'

    $WipeMethods = @{
        Hdd     = @{ Method = 'Overwrite';      Confirmation = 'Serial'; IsComplete = $true;  Warning = $null }
        SataSsd = @{ Method = 'AtaSecureErase'; Confirmation = 'Serial'; IsComplete = $true;  Warning = $null }
        Nvme    = @{ Method = 'NvmeSanitize';   Confirmation = 'Serial'; IsComplete = $true;  Warning = $null }
        Usb     = @{ Method = 'Overwrite';      Confirmation = 'Replug'; IsComplete = $false; Warning = $UNREACHABLE_BLOCKS_WARNING }
        SdCard  = @{ Method = 'Overwrite';      Confirmation = 'Replug'; IsComplete = $false; Warning = $UNREACHABLE_BLOCKS_WARNING }
        Unknown = @{ Method = 'Overwrite';      Confirmation = 'Serial'; IsComplete = $false; Warning = $UNREACHABLE_BLOCKS_WARNING }
    }

    return [PSCustomObject] $WipeMethods[$Kind]
}
