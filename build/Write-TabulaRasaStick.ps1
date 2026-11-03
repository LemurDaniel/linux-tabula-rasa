# NOTE:
#   Requires: Windows, an elevated PowerShell 7 (Run as administrator).
#             Docker for -Build, the GitHub CLI (gh, logged in) for -FromRelease of a private repository.
#   Erases the selected USB stick completely and writes the Linux Tabula Rasa ISO onto it.
#   Linux: use write-tabula-rasa-stick.sh next to this script.
#
#   ./build/Write-TabulaRasaStick.ps1 -FromRelease            # newest GitHub release, then pick a stick
#   ./build/Write-TabulaRasaStick.ps1 -Build                  # build the ISO, then pick a stick
#   ./build/Write-TabulaRasaStick.ps1                         # newest ISO in out/, then pick a stick
#   ./build/Write-TabulaRasaStick.ps1 -DiskNumber 3 -WhatIf   # shows what would happen

#
#   Chapters:
#     HELPERS          Admin check, release download, the USB disk list and the raw copy.
#     PREPARE          Validations, the ISO (downloaded, built or found) and the target stick.
#     WRITE AND CHECK  Typed confirmation, erase, raw write and read-back check.
#

# Interactive script: the messages are for the person at the keyboard, not for a pipeline.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
# The hotspot password ends up in plain text in hotspot.json on the stick by design (the kiosk shows it).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'HotspotPassword')]
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param (
    <#
    [Optional]
    Downloads the ISO of the newest GitHub release into 'out' and checks it against SHA256SUMS.
    Cannot be combined with -Build or -IsoPath.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.Management.Automation.SwitchParameter]
    $FromRelease,

    <#
    [Optional]
    The GitHub repository of -FromRelease as 'owner/name'. Default is 'LemurDaniel/linux-tabula-rasa'.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidatePattern('^[\w.-]+/[\w.-]+$')]
    [System.String]
    $Repository = 'LemurDaniel/linux-tabula-rasa',

    <#
    [Optional]
    Builds the ISO with Build-TabulaRasaIso.ps1 first. Without it the newest ISO in 'out' is used.
    Cannot be combined with -FromRelease or -IsoPath.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.Management.Automation.SwitchParameter]
    $Build,

    <#
    [Optional]
    The ISO to write. Default is the newest *.iso in 'out' of the repository.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $IsoPath = '',

    <#
    [Optional]
    The Windows disk number of the stick (Get-Disk). Without it the script lists the USB disks and asks.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateRange(0, 255)]
    [System.Int32]
    $DiskNumber = -1,

    <#
    [Optional]
    Allows disks larger than 256 GB, which are usually external hard drives rather than sticks.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.Management.Automation.SwitchParameter]
    $Force,

    <#
    [Optional]
    Skips reading the stick back after the write.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.Management.Automation.SwitchParameter]
    $SkipVerify,

    <#
    [Optional]
    Passed to Build-TabulaRasaIso.ps1 with -Build. Default is 'TabulaRasa'.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateLength(1, 32)]
    [System.String]
    $HotspotSsid = 'TabulaRasa',

    <#
    [Optional]
    Passed to Build-TabulaRasaIso.ps1 with -Build, 8 to 63 characters. Default is 'tabularasa'.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateLength(8, 63)]
    [System.String]
    $HotspotPassword = 'tabularasa'
)

Set-StrictMode -Version 1.0
$ErrorActionPreference = 'Stop'

$MAX_STICK_BYTES = 256GB
$CHUNK_BYTES     = 4MB
$OUT_PATH        = Join-Path -Path $PSScriptRoot -ChildPath '../out'

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   Test-IsAdministrator   Whether the shell runs elevated.
#   Save-ReleaseIso        Downloads the newest release ISO and checks its checksum.
#   Get-UsbDisk            USB disks that are neither boot nor system disk.
#   Copy-RawImage          Copies a file sector-aligned onto a raw device (or a file).
#   Test-RawImage          Reads the device back and compares it with the file.
#

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    return ([System.Security.Principal.WindowsPrincipal] $identity).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

<#
.SYNOPSIS
    Downloads the ISO and SHA256SUMS of the newest release and returns the checked ISO.

.DESCRIPTION
    > gh is installed   Downloads with the GitHub CLI, works for private repositories when logged in.
    > otherwise         Uses the public API, works only while the repository is public.
    Throws when the ISO does not match its line in SHA256SUMS.
