#!/usr/bin/env bash
# NOTE:
#   Requires: Linux, bash, lsblk, dd, sudo (for the raw write).
#             Docker for --build, the GitHub CLI (gh, logged in) for --from-release of a private repository.
#   Erases the selected USB stick completely and writes the Linux Tabula Rasa ISO onto it.
#   Windows: use Write-TabulaRasaStick.ps1 next to this script.
#
#   ./build/write-tabula-rasa-stick.sh --from-release       # newest GitHub release, then pick a stick
#   ./build/write-tabula-rasa-stick.sh --build              # build the ISO, then pick a stick
#   ./build/write-tabula-rasa-stick.sh                      # newest ISO in out/, then pick a stick
#   ./build/write-tabula-rasa-stick.sh --device /dev/sdc    # skip the question for the stick
#
#   Options:
#     --from-release             Downloads the ISO of the newest GitHub release and checks SHA256SUMS.
#     --repository OWNER/NAME    The repository of --from-release. Default is 'LemurDaniel/linux-tabula-rasa'.
#     --build                    Builds the ISO with Docker first (same steps as Build-TabulaRasaIso.ps1).
#     --iso PATH                 The ISO to write. Default is the newest *.iso in out/.
#     --device /dev/sdX          The stick. Without it the USB disks are listed and the script asks.
#     --force                    Allows disks larger than 256 GB (usually external drives, not sticks).
#     --skip-verify              Skips reading the stick back after the write.
#     --hotspot-ssid NAME        Passed to the build. Default is 'TabulaRasa'.
#     --hotspot-password SECRET  Passed to the build, 8 to 63 characters. Default is 'tabularasa'.

#
#   Chapters:
#     HELPERS          Messages, JSON escaping, the USB disk list, the build and the release download.
#     PREPARE          Options, the ISO (downloaded, built or found) and the target stick.
#     WRITE AND CHECK  Typed confirmation, unmount, raw write and read-back check.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_PATH="${REPO_ROOT}/out"
IMAGE_NAME="linux-tabula-rasa-builder"
MAX_STICK_BYTES=$((256 * 1024 * 1024 * 1024))

# ===========================================================================
# ===============================   HELPERS   ===============================
# ===========================================================================
#
#   fail           Prints an error and exits.
#   json_escape    Escapes a value for a JSON string.
#   list_usb           USB disks as 'path size model', the system disk never shows up.
#   build_iso          Builds the builder image and the ISO into out/.
#   download_release   Downloads the newest release ISO into out/, checks it, prints its path.
#

fail() {
    echo "Error: $*" >&2
    exit 1
}

json_escape() {
    local value="${1//\\/\\\\}"
    printf '%s' "${value//\"/\\\"}"
}

list_usb() {
    # 'lsblk -dnpo PATH,TRAN,SIZE,MODEL' prints '/dev/sdc usb 29.8G SanDisk Cruzer', only usb rows stay.
    lsblk -dnpo PATH,TRAN,SIZE,MODEL | awk '$2 == "usb" { $2 = ""; print }'
}

build_iso() {
    local ssid="$1" password="$2" config_path

    command -v docker >/dev/null || fail "Docker must be installed to build the ISO."
    docker build --tag "${IMAGE_NAME}" "${SCRIPT_DIR}"

    # Build-time settings for the container, removed again because they hold the hotspot password.
    config_path="$(mktemp -d)"
    trap 'rm -rf "${config_path}"; trap - RETURN' RETURN
    printf '{ "Ssid": "%s", "Password": "%s" }\n' "$(json_escape "${ssid}")" "$(json_escape "${password}")" > "${config_path}/hotspot.json"

    mkdir -p "${OUT_PATH}"
    docker run --rm --privileged \
        --volume "${REPO_ROOT}:/src:ro" \
        --volume "${config_path}:/config:ro" \
        --volume "${OUT_PATH}:/out" \
        "${IMAGE_NAME}"
}

