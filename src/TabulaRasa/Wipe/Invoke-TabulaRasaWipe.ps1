function Invoke-TabulaRasaWipe {
    <#
    .SYNOPSIS
        Wipes a disk with the given method.

    .DESCRIPTION
        Scaffold: the methods are not implemented yet and throw, so nothing is wiped by accident.
        Planned per method:
        - Overwrite        dd/FileStream with zeros over the full size, then flush.
        - AtaSecureErase   hdparm: check 'not frozen', set a temporary password, --security-erase(-enhanced).
        - NvmeSanitize     nvme id-ctrl: read sanicap, then 'nvme sanitize' (crypto > block erase),
                           fallback 'nvme format --ses'.

    .EXAMPLE
        PS> Invoke-TabulaRasaWipe -Path /dev/sdb -Method Overwrite -WhatIf
    #>

    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param (
        <#
        [Required]
        The device path, e.g. '/dev/sdb'.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $Path,

        <#
        [Required]
        The wipe method from Resolve-TabulaRasaWipeMethod.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [ValidateSet('Overwrite', 'AtaSecureErase', 'NvmeSanitize')]
        [System.String]
        $Method
    )

    if (-NOT $PSCmdlet.ShouldProcess($Path, "Wipe with '$Method'")) {
        return
    }

    throw [System.NotImplementedException]::new("Wipe method '$Method' is not implemented yet, '$Path' was not touched.")
}
