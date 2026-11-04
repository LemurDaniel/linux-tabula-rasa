# NOTE:
#   Requires: Linux, NetworkManager (nmcli) and /etc/tabula-rasa/hotspot.json.
#
#   Start-TabulaRasaWebHotspot -WaitSeconds 30

#
#   Chapters:
#     OPEN THE HOTSPOT   Waits for LAN, opens the hotspot only without it.
#

function Start-TabulaRasaWebHotspot {
    <#
    .SYNOPSIS
        Opens a Wi-Fi hotspot when no LAN cable is connected, so a phone can reach the stick anyway.

    .DESCRIPTION
        Runs once at boot (tabula-rasa-hotspot.service):
        > A LAN cable gets connected within the wait time
            - Do nothing, the phone reaches the stick through the router.
        > No LAN, but a Wi-Fi card
            - Open the hotspot from /etc/tabula-rasa/hotspot.json (written at build time).
        > Neither
            - Do nothing, the kiosk and the text menu still work locally.

    .EXAMPLE
        PS> Start-TabulaRasaWebHotspot -WaitSeconds 30
    #>

    # Runs unattended at boot, there is no one to confirm. -WhatIf has no meaning here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param (
        <#
        [Optional]
        Seconds to wait for a LAN connection before the hotspot opens. Default is 30.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [ValidateRange(0, 600)]
        [System.Int32]
        $WaitSeconds = 30
    )

    $HOTSPOT_CONFIG_PATH     = '/etc/tabula-rasa/hotspot.json'
    $HOTSPOT_CONNECTION_NAME = 'TabulaRasaHotspot'
    $POLL_SECONDS            = 2

    # 'nmcli -t -f TYPE,STATE device' prints 'ethernet:connected', 'wifi:disconnected', ...
    $getDeviceStates = { @(nmcli -t -f TYPE,STATE device 2>$null) }

    # ===========================================================================
    # ==========================   OPEN THE HOTSPOT   ===========================
    # ===========================================================================
    #
    #   1. LAN          A LAN cable gets connected within the wait time: no hotspot.
    #   2. Neither      No LAN and no Wi-Fi card: local use only.
    #   3. Wi-Fi card   No LAN, but a Wi-Fi card: open the hotspot.
    #

    # ---------------------------------------------------------------------------
    # LAN
    #   A LAN cable gets connected within the wait time: no hotspot.
    # ---------------------------------------------------------------------------

    $deadline = [System.DateTime]::UtcNow.AddSeconds($WaitSeconds)
    do {
        if ((& $getDeviceStates) -CONTAINS 'ethernet:connected') {
            Write-Verbose "[Start-TabulaRasaWebHotspot] LAN is connected -> no hotspot."
            return
        }
        Start-Sleep -Seconds $POLL_SECONDS
    } while ([System.DateTime]::UtcNow -LT $deadline)

    # ---------------------------------------------------------------------------
    # Neither
    #   No LAN and no Wi-Fi card: local use only.
    # ---------------------------------------------------------------------------

    if (@(& $getDeviceStates | Where-Object { $_ -LIKE 'wifi:*' }).Count -EQ 0) {
        Write-Verbose "[Start-TabulaRasaWebHotspot] No LAN and no Wi-Fi card -> local use only."
        return
    }

    # ---------------------------------------------------------------------------
    # Wi-Fi card
    #   No LAN, but a Wi-Fi card: open the hotspot.
    # ---------------------------------------------------------------------------

    $Config = Get-Content -Path $HOTSPOT_CONFIG_PATH -Raw | ConvertFrom-Json
    Write-Verbose "[Start-TabulaRasaWebHotspot] No LAN after $WaitSeconds seconds -> opening hotspot '$($Config.Ssid)'."
    nmcli device wifi hotspot con-name $HOTSPOT_CONNECTION_NAME ssid $Config.Ssid password $Config.Password
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("nmcli must open the hotspot '$($Config.Ssid)', got exit code $LASTEXITCODE. The Wi-Fi card may not support access point mode.")
    }
}