download_release() {
    local repository="$1" iso_name

    mkdir -p "${OUT_PATH}"
    # > gh is installed   works for private repositories when logged in
    # > otherwise         the public API, works only while the repository is public
    if command -v gh >/dev/null; then
        gh release download --repo "${repository}" --pattern '*.iso' --pattern 'SHA256SUMS' --dir "${OUT_PATH}" --clobber >&2 \
            || fail "gh must download the newest release of '${repository}'. Is there a release, and is gh logged in (gh auth login)?"
    else
        command -v curl >/dev/null || fail "curl or gh must be installed for --from-release."
        # The API answers JSON, every asset carries a line '"browser_download_url": "https://..."'.
        curl -fsSL "https://api.github.com/repos/${repository}/releases/latest" \
            | grep -o '"browser_download_url": *"[^"]*"' \
            | sed 's/.*"\(https[^"]*\)"/\1/' \
            | grep -E '(\.iso|/SHA256SUMS)$' \
            | while read -r url; do curl -fL --progress-bar -o "${OUT_PATH}/${url##*/}" "${url}"; done \
            || fail "The newest release of '${repository}' must be reachable. A private repository needs the GitHub CLI (gh) logged in."
    fi

    # SHA256SUMS holds '<hash>  <file>' lines, sha256sum checks the ISO's line.
    iso_name="$(grep -E '\.iso$' "${OUT_PATH}/SHA256SUMS" | head -n 1 | awk '{ print $2 }' | tr -d '*')"
    [[ -n "${iso_name}" ]] || fail "SHA256SUMS of '${repository}' must list the ISO."
    (cd "${OUT_PATH}" && grep -E "[ *]${iso_name}\$" SHA256SUMS | sha256sum -c - >&2) \
        || fail "'${iso_name}' must match SHA256SUMS. Download it again."
    printf '%s\n' "${OUT_PATH}/${iso_name}"
}

# ===========================================================================
# ===============================   PREPARE   ===============================
# ===========================================================================
#
#   1. Options   Reads the command line.
#   2. ISO       Builds it with --build, else takes the newest one.
#   3. Stick     Picks the USB disk and checks it may be erased.
#

# ---------------------------------------------------------------------------
# Options
#   Reads the command line.
# ---------------------------------------------------------------------------

is_from_release=false
is_build=false
is_force=false
repository="LemurDaniel/linux-tabula-rasa"
is_skip_verify=false
iso_path=""
device=""
hotspot_ssid="TabulaRasa"
hotspot_password="tabularasa"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --from-release)     is_from_release=true ;;
        --repository)       repository="${2:?--repository needs owner/name}"; shift ;;
        --build)            is_build=true ;;
        --force)            is_force=true ;;
        --skip-verify)      is_skip_verify=true ;;
        --iso)              iso_path="${2:?--iso needs a path}"; shift ;;
        --device)           device="${2:?--device needs a path}"; shift ;;
        --hotspot-ssid)     hotspot_ssid="${2:?--hotspot-ssid needs a name}"; shift ;;
        --hotspot-password) hotspot_password="${2:?--hotspot-password needs a value}"; shift ;;
        -h|--help)          sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)                  fail "Unknown option '$1', see --help." ;;
    esac
    shift
done