#>
function Save-ReleaseIso {
    param (
        [System.String] $Repository,
        [System.String] $Destination
    )

    $null = New-Item -ItemType Directory -Path $Destination -Force

    # gh is installed
    if ($null -NE (Get-Command -Name gh -ErrorAction SilentlyContinue)) {
        Write-Verbose "[Write-TabulaRasaStick] Downloading the newest release of '$Repository' with gh."
        gh release download --repo $Repository --pattern '*.iso' --pattern 'SHA256SUMS' --dir $Destination --clobber
        if ($LASTEXITCODE -NE 0) {
            throw [System.InvalidOperationException]::new("gh must download the newest release of '$Repository', got exit code $LASTEXITCODE. Is there a release, and is gh logged in (gh auth login)?")
        }
    }
    # otherwise
    else {
        Write-Verbose "[Write-TabulaRasaStick] gh not found, downloading the newest release of '$Repository' via the public API."
        try {
            $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest"
        }
        catch [Microsoft.PowerShell.Commands.HttpResponseException] {
            throw [System.InvalidOperationException]::new("The newest release of '$Repository' must be reachable. A private repository needs the GitHub CLI (gh) logged in.", $_.Exception)
        }
        foreach ($asset in $release.assets | Where-Object { $_.name -LIKE '*.iso' -OR $_.name -EQ 'SHA256SUMS' }) {
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile (Join-Path -Path $Destination -ChildPath $asset.name)
        }
    }

    # Checksum: SHA256SUMS holds '<hash>  <file>' lines, the ISO's line must match its hash.
    $sumsPath = Join-Path -Path $Destination -ChildPath 'SHA256SUMS'
    $sumLine  = Get-Content -Path $sumsPath | Where-Object { $_ -MATCH '\.iso$' } | Select-Object -First 1
    if ($null -EQ $sumLine) {
        throw [System.IO.InvalidDataException]::new("SHA256SUMS of '$Repository' must list the ISO.")
    }
    $expectedHash, $isoName = $sumLine -split '\s+\*?', 2
    $isoPath    = Join-Path -Path $Destination -ChildPath $isoName
    $actualHash = (Get-FileHash -Path $isoPath -Algorithm SHA256).Hash

    if ($actualHash -NE $expectedHash) {
        throw [System.IO.InvalidDataException]::new("'$isoName' must match SHA256SUMS ($expectedHash), got $actualHash. Download it again.")
    }
    Write-Verbose "[Write-TabulaRasaStick] '$isoName' matches SHA256SUMS."
    return $isoPath
}

function Get-UsbDisk {
    return Get-Disk
    | Where-Object { $_.BusType -EQ 'USB' -AND -NOT $_.IsBoot -AND -NOT $_.IsSystem }
    | Sort-Object -Property Number
}

<#
.SYNOPSIS
    Copies a file onto a raw device in chunks that are multiples of the sector size.

.DESCRIPTION
    Raw disks on Windows only accept writes in whole sectors, so the last chunk is padded with
    zeros up to the next sector. Works with a plain file as target too, which is how it is tested.
#>
function Copy-RawImage {
    param (
        [System.String] $Source,
        [System.String] $Target,
        [System.Int32] $SectorSize
    )

    $sourceStream = [System.IO.File]::OpenRead($Source)
    $targetStream = [System.IO.FileStream]::new($Target, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite, 1, [System.IO.FileOptions]::WriteThrough)
    try {
        $buffer  = [System.Byte[]]::new($CHUNK_BYTES)
        $total   = $sourceStream.Length
        $written = [System.Int64] 0

        while (($readCount = $sourceStream.Read($buffer, 0, $CHUNK_BYTES)) -GT 0) {
            # Pads the last chunk to whole sectors, the padding bytes are zero.
            $writeCount = [System.Math]::Ceiling($readCount / $SectorSize) * $SectorSize
            if ($writeCount -GT $readCount) {
                [System.Array]::Clear($buffer, $readCount, $writeCount - $readCount)
            }
            $targetStream.Write($buffer, 0, $writeCount)
            $written += $readCount
            Write-Progress -Activity 'Writing stick' -Status "$([System.Math]::Floor($written / 1MB)) of $([System.Math]::Floor($total / 1MB)) MB" -PercentComplete (100 * $written / $total)
        }
        $targetStream.Flush($true)
    }
    finally {
        Write-Progress -Activity 'Writing stick' -Completed
        $sourceStream.Dispose()
        $targetStream.Dispose()
    }
}

<#
.SYNOPSIS
    Reads the first file-length bytes back from the device and compares them chunk by chunk.
