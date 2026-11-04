# NOTE:
#   Requires: Linux, NetworkManager (nmcli) and /etc/tabula-rasa/hotspot.json.
#
#   Start-TabulaRasaWebHotspot -WaitSeconds 15

#
#   Chapters:
#     OPEN THE HOTSPOT   Waits for a Wi-Fi card and opens the hotspot, LAN stays the second way.
#

function Start-TabulaRasaWebHotspot {
    <#
    .SYNOPSIS
        Opens a Wi-Fi hotspot at boot, so a phone reaches the stick without any router.

    .DESCRIPTION
        Runs once at boot (tabula-rasa-hotspot.service). The hotspot is the first way in,
        LAN the second: NetworkManager brings up a LAN cable on its own, next to the hotspot.
        > A Wi-Fi card shows up within the wait time
            - Open the hotspot from /etc/tabula-rasa/hotspot.json (written at build time).
            - The phone joins it and opens http://10.42.0.1/ (NetworkManager's shared network).
        > No Wi-Fi card
            - Nothing to open, the phone reaches the stick through LAN and the router.

    .EXAMPLE
        PS> Start-TabulaRasaWebHotspot -WaitSeconds 15
    #>

    # Runs unattended at boot, there is no one to confirm. -WhatIf has no meaning here.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    param (
        <#
        [Optional]
        Seconds to wait for the Wi-Fi card, its driver and firmware load after boot. Default is 15.
        #>
        [Parameter(
            Mandatory = $false
        )]
        [ValidateRange(0, 600)]
        [System.Int32]
        $WaitSeconds = 15
    )

    $HOTSPOT_CONFIG_PATH     = '/etc/tabula-rasa/hotspot.json'
    $HOTSPOT_CONNECTION_NAME = 'TabulaRasaHotspot'
    $POLL_SECONDS            = 2

    # 'nmcli -t -f TYPE,STATE device' prints 'ethernet:connected', 'wifi:disconnected', ...
    $getWifiDevices = { @(nmcli -t -f TYPE,STATE device 2>$null | Where-Object { $_ -LIKE 'wifi:*' }) }

    # ===========================================================================
    # ==========================   OPEN THE HOTSPOT   ===========================
    # ===========================================================================
    #
    #   1. Wi-Fi card   Waits for a Wi-Fi card, without one LAN is the only way.
    #   2. Hotspot      Opens the hotspot, LAN keeps working next to it.
    #

    # ---------------------------------------------------------------------------
    # Wi-Fi card
    #   Waits for a Wi-Fi card, without one LAN is the only way.
    # ---------------------------------------------------------------------------

    $deadline = [System.DateTime]::UtcNow.AddSeconds($WaitSeconds)
    while ((& $getWifiDevices).Count -EQ 0 -AND [System.DateTime]::UtcNow -LT $deadline) {
        Start-Sleep -Seconds $POLL_SECONDS
    }
    if ((& $getWifiDevices).Count -EQ 0) {
        Write-Verbose "[Start-TabulaRasaWebHotspot] No Wi-Fi card after $WaitSeconds seconds -> LAN only."
        return
    }

    # ---------------------------------------------------------------------------
    # Hotspot
    #   Opens the hotspot, LAN keeps working next to it.
    # ---------------------------------------------------------------------------

    $Config = Get-Content -Path $HOTSPOT_CONFIG_PATH -Raw | ConvertFrom-Json
    Write-Verbose "[Start-TabulaRasaWebHotspot] Opening hotspot '$($Config.Ssid)', LAN stays available."
    nmcli device wifi hotspot con-name $HOTSPOT_CONNECTION_NAME ssid $Config.Ssid password $Config.Password
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("nmcli must open the hotspot '$($Config.Ssid)', got exit code $LASTEXITCODE. The Wi-Fi card may not support access point mode, LAN still works.")
    }
}