[[ "$(uname -s)" == "Linux" ]] || fail "This script needs Linux, on Windows use build/Write-TabulaRasaStick.ps1."
(( ${#hotspot_ssid} >= 1 && ${#hotspot_ssid} <= 32 )) || fail "--hotspot-ssid must have 1 to 32 characters."
(( ${#hotspot_password} >= 8 && ${#hotspot_password} <= 63 )) || fail "--hotspot-password must have 8 to 63 characters."
[[ "${repository}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "--repository must look like 'owner/name'."

source_count=0
[[ "${is_from_release}" == true ]] && source_count=$((source_count + 1))
[[ "${is_build}" == true ]] && source_count=$((source_count + 1))
[[ -n "${iso_path}" ]] && source_count=$((source_count + 1))
(( source_count <= 1 )) || fail "--from-release, --build and --iso must not be combined, pick one source for the ISO."

# ---------------------------------------------------------------------------
# ISO
#   Downloads, builds or finds the ISO.
# ---------------------------------------------------------------------------

# > --from-release   downloads the newest release and checks its checksum
# > --build          builds, the newest ISO in out/ is the new one
# > --iso            takes that file
# > otherwise        takes the newest ISO in out/
if [[ "${is_from_release}" == true ]]; then
    iso_path="$(download_release "${repository}")"
elif [[ "${is_build}" == true ]]; then
    build_iso "${hotspot_ssid}" "${hotspot_password}"
fi
if [[ -z "${iso_path}" ]]; then
    # Newest first: '1730000000.0 /repo/out/a.iso' sorted by the timestamp, the path stays.
    iso_path="$(find "${OUT_PATH}" -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -n 1 | cut -d' ' -f2- || true)"
fi
[[ -n "${iso_path}" && -f "${iso_path}" ]] || fail "An ISO must exist, build one with --build or pass --iso. Looked in '${OUT_PATH}'."

iso_bytes="$(stat -c %s "${iso_path}")"
echo "ISO: ${iso_path} ($((iso_bytes / 1024 / 1024)) MB)"

# ---------------------------------------------------------------------------
# Stick
#   Picks the USB disk and checks it may be erased.
# ---------------------------------------------------------------------------

usb_disks="$(list_usb)"
[[ -n "${usb_disks}" ]] || fail "No USB disk found. Plug in the stick and run the script again."

if [[ -z "${device}" ]]; then
    echo "USB disks:"
    while read -r line; do
        echo "  ${line}"
    done <<< "${usb_disks}"
    read -rp "Device of the stick (e.g. /dev/sdc): " device
fi

# Only a USB disk from the list, never a partition or the disk the system runs on.
echo "${usb_disks}" | awk '{ print $1 }' | grep -qx -- "${device}" \
    || fail "'${device}' must be one of the USB disks: $(echo "${usb_disks}" | awk '{ print $1 }' | tr '\n' ' ')"
if lsblk -lnpo MOUNTPOINT "${device}" | grep -qx -- "/"; then
    fail "'${device}' holds the running system."
fi

device_bytes="$(lsblk -bdno SIZE "${device}")"
if (( device_bytes > MAX_STICK_BYTES )) && [[ "${is_force}" != true ]]; then
    fail "'${device}' has $((device_bytes / 1024 / 1024 / 1024)) GB, more than 256 GB looks like an external drive. Add --force if it really is the stick."
fi
(( device_bytes >= iso_bytes )) || fail "'${device}' must hold at least $((iso_bytes / 1024 / 1024)) MB."

# ===========================================================================
# ===========================   WRITE AND CHECK   ===========================
# ===========================================================================
#
#   1. Confirm   Shows the disk and wants its path typed.
#   2. Write     Unmounts its partitions and writes the ISO raw with dd.
#   3. Check     Reads the stick back and compares it with the ISO.
#

# ---------------------------------------------------------------------------
# Confirm
#   Shows the disk and wants its path typed.
# ---------------------------------------------------------------------------

echo "Everything on $(echo "${usb_disks}" | grep -- "^${device} ") will be lost."
read -rp "Type the device path (${device}) to continue: " answer
if [[ "${answer}" != "${device}" ]]; then
    echo "Cancelled, nothing was written."
    exit 0
fi

# ---------------------------------------------------------------------------
# Write
#   Unmounts its partitions and writes the ISO raw with dd.
# ---------------------------------------------------------------------------

# Desktops mount sticks on plug-in, a mounted partition would be written underneath.
while read -r mountpoint; do
    if [[ -n "${mountpoint}" ]]; then
        sudo umount "${mountpoint}"
    fi
done < <(lsblk -lnpo MOUNTPOINT "${device}")

sudo dd if="${iso_path}" of="${device}" bs=4M conv=fsync oflag=direct status=progress
sync

# ---------------------------------------------------------------------------
# Check
#   Reads the stick back and compares it with the ISO.
# ---------------------------------------------------------------------------

if [[ "${is_skip_verify}" == true ]]; then
    echo "Done, the stick is ready (not verified)."
    exit 0
fi

echo "Checking the stick ..."
sudo cmp --bytes="${iso_bytes}" "${iso_path}" "${device}" \
    || fail "The stick does not match the ISO after the write. Try another stick or port."
echo "Done, the stick is written and verified. Boot from it."
