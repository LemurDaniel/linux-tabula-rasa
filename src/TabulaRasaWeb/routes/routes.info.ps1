# NOTE:
#   Loaded by Use-PodeRoutes in Start-TabulaRasaServer. Both routes are public (no session).
#
#   GET /api/info        Network (URLs, hotspot) and who holds the session.
#   GET /api/qr?text=    The text as QR code (SVG), for the URLs and the hotspot login.

#
#   Chapters:
#     INFO ROUTES   Reachability and QR codes for the start screen.
#

# ===========================================================================
# =============================   INFO ROUTES   =============================
# ===========================================================================
#
#   GET /api/info   Network, session owner and seconds until it is free.
#   GET /api/qr     Renders text as SVG QR code with qrencode.
#

Add-PodeRoute -Method Get -Path '/api/info' -ScriptBlock {
    $session = Get-PodeState -Name 'Session'
    $timeout = (Get-PodeState -Name 'Config').SessionTimeoutSeconds
    $address = $WebEvent.Request.RemoteEndPoint.Address

    $isLocked    = -NOT [System.String]::IsNullOrEmpty($session['Token']) -AND ([System.DateTime]::UtcNow - $session['LastSeen']).TotalSeconds -LE $timeout
    $secondsLeft = $isLocked ? [System.Math]::Ceiling($timeout - ([System.DateTime]::UtcNow - $session['LastSeen']).TotalSeconds) : 0

    Write-PodeJsonResponse -Depth 5 -Value @{
        network = Get-TabulaRasaWebNetwork
        isLocal = [System.Net.IPAddress]::IsLoopback($address)
        session = @{
            isLocked     = $isLocked
            ownerAddress = $isLocked ? $session['Address'] : $null
            secondsLeft  = $secondsLeft
        }
    }
}

Add-PodeRoute -Method Get -Path '/api/qr' -ScriptBlock {
    $MAX_TEXT_LENGTH = 300

    $text = [System.String] $WebEvent.Query['text']
    if ([System.String]::IsNullOrEmpty($text) -OR $text.Length -GT $MAX_TEXT_LENGTH) {
        Write-TabulaRasaWebError -StatusCode 400 -Message "Query 'text' must have 1 to $MAX_TEXT_LENGTH characters."
        return
    }

    # The text goes to qrencode as one argument, never through a shell.
    $svg = qrencode --type=SVG --margin=1 --output=- -- $text
    if ($LASTEXITCODE -NE 0) {
        Write-TabulaRasaWebError -StatusCode 500 -Message "qrencode must render the QR code, got exit code $LASTEXITCODE."
        return
    }
    Write-PodeTextResponse -Value ($svg -join "`n") -ContentType 'image/svg+xml'
}
