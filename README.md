# 📜 Linux Tabula Rasa
A bootable Linux live USB stick that securely wipes HDDs, SSDs, NVMe drives, USB sticks and SD cards.
Plug it in, boot, pick a disk, confirm, done.

> **Status: scaffold.** Disk detection, the data views and the text menu work, the wipe methods are not
> implemented yet and refuse to run. A web UI for phone access is planned.

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
1. The stick boots Debian trixie (UEFI with Secure Boot, or BIOS) and logs root in on tty1.
2. The menu (`src/TabulaRasa`, PowerShell 7 with PwshSpectreConsole) lists every disk except the stick itself.
3. Picking a disk shows what is still on it, all read-only:

   | View | Shows | How |
   | --- | --- | --- |
   | Overview | Partitions, used space, sampled blocks, quick file header estimate | lsblk, read-only mount, 16 MiB of samples |
   | Browse files | Folders and files of a partition | `mount -o ro` on a read-only block device |
   | Deleted files | Files the file system marks deleted but still holds | sleuthkit (`fls`) |
   | Deep scan | File headers (JPEG, PDF, ZIP, ...) on the whole disk, also after a quick format | Signature scan, ~1.4 GB/s |

4. The wipe only starts after a confirmation of exactly that disk. Nothing is ever wiped automatically:
   - HDD, SSD, NVMe: type the serial number from the label.
   - USB stick, SD card: unplug it and plug it in again (their serial is rarely printed or real).

`Alt+F2` opens a plain root shell next to the menu.

## Build
Requires Docker (Docker Desktop on Windows) with privileged containers.

```powershell
./build/Build-TabulaRasaIso.ps1
```

The ISO lands in `out/`. Write it to a USB stick with Rufus (DD mode), balenaEtcher or `dd`.
GitHub Actions builds it too: run **Build ISO** manually or push a `v*` tag, the ISO is attached as artifact.

## Test
```powershell
'./src', './build' | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Recurse -Severity Warning, Error }
Invoke-Pester -Path ./src/TabulaRasa/tests
```

## Layout
| Path | Content |
| --- | --- |
| `build/` | Builder image and build script, see [build/README.md](build/README.md). |
| `live/` | live-build config of the image, see [live/README.md](live/README.md). |
| `src/TabulaRasa/` | The menu module: disk detection, data check, wipe methods, tests. |
| `.github/workflows/build.iso.yaml` | Tests and ISO build on GitHub Actions. |
