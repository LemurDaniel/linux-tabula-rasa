# NOTE:
#   Loaded by Use-PodeRoutes in Start-TabulaRasaServer.
#
#   POST   /api/session   Claims the session, { isTakeover } lets the local kiosk take over.
#   DELETE /api/session   Releases the session.

#
#   Chapters:
#     SESSION ROUTES   Claim and release of the single control session.
#

# ===========================================================================
# ============================   SESSION ROUTES   ===========================
# ===========================================================================
#
#   POST /api/session     Grants a token or answers 423 with the owner's address.
#   DELETE /api/session   Clears the session when the caller owns it.
#

Add-PodeRoute -Method Post -Path '/api/session' -ScriptBlock {
    $session    = Get-PodeState -Name 'Session'
    $address    = $WebEvent.Request.RemoteEndPoint.Address
    $isTakeover = $null -NE $WebEvent.Data -AND [System.Boolean] $WebEvent.Data.isTakeover

    $SessionClaim = @{
        Session        = $session
        Token          = Get-PodeHeader -Name 'X-Session-Token'
        ClientAddress  = $address.ToString()
        IsLocal        = [System.Net.IPAddress]::IsLoopback($address)
        IsTakeover     = $isTakeover
        TimeoutSeconds = (Get-PodeState -Name 'Config').SessionTimeoutSeconds
    }
    $Result = Lock-PodeObject -Object $session -Return -ScriptBlock {
        Enter-TabulaRasaWebSession @SessionClaim
    }

    $statusCode = $Result.IsGranted ? 200 : 423
    Write-PodeJsonResponse -StatusCode $statusCode -Value @{
        isGranted    = $Result.IsGranted
        token        = $Result.Token
        ownerAddress = $Result.OwnerAddress
        secondsLeft  = $Result.SecondsLeft
    }
}

Add-PodeRoute -Method Delete -Path '/api/session' -ScriptBlock {
    $session = Get-PodeState -Name 'Session'
    $token   = Get-PodeHeader -Name 'X-Session-Token'
    $isReleased = Lock-PodeObject -Object $session -Return -ScriptBlock {
        Exit-TabulaRasaWebSession -Session $session -Token $token
    }
    Write-PodeJsonResponse -Value @{ isReleased = $isReleased }
}