#>
function Test-RawImage {
    param (
        [System.String] $Source,
        [System.String] $Target,
        [System.Int32] $SectorSize
    )

    $sourceStream = [System.IO.File]::OpenRead($Source)
    $targetStream = [System.IO.FileStream]::new($Target, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite, 1)
    try {
        $expected = [System.Byte[]]::new($CHUNK_BYTES)
        $actual   = [System.Byte[]]::new($CHUNK_BYTES)
        $total    = $sourceStream.Length
        $checked  = [System.Int64] 0

        while (($readCount = $sourceStream.Read($expected, 0, $CHUNK_BYTES)) -GT 0) {
            # The device is read in whole sectors as well. Beyond the file's part both buffers are
            # zeroed, so whole arrays can be compared (the fast path of SequenceEqual).
            $deviceCount = [System.Math]::Ceiling($readCount / $SectorSize) * $SectorSize
            $null = $targetStream.Read($actual, 0, $deviceCount)
            if ($readCount -LT $CHUNK_BYTES) {
                [System.Array]::Clear($expected, $readCount, $CHUNK_BYTES - $readCount)
                [System.Array]::Clear($actual, $readCount, $CHUNK_BYTES - $readCount)
            }
            if (-NOT [System.Linq.Enumerable]::SequenceEqual($expected, $actual)) {
                return $false
            }
            $checked += $readCount
            Write-Progress -Activity 'Checking stick' -Status "$([System.Math]::Floor($checked / 1MB)) of $([System.Math]::Floor($total / 1MB)) MB" -PercentComplete (100 * $checked / $total)
        }
        return $true
    }
    finally {
        Write-Progress -Activity 'Checking stick' -Completed
        $sourceStream.Dispose()
        $targetStream.Dispose()
    }
}

# ===========================================================================
# ===============================   PREPARE   ===============================
# ===========================================================================
#
#   1. Validations   Windows, an elevated shell and one ISO source at most.
#   2. ISO           Downloads, builds or finds the ISO.
#   3. Stick         Picks the USB disk and checks it may be erased.
#

# ---------------------------------------------------------------------------
# Validations
#   Windows, an elevated shell and one ISO source at most.
# ---------------------------------------------------------------------------

if (-NOT $IsWindows) {
    throw [System.PlatformNotSupportedException]::new('This script needs Windows, on Linux use build/write-tabula-rasa-stick.sh.')
}
if (-NOT (Test-IsAdministrator)) {
    throw [System.UnauthorizedAccessException]::new('Writing a raw disk needs an elevated PowerShell (Run as administrator).')
}
$SourceCount = (@($FromRelease.IsPresent, $Build.IsPresent, -NOT [System.String]::IsNullOrEmpty($IsoPath)) -EQ $true).Count
if ($SourceCount -GT 1) {
    throw [System.ArgumentException]::new('-FromRelease, -Build and -IsoPath must not be combined, pick one source for the ISO.')
}

# ---------------------------------------------------------------------------
# ISO
#   Downloads, builds or finds the ISO.
# ---------------------------------------------------------------------------

# > -FromRelease or -Build with -WhatIf   Skips them: -WhatIf would reach New-Item inside and break them.
# > -FromRelease                          Downloads the newest release and checks its checksum.
# > -Build                                Builds and takes the new ISO.
# > -IsoPath                              Takes that file.
# > otherwise                             Takes the newest ISO in out/.
$isWhatIfSkip = ($FromRelease -OR $Build) -AND $WhatIfPreference
if ($isWhatIfSkip) {
    Write-Host 'What if: Downloading or building the ISO (skipped, using the newest existing ISO in out/).'
}
elseif ($FromRelease) {
    $IsoPath = Save-ReleaseIso -Repository $Repository -Destination $OUT_PATH
}
elseif ($Build) {
    $BuildConfig = @{
        OutputPath      = $OUT_PATH
        HotspotSsid     = $HotspotSsid
        HotspotPassword = $HotspotPassword
    }
    $IsoPath = (& (Join-Path -Path $PSScriptRoot -ChildPath 'Build-TabulaRasaIso.ps1') @BuildConfig).FullName
}

if ([System.String]::IsNullOrEmpty($IsoPath)) {
    $IsoPath = Get-ChildItem -Path $OUT_PATH -Filter '*.iso' -ErrorAction SilentlyContinue
    | Sort-Object -Property LastWriteTime -Descending
    | Select-Object -First 1 -ExpandProperty FullName
}

