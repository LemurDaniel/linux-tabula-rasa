# 📜 Linux Tabula Rasa
A bootable Linux live USB stick that securely wipes HDDs, SSDs, NVMe drives, USB sticks and SD cards.
Plug it in, boot, pick a disk on the screen or on your phone, confirm, done.

> **Status: scaffold.** Disk detection, the data views, the text menu and the web UI work, the wipe methods are not
> implemented yet and refuse to run.

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
| HDD | Overwrite with zeros (one pass) | ✅ |
| SATA SSD | ATA Secure Erase (`hdparm`) | ✅ |
| NVMe | NVMe Sanitize (`nvme-cli`) | ✅ |
| USB stick, SD card | Overwrite | ⚠️ the controller may keep blocks, destroy physically for sensitive data |

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
   - HDD, SSD, NVMe: type the serial number from the label.
   - USB stick, SD card: unplug it and plug it in again (their serial is rarely printed or real).

`Alt+F2` switches to the text menu, `Alt+F1` back to the kiosk. When the kiosk cannot start (no GPU),
the stick switches to the text menu on its own.

## Build
Requires Docker (Docker Desktop on Windows) with privileged containers.

```powershell
./build/Build-TabulaRasaIso.ps1
```

```powershell
./build/Build-TabulaRasaIso.ps1 -HotspotSsid 'Wiper' -HotspotPassword 'not-my-wifi-password'
```

The ISO lands in `out/`.

### Write a stick
Windows (elevated PowerShell 7):
```powershell
./build/Write-TabulaRasaStick.ps1 -FromRelease
```

Linux:
```bash
./build/write-tabula-rasa-stick.sh --from-release
```

| Source of the ISO | Windows | Linux |
| --- | --- | --- |
| Newest GitHub release, checked against `SHA256SUMS` | `-FromRelease` | `--from-release` |
| Build it now with Docker | `-Build` | `--build` |
| A file | `-IsoPath <file>` | `--iso <file>` |
| Newest ISO in `out/` | (default) | (default) |

Both list the USB disks, want the disk number or device path typed, write the ISO and read it back to verify.
The repository is private, so `-FromRelease` needs the [GitHub CLI](https://cli.github.com/) logged in (`gh auth login`).
Rufus (DD mode) or balenaEtcher work too.

### Releases
A tag `v*` builds the ISO on GitHub Actions and publishes it as release
(`linux-tabula-rasa-<tag>-amd64.iso` plus `SHA256SUMS`):

```bash
git tag v0.1.0 && git push --tags
```
The hotspot password is stored in plain text on the stick and shown on the kiosk, so pick one you use nowhere else.
GitHub Actions builds it too: run **Build ISO** manually or push a `v*` tag, the ISO is attached as artifact.

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
| `src/TabulaRasa/` | Core module: disk detection, data views, wipe methods, text menu, tests. |
| `src/TabulaRasaWeb/` | Pode server, REST API ([routes](src/TabulaRasaWeb/routes/README.md)), web UI (`public/`), tests. |
| `.github/workflows/build.iso.yaml` | Tests and ISO build on GitHub Actions. |
