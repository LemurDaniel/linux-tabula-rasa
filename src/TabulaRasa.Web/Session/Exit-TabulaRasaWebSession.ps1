# NOTE:
#   Requires: nothing, works on a plain hashtable (the Pode state 'Session').
#
#   Exit-TabulaRasaWebSession -Session $state -Token $token

function Exit-TabulaRasaWebSession {
    <#
    .SYNOPSIS
        Releases the session when the caller owns it, so another device can take control.

    .EXAMPLE
        PS> Exit-TabulaRasaWebSession -Session $state -Token $token
    #>

    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param (
        <#
        [Required]
        The session state from Enter-TabulaRasaWebSession. Changed in place.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.Collections.IDictionary]
        $Session,

        <#
        [Optional]
        The token the caller presents.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [AllowEmptyString()]
        [AllowNull()]
        [System.String]
        $Token
    )

    if ([System.String]::IsNullOrEmpty($Token) -OR $Token -CNE $Session['Token']) {
        return $false
    }

    Write-Verbose "[Exit-TabulaRasaWebSession] '$($Session['Address'])' released the session."
    $Session['Token']   = $null
    $Session['Address'] = $null
    return $true
}
