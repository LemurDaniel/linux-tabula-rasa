# NOTE:
#   Requires: Docker (Docker Desktop on Windows) with Linux containers and privileged mode.
#
#   ./build/Build-TabulaRasaIso.ps1
#   ./build/Build-TabulaRasaIso.ps1 -OutputPath C:\temp\iso

#
#   Chapters:
#     BUILD BUILDER IMAGE   Validations and the docker image with live-build.
#     BUILD ISO             Runs live-build and returns the ISO file.
#

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
    $OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '../out')
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
#   1. Run      Runs live-build in a privileged container.
#   2. Result   Returns the built ISO file.
#

# ---------------------------------------------------------------------------
# Run
#   Runs live-build in a privileged container.
# ---------------------------------------------------------------------------

$null = New-Item -ItemType Directory -Path $OutputPath -Force
$OutputPath = (Resolve-Path -Path $OutputPath).Path

Write-Verbose "[Build-TabulaRasaIso] Running live-build, ISO goes to '$OutputPath'."
docker run --rm --privileged --volume "$($REPO_ROOT):/src:ro" --volume "$($OutputPath):/out" $IMAGE_NAME
if ($LASTEXITCODE -NE 0) {
    throw [System.InvalidOperationException]::new("live-build must succeed, got exit code $LASTEXITCODE.")
}

# ---------------------------------------------------------------------------
# Result
#   Returns the built ISO file.
# ---------------------------------------------------------------------------

return Get-ChildItem -Path $OutputPath -Filter '*.iso'
| Sort-Object -Property LastWriteTime -Descending
| Select-Object -First 1
