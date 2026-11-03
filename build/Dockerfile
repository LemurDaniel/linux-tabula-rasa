# NOTE:
#   Builder image for the Linux Tabula Rasa live ISO, used by Build-TabulaRasaIso.ps1.
#   Requires a privileged container, live-build mounts proc/sys inside its chroot.
#
#   docker build -t linux-tabula-rasa-builder ./build
#   docker run --rm --privileged -v <REPO>:/src:ro -v <CONFIG>:/config:ro -v <OUT>:/out linux-tabula-rasa-builder
#
#   Mounts:
#     /src      The repository (live-build config and modules).
#     /config   Build-time settings from Build-TabulaRasaIso.ps1 (hotspot.json).
#     /out      Receives the ISO and packages-by-size.txt (installed packages, largest first, in KiB).

FROM debian:trixie

RUN apt-get update \
    && apt-get install -y --no-install-recommends live-build debootstrap ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# 1. Copies the live-build config into a fresh build tree.
# 2. chmod: a checkout on Windows loses the executable bit of auto/config and the hooks.
# 3. Ships both modules under /opt/tabula-rasa and the build-time settings under /etc/tabula-rasa.
# 4. Builds and hands the ISO to /out.
# 5. Writes the size report from the chroot that went into the image.
CMD set -e; \
    cp -a /src/live/. /build/; \
    chmod +x /build/auto/* /build/config/hooks/live/*; \
    mkdir -p /build/config/includes.chroot/opt/tabula-rasa /build/config/includes.chroot/etc/tabula-rasa; \
    cp -a /src/src/TabulaRasa /src/src/TabulaRasa.Web /build/config/includes.chroot/opt/tabula-rasa/; \
    cp /config/hotspot.json /build/config/includes.chroot/etc/tabula-rasa/hotspot.json; \
    lb config; \
    lb build; \
    cp /build/*.iso /out/; \
    chroot /build/chroot dpkg-query -W -f '${Installed-Size}\t${Package}\n' | sort -rn > /out/packages-by-size.txt
