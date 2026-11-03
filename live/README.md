# live-build config
The folder layout is the one live-build expects, the Dockerfile copies it as build tree.

| Path | Content |
| --- | --- |
| `auto/config` | `lb config` options: Debian trixie, amd64, hybrid ISO, Secure Boot, boot parameters. |
| `config/package-lists/tabula-rasa.list.chroot` | Packages of the live system: wipe tools, PowerShell runtime, console. |
| `config/hooks/live/0100-install-pwsh.hook.chroot` | Installs pwsh (hash checked) and PwshSpectreConsole inside the chroot. |
| `config/includes.chroot/etc/systemd/system/getty@tty1.service.d/override.conf` | Autologin of root on tty1. |
| `config/includes.chroot/root/.bash_profile` | Starts the menu on tty1. |

The menu module (`src/TabulaRasa`) is copied to `config/includes.chroot/opt/tabula-rasa/` at build time.
