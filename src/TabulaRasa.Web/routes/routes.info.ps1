# NOTE:
#   Loaded by Use-PodeRoutes in Start-TabulaRasaServer. All routes are public (no session).
#
#   GET  /api/info        Network (URLs, hotspot) and who holds the session.
#   GET  /api/qr?text=    The text as QR code (SVG), for the URLs and the hotspot login.
#   POST /api/console     Switches the screen to the text menu on tty2, from the kiosk only.
#   GET  /api/diagnostics Failed units and the logs of kiosk and server as plain text, for a phone
#                         when the screen stays black.
#   GET  /api/kiosk       Whether the kiosk browser has called the API, read by the kiosk watchdog.

#
#   Chapters:
#     INFO ROUTES   Reachability, QR codes and the way out to the text menu.
#

# ===========================================================================
# =============================   INFO ROUTES   =============================
# ===========================================================================
#
#   GET /api/info       Network, session owner and seconds until it is free.
#   GET /api/qr         Renders text as SVG QR code with qrencode.
#   POST /api/console   chvt 2 for the kiosk, cage does not always let Ctrl+Alt+F2 through.
#   GET /api/diagnostics   systemctl and journalctl output, read-only.
#   GET /api/kiosk         isSeen and the seconds since the last call of the kiosk browser.
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

Add-PodeRoute -Method Post -Path '/api/console' -ScriptBlock {
    $TEXT_MENU_TTY = 2

    # Only the kiosk on this machine may switch its own screen, a phone has nothing to switch.
    if (-NOT [System.Net.IPAddress]::IsLoopback($WebEvent.Request.RemoteEndPoint.Address)) {
        Write-TabulaRasaWebError -StatusCode 403 -Message 'The text menu can only be opened from the screen of the stick.'
        return
    }

    chvt $TEXT_MENU_TTY
    if ($LASTEXITCODE -NE 0) {
        Write-TabulaRasaWebError -StatusCode 500 -Message "chvt must switch to tty$TEXT_MENU_TTY, got exit code $LASTEXITCODE."
        return
    }
    Write-PodeJsonResponse -Value @{ tty = $TEXT_MENU_TTY }
}

Add-PodeRoute -Method Get -Path '/api/diagnostics' -ScriptBlock {
    # Title and command per block, every command only reads.
    $Blocks = [ordered]@{
        'Failed units'                  = { systemctl --failed --no-pager }
        'Kiosk (tabula-rasa-kiosk)'     = { journalctl -b -u tabula-rasa-kiosk -n 80 --no-pager }
        'Server (tabula-rasa-server)'   = { journalctl -b -u tabula-rasa-server -n 30 --no-pager }
        'Hotspot (tabula-rasa-hotspot)' = { journalctl -b -u tabula-rasa-hotspot -n 20 --no-pager }
        'Warnings and errors'           = { journalctl -b -p warning -n 80 --no-pager }
        'Graphics devices'              = { Get-ChildItem -Path /dev/dri -ErrorAction SilentlyContinue | ForEach-Object Name }
    }

    $report = foreach ($title in $Blocks.Keys) {
        "===== $title ====="
        & $Blocks[$title] 2>&1 | ForEach-Object { [System.String] $_ }
        ''
    }
    Write-PodeTextResponse -Value ($report -join "`n") -ContentType 'text/plain; charset=utf-8'
}

Add-PodeRoute -Method Get -Path '/api/kiosk' -ScriptBlock {
    $lastSeen = (Get-PodeState -Name 'Kiosk')['LastSeen']
    Write-PodeJsonResponse -Value @{
        isSeen      = $null -NE $lastSeen
        secondsAgo  = $null -EQ $lastSeen ? $null : [System.Math]::Round(([System.DateTime]::UtcNow - $lastSeen).TotalSeconds)
    }
}
