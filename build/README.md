# Build
| File | Content |
| --- | --- |
| `Build-TabulaRasaIso.ps1` | Entry point: builds the builder image and the ISO into `out/`. |
| `Write-TabulaRasaStick.ps1` | Windows: takes the newest release, a fresh build or a file, writes it onto a USB stick and verifies it (elevated shell). |
| `write-tabula-rasa-stick.sh` | Linux: the same in bash, writes with `dd` and verifies with `cmp`. |
| `Dockerfile` | Debian trixie with live-build, copies `live/` and the modules into a build tree. |

Both stick scripts only offer USB disks (never the boot or system disk), refuse disks over 256 GB
without `-Force` / `--force` and want the disk number or device path typed before they erase anything.
