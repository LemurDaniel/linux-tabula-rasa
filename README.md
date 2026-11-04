# 📜 Linux Tabula Rasa
A bootable Linux live USB stick that securely wipes HDDs, SSDs, NVMe drives, USB sticks and SD cards.
Plug it in, boot, pick a disk on the screen or on your phone, confirm, done.

> **Status: early.** Everything works end to end on test images. Overwrite is tested on real block devices,
> ATA Secure Erase and NVMe Sanitize are implemented but not yet tested on real drives.

> **🤖 AI notice:** Large parts of this project were written with the help of AI ([Claude Code](https://claude.com/claude-code) by Anthropic).
> The code is tested (Pester, PSScriptAnalyzer, end-to-end runs on loop devices), but AI can make mistakes.
> This tool deletes data for good: read the code and try it on a disk you do not need before you trust it with anything.
> Provided as is, without warranty.

## Why
A quick format only rewrites the file system, the data stays on the disk and tools like PhotoRec bring it back.
And overwriting does not reach every block of an SSD, its controller keeps spare and remapped blocks.
Each kind of disk needs its own method:

| Kind | Method | Complete |
| --- | --- | --- |
| HDD | Overwrite with zeros (one pass), then every sample must read zero | ✅ |
| SATA SSD | ATA Secure Erase (`hdparm`), enhanced when supported; a frozen drive is unfrozen by a 5 s suspend | ✅ |
| NVMe | NVMe Sanitize (`nvme-cli`): crypto erase > block erase > overwrite, else Format with Secure Erase | ✅ |
| USB stick, SD card | Overwrite | ⚠️ the controller may keep blocks, destroy physically for sensitive data |

Before every wipe the stick refuses its own disk and any disk mounted outside Tabula Rasa.
An NVMe controller with more than one namespace is refused, Sanitize would erase all of them.
If an ATA Secure Erase fails, the temporary password `TabulaRasa` is removed again, so the drive never stays locked.

## Getting started
You need a USB stick of at least 2 GB, everything on it gets erased.
The stick scripts only offer USB disks (never the boot or system disk), want the disk number or device path
typed before they erase anything and read the stick back after writing to verify it.

| Variant | You need |
| --- | --- |
| [1. Flash from release](#1-flash-from-release) | Nothing extra, just an internet connection |
| [2. Flash from build](#2-flash-from-build) | An ISO you already have: built earlier, or downloaded from a GitHub Actions run |
| [3. Build and flash it yourself](#3-build-and-flash-it-yourself) | Docker (Docker Desktop on Windows) with privileged containers |

On Windows the stick script needs an elevated PowerShell 7 (Run as administrator), on Linux it asks for `sudo`.

### 1. Flash from release
Downloads the ISO of the newest GitHub release into `out/`, checks it against `SHA256SUMS` and writes it.

Windows:
```powershell
./build/Write-TabulaRasaStick.ps1 -FromRelease
```

Linux:
```bash
./build/write-tabula-rasa-stick.sh --from-release
```

The scripts use the [GitHub CLI](https://cli.github.com/) when it is installed, else the public GitHub API.
A release of another repository (a fork): `-Repository owner/name` or `--repository owner/name`.
Prefer your own tool? Download the ISO from the [latest release](https://github.com/LemurDaniel/linux-tabula-rasa/releases/latest)
and continue with [Flash from build](#2-flash-from-build).

### 2. Flash from build
Writes an ISO that already exists. Without a path the scripts take the newest ISO in `out/`.

Windows:
```powershell
./build/Write-TabulaRasaStick.ps1
./build/Write-TabulaRasaStick.ps1 -IsoPath C:\Downloads\linux-tabula-rasa-amd64.hybrid.iso
```

Linux:
```bash
./build/write-tabula-rasa-stick.sh
./build/write-tabula-rasa-stick.sh --iso ~/Downloads/linux-tabula-rasa-amd64.hybrid.iso
```

An ISO from GitHub Actions: run **Build ISO** in the Actions tab, download the artifact `linux-tabula-rasa-iso`
and pass the ISO inside. Rufus (DD mode) or balenaEtcher write it too, without the read-back check.

### 3. Build and flash it yourself
Builds the ISO with live-build in Docker (20 to 40 minutes the first time), then writes it.

Windows:
```powershell
./build/Write-TabulaRasaStick.ps1 -Build
```

Linux:
```bash
./build/write-tabula-rasa-stick.sh --build
```

With your own hotspot (used when the stick finds no LAN):
```powershell
./build/Write-TabulaRasaStick.ps1 -Build -HotspotSsid 'Wiper' -HotspotPassword 'not-my-wifi-password'
```

Only the ISO, without a stick:
```powershell
./build/Build-TabulaRasaIso.ps1
```

The hotspot password is stored in plain text on the stick and shown on the kiosk, so pick one you use nowhere else.

### Options at a glance
| | Windows | Linux |
| --- | --- | --- |
| Newest GitHub release | `-FromRelease` | `--from-release` |
| Repository of the release | `-Repository owner/name` | `--repository owner/name` |
| Build first | `-Build` | `--build` |
| A specific ISO | `-IsoPath <file>` | `--iso <file>` |
| The stick, without the question | `-DiskNumber <n>` | `--device /dev/sdX` |
| Disks over 256 GB | `-Force` | `--force` |
| No read-back check | `-SkipVerify` | `--skip-verify` |
| Hotspot of the build | `-HotspotSsid`, `-HotspotPassword` | `--hotspot-ssid`, `--hotspot-password` |
| Only show what would happen | `-WhatIf` | |

## How it works
```
tty1   Kiosk: cage + Chromium  ──►  http://localhost  ──┐
Phone  ── LAN / hotspot ──►  http://tabula-rasa.local  ─┤
                                                        ▼
                               Pode web server (pwsh, port 80)
                                                        │
                               TabulaRasa module (detect, inspect, wipe)
tty2   Text menu (PwshSpectreConsole), also the fallback without a GPU
```

1. The stick boots Debian trixie (UEFI with Secure Boot, or BIOS).
2. The screen shows the web UI with QR codes for the phone. The stick announces itself as `tabula-rasa.local` (mDNS).
   Without a LAN cable it opens the Wi-Fi hotspot `TabulaRasa` after 30 seconds.
3. One device controls the stick at a time: the first one that taps **Start**. The kiosk can always take over,
   an idle session is free again after 5 minutes.
4. Every disk except the stick itself is listed. Picking one shows what is still on it, all read-only:

   | View | Shows | How |
   | --- | --- | --- |
   | Overview | Partitions, used space, sampled blocks, quick file header estimate | lsblk, read-only mount, 16 MiB of samples |
   | Files | Folders and files of a partition | `mount -o ro` on a read-only block device |
   | Deleted | Files the file system marks deleted but still holds | sleuthkit (`fls`) |
   | Deep scan | File headers (JPEG, PDF, ZIP, ...) on the whole disk, also after a quick format | Signature scan, ~1.4 GB/s |

5. The wipe only starts after a confirmation of exactly that disk. Nothing is ever wiped automatically:
   - HDD, SSD, NVMe: model, size and serial are shown, you confirm them (no need to open the case for the label).
     A disk swapped in the meantime under the same name is refused.
   - USB stick, SD card: unplug it and plug it in again (their serial is rarely printed or real).

| Screen | How to get there |
| --- | --- |
| Kiosk (tty1) | Starts by itself, `Ctrl+Alt+F1` from the consoles |
| Text menu (tty2) | `Ctrl+Alt+F2`, or the button **Text menu** on the kiosk start screen |
| Root shell (tty3) | `Ctrl+Alt+F3` |

When the kiosk crashes three times, the stick switches to the text menu on its own.
When the screen stays black, open `http://tabula-rasa.local/api/diagnostics` on a phone: failed services and
the logs of kiosk and server, no keyboard needed.

## Releases
A tag `v*` builds the ISO on GitHub Actions and publishes it as release
(`linux-tabula-rasa-<tag>-amd64.iso` plus `SHA256SUMS`), which [Flash from release](#1-flash-from-release) picks up:

```bash
git tag v0.1.0 && git push --tags
```

## Test
```powershell
'./src', './build' | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Recurse -Severity Warning, Error }
Invoke-Pester -Path ./src
```

## Layout
| Path | Content |
| --- | --- |
| `build/` | Builder image and build script, see [build/README.md](build/README.md). |
| `live/` | live-build config of the image, see [live/README.md](live/README.md). |
| `src/TabulaRasa/` | Core module: disk detection, data views, wipe methods, text menu. |
| `src/TabulaRasa.Tests/` | Pester tests of the core module. |
| `src/TabulaRasa.Web/` | Pode server, REST API ([routes](src/TabulaRasa.Web/routes/README.md)), web UI (`public/`). |
| `src/TabulaRasa.Web.Tests/` | Pester tests of the server logic. |
| `.github/workflows/build.iso.yaml` | Tests and ISO build on GitHub Actions. |
