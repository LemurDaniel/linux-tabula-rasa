# live-build config
The folder layout is the one live-build expects, the Dockerfile copies it as build tree.

| Path | Content |
| --- | --- |
| `auto/config` | `lb config` options: Debian trixie, amd64, hybrid ISO, Secure Boot, host name, boot parameters. |
| `config/package-lists/tabula-rasa.list.chroot` | Packages: wipe tools, sleuthkit, kiosk, NetworkManager, avahi, firmware, PowerShell runtime. |
| `config/hooks/live/0100-install-pwsh.hook.chroot` | Installs pwsh (hash checked), PwshSpectreConsole and Pode inside the chroot. |
| `config/hooks/live/0200-setup-services.hook.chroot` | Creates the `kiosk` user and enables the services. |
| `config/includes.chroot/etc/systemd/system/tabula-rasa-server.service` | Pode web server on port 80 (root). |
| `config/includes.chroot/etc/systemd/system/tabula-rasa-kiosk.service` | cage + Chromium on tty1 (user `kiosk`). |
| `config/includes.chroot/etc/systemd/system/tabula-rasa-fallback.service` | Switches to tty2 when the kiosk fails three times. |
| `config/includes.chroot/etc/systemd/system/tabula-rasa-hotspot.service` | Opens the Wi-Fi hotspot at boot, LAN works next to it. |
| `config/includes.chroot/etc/systemd/system/getty@tty2.service.d/override.conf` | Autologin of root on tty2. |
| `config/includes.chroot/etc/systemd/system/getty@tty3.service.d/override.conf` | Autologin of root on tty3, a plain shell. |
| `config/includes.chroot/root/.bash_profile` | Starts the text menu on tty2. |

Copied in at build time by the Dockerfile:
- `src/TabulaRasa` and `src/TabulaRasa.Web` to `/opt/tabula-rasa/` (their tests live in the `*.Tests` folders next to them and stay out).
- `hotspot.json` (from `Build-TabulaRasaIso.ps1 -HotspotSsid/-HotspotPassword`) to `/etc/tabula-rasa/`.
