# NOTE:
#   Builder image for the Linux Tabula Rasa live ISO, used by Build-TabulaRasaIso.ps1.
#   Requires a privileged container, live-build mounts proc/sys inside its chroot.
#
#   docker build -t linux-tabula-rasa-builder ./build
#   docker run --rm --privileged -v <REPO>:/src:ro -v <OUT>:/out linux-tabula-rasa-builder

FROM debian:trixie

RUN apt-get update \
    && apt-get install -y --no-install-recommends live-build debootstrap ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Copies the live-build config and the menu module into a fresh build tree, builds and hands the ISO to /out.
# The module lands in includes.chroot, so the image ships it under /opt/tabula-rasa.
# chmod: a checkout on Windows loses the executable bit of auto/config and the hooks.
CMD ["sh", "-c", "set -e; cp -a /src/live/. /build/; chmod +x /build/auto/* /build/config/hooks/live/*; mkdir -p /build/config/includes.chroot/opt/tabula-rasa; cp -a /src/src/TabulaRasa /build/config/includes.chroot/opt/tabula-rasa/; lb config; lb build; cp /build/*.iso /out/"]
