# NOTE:
#   Requires: nothing, works on a plain hashtable (the Pode state 'Session').
#
#   Enter-TabulaRasaWebSession -Session $state -Token $null -ClientAddress '192.168.1.20'
#   Enter-TabulaRasaWebSession -Session $state -ClientAddress '127.0.0.1' -IsLocal $true -IsTakeover $true

#
#   Chapters:
#     CLAIM THE SESSION   Grants, refreshes or denies the single control session.
#

function Enter-TabulaRasaWebSession {
    <#
    .SYNOPSIS
        Claims the single control session of the web UI, or says who holds it.

    .DESCRIPTION
        Only one device controls the stick at a time, so a phone and the kiosk never click into
        each other's wipe.

        > No owner, or the owner was idle longer than the timeout
            - Grant a new token to the caller.
        > The caller presents the owner's token
            - Grant again and refresh the idle timer.
        > The caller is the local kiosk and asks for a takeover
            - Grant a new token, sitting in front of the machine beats a remote device.
        > Otherwise
            - Deny, with the owner's address and the seconds until the session times out.

        Works on a plain hashtable (the Pode state 'Session'), so it is testable without a server.

    .EXAMPLE
        PS> Enter-TabulaRasaWebSession -Session $state -Token $null -ClientAddress '192.168.1.20'
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        <#
        [Required]
        The session state with Token, Address and LastSeen. Changed in place.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.Collections.IDictionary]
        $Session,

        <#
        [Optional]
        The token the caller presents. Empty for a first claim.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [AllowEmptyString()]
        [AllowNull()]
        [System.String]
        $Token,

        <#
        [Required]
        The IP address of the caller, shown to others while it holds the session.
        #>
        [Parameter(
            Mandatory = $true
        )]
        [System.String]
        $ClientAddress,

        <#
        [Optional]
        Whether the caller is the local kiosk (loopback address).
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.Boolean]
        $IsLocal = $false,

        <#
        [Optional]
        Asks to take the session over. Only honoured for the local kiosk.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [System.Boolean]
        $IsTakeover = $false,

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

    $hasOwner  = -NOT [System.String]::IsNullOrEmpty($Session['Token'])
    $isExpired = $hasOwner -AND ($Now - $Session['LastSeen']).TotalSeconds -GT $TimeoutSeconds
    $isOwner   = $hasOwner -AND $Token -CEQ $Session['Token']

    # ===========================================================================
    # ==========================   CLAIM THE SESSION   ==========================
    # ===========================================================================
    #
    #   1. Free     No owner, an idle owner or a kiosk takeover: a new token.
    #   2. Owner    The owner's token: refresh the idle timer.
    #   3. Denied   Otherwise: the owner's address and the seconds left.
    #

    # ---------------------------------------------------------------------------
    # Free
    #   No owner, an idle owner or a kiosk takeover: a new token.
    # ---------------------------------------------------------------------------

    if (-NOT $hasOwner -OR $isExpired -OR ($IsLocal -AND $IsTakeover)) {
        Write-Verbose "[Enter-TabulaRasaWebSession] Granting a new session to '$ClientAddress' (owner: $hasOwner, expired: $isExpired, takeover: $($IsLocal -AND $IsTakeover))."
        $Session['Token']    = [System.Guid]::NewGuid().ToString('N')
        $Session['Address']  = $ClientAddress
        $Session['LastSeen'] = $Now
        return [PSCustomObject]@{ IsGranted = $true; Token = $Session['Token']; OwnerAddress = $ClientAddress; SecondsLeft = $TimeoutSeconds }
    }

    # ---------------------------------------------------------------------------
    # Owner
    #   The owner's token: refresh the idle timer.
    # ---------------------------------------------------------------------------

    if ($isOwner) {
        $Session['LastSeen'] = $Now
        return [PSCustomObject]@{ IsGranted = $true; Token = $Session['Token']; OwnerAddress = $Session['Address']; SecondsLeft = $TimeoutSeconds }
    }

    # ---------------------------------------------------------------------------
    # Denied
    #   Otherwise: the owner's address and the seconds left.
    # ---------------------------------------------------------------------------

    $secondsLeft = [System.Math]::Max(0, [System.Math]::Ceiling($TimeoutSeconds - ($Now - $Session['LastSeen']).TotalSeconds))
    Write-Verbose "[Enter-TabulaRasaWebSession] '$ClientAddress' denied, '$($Session['Address'])' holds the session for $secondsLeft more seconds."
    return [PSCustomObject]@{ IsGranted = $false; Token = $null; OwnerAddress = $Session['Address']; SecondsLeft = $secondsLeft }
}
