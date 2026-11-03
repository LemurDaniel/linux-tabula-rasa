# NOTE:
#   Requires: Linux with iproute2 (ip -j), NetworkManager (nmcli) only for the hotspot state.
#
#   (Get-TabulaRasaWebNetwork).Urls

#
#   Chapters:
#     COLLECT REACHABILITY   Addresses, URLs and the hotspot of the stick.
#

function Get-TabulaRasaWebNetwork {
    <#
    .SYNOPSIS
        Returns how the web UI can be reached: host name, URLs and the hotspot.

    .DESCRIPTION
        The kiosk shows these URLs (and QR codes of them) so a phone finds the stick:
        - http://<hostname>.local/   via mDNS (avahi), works on iOS and recent Android
        - http://<ip>/               one per IPv4 address, the fallback without mDNS
        Hotspot holds SSID and password from Start-TabulaRasaWebHotspot and whether it runs.

    .EXAMPLE
        PS> Get-TabulaRasaWebNetwork
    #>

    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param ()

    $HOTSPOT_CONFIG_PATH     = '/etc/tabula-rasa/hotspot.json'
    $HOTSPOT_CONNECTION_NAME = 'TabulaRasaHotspot'

    # ===========================================================================
    # ========================   COLLECT REACHABILITY   =========================
    # ===========================================================================
    #
    #   1. Addresses   IPv4 addresses without loopback and the URLs built from them.
    #   2. Hotspot     SSID and password from the config, whether the hotspot runs.
    #   3. Result      Returns host name, addresses, URLs and the hotspot.
    #

    # ---------------------------------------------------------------------------
    # Addresses
    #   IPv4 addresses without loopback and the URLs built from them.
    # ---------------------------------------------------------------------------

    # 'ip -j' prints one object per interface with its addresses.
    # [{"ifname":"lo","addr_info":[{"local":"127.0.0.1"}]},{"ifname":"enp3s0","addr_info":[{"local":"192.168.1.42"}]}]
    # => 192.168.1.42
    $Addresses = @(ip -j -4 address show | ConvertFrom-Json)
    | Where-Object -Property ifname -NE -Value 'lo'
    | ForEach-Object { $_.addr_info.local }

    $Hostname = [System.Net.Dns]::GetHostName()
    $Urls     = @("http://$Hostname.local/") + @($Addresses | ForEach-Object { "http://$_/" })

    # ---------------------------------------------------------------------------
    # Hotspot
    #   SSID and password from the config, whether the hotspot runs.
    # ---------------------------------------------------------------------------

    $hotspotConfig = (Test-Path -Path $HOTSPOT_CONFIG_PATH) ? (Get-Content -Path $HOTSPOT_CONFIG_PATH -Raw | ConvertFrom-Json) : $null
    # Without NetworkManager (a test container) there is no hotspot, instead of an error.
    $activeNames   = $null -NE (Get-Command -Name nmcli -ErrorAction SilentlyContinue) ? @(nmcli -t -f NAME connection show --active 2>$null) : @()

    # ---------------------------------------------------------------------------
    # Result
    #   Returns host name, addresses, URLs and the hotspot.
    # ---------------------------------------------------------------------------

    return [PSCustomObject]@{
        Hostname  = $Hostname
        Addresses = @($Addresses)
        Urls      = $Urls
        Hotspot   = [PSCustomObject]@{
            IsActive = $activeNames -CONTAINS $HOTSPOT_CONNECTION_NAME
            # Braces: '$hotspotConfig?' would be read as a variable named 'hotspotConfig?'.
            Ssid     = ${hotspotConfig}?.Ssid
            Password = ${hotspotConfig}?.Password
        }
    }
}
