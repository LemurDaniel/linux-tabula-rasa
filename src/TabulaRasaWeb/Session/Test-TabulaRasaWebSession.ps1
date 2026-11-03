function Test-TabulaRasaWebSession {
    <#
    .SYNOPSIS
        Checks that a token owns the live session and refreshes its idle timer.

    .DESCRIPTION
        Called for every protected API request by the session middleware.
        Returns $false for a missing, foreign or expired token. An expired session is cleared.

    .EXAMPLE
        PS> Test-TabulaRasaWebSession -Session $state -Token $token
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
        $Token,

        <#
        [Optional]
        Seconds without a request after which the session is free again. Default is 300.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [ValidateRange(10, 86400)]
        [System.Int32]
        $TimeoutSeconds = 300,

        <#
        [Optional]
        The current time, injectable for tests. Default is now.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.DateTime]
        $Now = [System.DateTime]::UtcNow
    )

    if ([System.String]::IsNullOrEmpty($Token) -OR $Token -CNE $Session['Token']) {
        return $false
    }

    if (($Now - $Session['LastSeen']).TotalSeconds -GT $TimeoutSeconds) {
        Write-Verbose "[Test-TabulaRasaWebSession] Session of '$($Session['Address'])' expired -> cleared."
        $Session['Token'] = $null
        return $false
    }

    $Session['LastSeen'] = $Now
    return $true
}
