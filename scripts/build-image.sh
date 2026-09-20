#!/usr/bin/env bash
# Build a Fedora image for Xiaomi Pad 6 (pipa) with Docker.
#
# Usage:
#   ./scripts/build-image.sh [tty|plasma|plasma-mobile|gnome|custom]
#
# Images are written to ./images/. This needs Docker, ~20 GiB free disk,
# and --privileged (loop mounts + binfmt). Cross-building on x86_64 also
# needs qemu-user-static inside the image (installed by the Dockerfile).

set -euo pipefail

flavor="${1:-plasma}"
image_tag="${PIPA_BUILDER_TAG:-pipa-fedora-builder}"

case "$flavor" in
    tty|plasma|plasma-mobile|gnome|custom) ;;
    -h|--help)
        echo "Usage: $0 [tty|plasma|plasma-mobile|gnome|custom]"
        exit 0
        ;;
    *)
        echo "Unknown flavor '$flavor' (tty, plasma, plasma-mobile, gnome, custom)" >&2
        exit 1
        ;;
esac

command -v docker >/dev/null || {
    echo "error: docker is not installed or not on PATH" >&2
    echo "See BUILD.md. On Fedora: sudo dnf install docker qemu-user-static" >&2
    exit 1
}

root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$root/images"

echo "==> docker build ($image_tag)"
docker build -t "$image_tag" "$root"

echo "==> docker run flavor=$flavor"
# /dev is bind-mounted so mkosi/losetup can create loop devices.
docker run --privileged --rm \
    -v "$root/images:/build/images" \
    -v /dev:/dev \
    "$image_tag" "$flavor"

echo "==> images:"
ls -lh "$root/images" || true
echo "Flash with:  ./scripts/flash.sh singleboot --boot <boot.img> --root <root.img>"
echo "        or:  ./scripts/flash.sh dualboot   --boot <boot.img> --root <root.img>"
echo "See INSTALL.md and DUALBOOT.md."
