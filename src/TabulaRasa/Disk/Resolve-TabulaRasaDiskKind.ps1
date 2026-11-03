# NOTE:
#   Requires: nothing, pure mapping.
#
#   Resolve-TabulaRasaDiskKind -Name sda -Transport sata -IsRotational $false

function Resolve-TabulaRasaDiskKind {
    <#
    .SYNOPSIS
        Resolves the kind of a disk from its lsblk name, transport and rotation flag.

    .DESCRIPTION
        The kind decides the wipe method, see Resolve-TabulaRasaWipeMethod.

        Order of precedence:
        - SD card         name mmcblk* or transport mmc
        - USB             transport usb, also an NVMe or SSD in a USB enclosure,
                          because the bridge hides the drive's own erase commands
        - NVMe            transport nvme or name nvme*
        - HDD             rotational
        - SATA SSD        transport sata or ata and not rotational
        - Unknown         everything else (SAS, virtio, ...)

    .EXAMPLE
        PS> Resolve-TabulaRasaDiskKind -Name sda -Transport sata -IsRotational $false
        SataSsd
    #>

    [CmdletBinding()]
    [OutputType([System.String])]
    param (
        <#
        [Required]
        The kernel name of the disk, e.g. 'sda' or 'nvme0n1'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Name,

        <#
        [Optional]
        The lsblk transport, e.g. 'sata', 'nvme', 'usb', 'mmc'. Empty when lsblk reports none.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [AllowEmptyString()]
        [System.String]
        $Transport = '',

        <#
        [Required]
        Whether the disk has spinning platters.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.Boolean]
        $IsRotational
    )

    # SD card
    if ($Name -LIKE 'mmcblk*' -OR $Transport -EQ 'mmc') {
        return 'SdCard'
    }
    # USB
    if ($Transport -EQ 'usb') {
        return 'Usb'
    }
    # NVMe
    if ($Transport -EQ 'nvme' -OR $Name -LIKE 'nvme*') {
        return 'Nvme'
    }
    # HDD
    if ($IsRotational) {
        return 'Hdd'
    }
    # SATA SSD
    if ($Transport -IN @('sata', 'ata')) {
        return 'SataSsd'
    }
    # Unknown
    return 'Unknown'
}