if ([System.String]::IsNullOrEmpty($IsoPath) -OR -NOT (Test-Path -Path $IsoPath -PathType Leaf)) {
    throw [System.IO.FileNotFoundException]::new("An ISO must exist: use -FromRelease, -Build or -IsoPath. Looked in '$OUT_PATH'.")
}
$Iso = Get-Item -Path $IsoPath
Write-Host "ISO: $($Iso.FullName) ($([System.Math]::Round($Iso.Length / 1MB)) MB)"

# ---------------------------------------------------------------------------
# Stick
#   Picks the USB disk and checks it may be erased.
# ---------------------------------------------------------------------------

$UsbDisks = @(Get-UsbDisk)
if ($UsbDisks.Count -EQ 0) {
    throw [System.InvalidOperationException]::new('No USB disk found. Plug in the stick and run the script again.')
}

if ($DiskNumber -LT 0) {
    $UsbDisks
    | Format-Table -Property Number, FriendlyName, @{ Name = 'Size (GB)'; Expression = { [System.Math]::Round($_.Size / 1GB, 1) } }, PartitionStyle
    | Out-Host
    $DiskNumber = [System.Int32] (Read-Host -Prompt 'Disk number of the stick')
}

$Disk = $UsbDisks | Where-Object -Property Number -EQ -Value $DiskNumber
if ($null -EQ $Disk) {
    throw [System.ArgumentException]::new("Disk $DiskNumber must be a USB disk that is neither boot nor system disk. USB disks: $($UsbDisks.Number -join ', ').")
}
if ($Disk.Size -GT $MAX_STICK_BYTES -AND -NOT $Force) {
    throw [System.ArgumentException]::new("Disk $DiskNumber has $([System.Math]::Round($Disk.Size / 1GB)) GB, more than 256 GB looks like an external drive. Add -Force if it really is the stick.")
}
if ($Disk.Size -LT $Iso.Length) {
    throw [System.ArgumentException]::new("Disk $DiskNumber must hold at least $([System.Math]::Round($Iso.Length / 1MB)) MB, it has $([System.Math]::Round($Disk.Size / 1MB)) MB.")
}

# ===========================================================================
# ===========================   WRITE AND CHECK   ===========================
# ===========================================================================
#
#   1. Confirm   Shows the disk and wants its number typed (skipped by -WhatIf).
#   2. Write     Erases the partition table and writes the ISO raw.
#   3. Check     Reads the stick back and compares it with the ISO.
#

# ---------------------------------------------------------------------------
# Confirm
#   Shows the disk and wants its number typed (skipped by -WhatIf).
# ---------------------------------------------------------------------------

$Description = "disk $($Disk.Number): $($Disk.FriendlyName), $([System.Math]::Round($Disk.Size / 1GB, 1)) GB"
if (-NOT $PSCmdlet.ShouldProcess($Description, 'Erase completely and write the Tabula Rasa ISO')) {
    return
}

Write-Host "Everything on $Description will be lost." -ForegroundColor Red
$answer = Read-Host -Prompt "Type the disk number ($($Disk.Number)) to continue"
if ($answer -NE [System.String] $Disk.Number) {
    Write-Host 'Cancelled, nothing was written.'
    return
}

# ---------------------------------------------------------------------------
# Write
#   Erases the partition table and writes the ISO raw.
# ---------------------------------------------------------------------------

# Without partitions Windows holds no volume on the stick, so the raw write is not blocked.
# A RAW disk has nothing to clear (Clear-Disk would fail on it).
if ($Disk.PartitionStyle -NE 'RAW') {
    Write-Verbose "[Write-TabulaRasaStick] Clearing disk $($Disk.Number) ($($Disk.PartitionStyle))."
    Clear-Disk -Number $Disk.Number -RemoveData -RemoveOEM -Confirm:$false
}
$Device = "\\.\PhysicalDrive$($Disk.Number)"

Write-Verbose "[Write-TabulaRasaStick] Writing '$($Iso.FullName)' to '$Device'."
Copy-RawImage -Source $Iso.FullName -Target $Device -SectorSize $Disk.LogicalSectorSize
Update-Disk -Number $Disk.Number

# ---------------------------------------------------------------------------
# Check
#   Reads the stick back and compares it with the ISO.
# ---------------------------------------------------------------------------

if ($SkipVerify) {
    Write-Host "Done, the stick is ready (not verified)." -ForegroundColor Green
    return
}
if (-NOT (Test-RawImage -Source $Iso.FullName -Target $Device -SectorSize $Disk.LogicalSectorSize)) {
    throw [System.IO.IOException]::new("The stick does not match the ISO after the write. Try another stick or port.")
}
Write-Host "Done, the stick is written and verified. Boot from it." -ForegroundColor Green
