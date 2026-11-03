# NOTE:
#   Requires: Docker (Docker Desktop on Windows) with Linux containers and privileged mode.
#
#   ./build/Build-TabulaRasaIso.ps1
#   ./build/Build-TabulaRasaIso.ps1 -OutputPath C:\temp\iso -HotspotPassword 'my-secret-123'

#
#   Chapters:
#     BUILD BUILDER IMAGE   Validations and the docker image with live-build.
#     BUILD ISO             Writes the build-time settings, runs live-build, returns the ISO.
#

# The hotspot password ends up in plain text in hotspot.json on the stick by design (the kiosk shows it).
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'HotspotPassword')]
[CmdletBinding()]
param (
    <#
    [Optional]
    The folder the ISO is written to. Default is 'out' in the repository root.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [System.String]
    $OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '../out'),

    <#
    [Optional]
    The name of the Wi-Fi hotspot the stick opens without LAN. Default is 'TabulaRasa'.
    #>
    [Parameter(
        Mandatory = $false
    )]
    [ValidateLength(1, 32)]
    [System.String]
    $HotspotSsid = 'TabulaRasa',

    <#
    [Optional]
    The WPA2 password of the hotspot, 8 to 63 characters. Default is 'tabularasa'.
    Stored in plain text on the stick, so not a password used anywhere else.
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

$IMAGE_NAME = 'linux-tabula-rasa-builder'
$REPO_ROOT  = (Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')).Path

# ===========================================================================
# =========================   BUILD BUILDER IMAGE   =========================
# ===========================================================================
#
#   1. Validations   Fails early when docker is missing.
#   2. Image         Builds the image that holds live-build.
#

# ---------------------------------------------------------------------------
# Validations
#   Fails early when docker is missing.
# ---------------------------------------------------------------------------

if ($null -EQ (Get-Command -Name docker -ErrorAction SilentlyContinue)) {
    throw [System.InvalidOperationException]::new('Docker must be installed and on the PATH to build the ISO.')
}

# ---------------------------------------------------------------------------
# Image
#   Builds the image that holds live-build.
# ---------------------------------------------------------------------------

Write-Verbose "[Build-TabulaRasaIso] Building image '$IMAGE_NAME'."
docker build --tag $IMAGE_NAME $PSScriptRoot
if ($LASTEXITCODE -NE 0) {
    throw [System.InvalidOperationException]::new("docker build must succeed, got exit code $LASTEXITCODE.")
}

# ===========================================================================
# ==============================   BUILD ISO   ==============================
# ===========================================================================
#
#   1. Settings   Writes hotspot.json into a temporary folder for the container.
#   2. Run        Runs live-build in a privileged container.
#   3. Result     Returns the built ISO file and removes the temporary folder.
#

# ---------------------------------------------------------------------------
# Settings
#   Writes hotspot.json into a temporary folder for the container.
# ---------------------------------------------------------------------------

$ConfigPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "tabula-rasa-config-$([System.Guid]::NewGuid().ToString('N'))"
$null = New-Item -ItemType Directory -Path $ConfigPath
@{ Ssid = $HotspotSsid; Password = $HotspotPassword }
| ConvertTo-Json
| Set-Content -Path (Join-Path -Path $ConfigPath -ChildPath 'hotspot.json') -Encoding utf8NoBOM

try {
    # ---------------------------------------------------------------------------
    # Run
    #   Runs live-build in a privileged container.
    # ---------------------------------------------------------------------------

    $null = New-Item -ItemType Directory -Path $OutputPath -Force
    $OutputPath = (Resolve-Path -Path $OutputPath).Path

    Write-Verbose "[Build-TabulaRasaIso] Running live-build, ISO goes to '$OutputPath'."
    docker run --rm --privileged --volume "$($REPO_ROOT):/src:ro" --volume "$($ConfigPath):/config:ro" --volume "$($OutputPath):/out" $IMAGE_NAME
    if ($LASTEXITCODE -NE 0) {
        throw [System.InvalidOperationException]::new("live-build must succeed, got exit code $LASTEXITCODE.")
    }
}
finally {
    # Removes the settings written in Settings, they hold the hotspot password.
    Remove-Item -Path $ConfigPath -Recurse -Force
}

# ---------------------------------------------------------------------------
# Result
#   Returns the built ISO file and removes the temporary folder.
# ---------------------------------------------------------------------------

return Get-ChildItem -Path $OutputPath -Filter '*.iso'
| Sort-Object -Property LastWriteTime -Descending
| Select-Object -First 1
