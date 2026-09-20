#!/usr/bin/env bash
# Flash Fedora images to a Xiaomi Pad 6 (pipa) from a host PC.
#
# Usage:
#   ./scripts/flash.sh singleboot [--boot boot.img] [--root root.img]
#   ./scripts/flash.sh dualboot   [--boot boot.img] [--root root.img] [--partition fedora] [--linux-slot auto]
#
# The tablet must already be in fastboot (Volume Down + Power). Dualboot
# requires a GPT partition named with --partition (default: fedora). See DUALBOOT.md.

set -euo pipefail

mode=""
boot_img="boot.img"
root_img="root.img"
partition="fedora"
linux_slot="auto"
assume_yes=0
dry_run=0
force=0

usage() {
    cat <<'EOF'
Flash Fedora for Xiaomi Pad 6 (pipa)

Usage:
  flash.sh singleboot [options]
  flash.sh dualboot   [options]

Options:
  --boot FILE          boot.img path (default: ./boot.img)
  --root FILE          root.img path (default: ./root.img)
  --partition NAME     GPT partition name for rootfs (dualboot only, default: fedora)
  --linux-slot a|b|auto
                       Slot that will run Fedora (dualboot only).
                       auto (default) = opposite of fastboot current-slot,
                       same rule as TheMojoMan's Ubuntu/Fedora pipa images.
  --yes                Do not ask for confirmation
  --dry-run            Print fastboot commands without running them
  --force              Skip product=pipa check
  -h, --help           Show this help

Examples:
  ./scripts/flash.sh singleboot --boot boot.img --root root.img
  ./scripts/flash.sh dualboot --partition fedora
  ./scripts/flash.sh dualboot --partition fedora --linux-slot b
EOF
}

die() { echo "error: $*" >&2; exit 1; }

need_file() {
    [[ -f "$1" ]] || die "file not found: $1"
}

fb() {
    if [[ "$dry_run" -eq 1 ]]; then
        printf '[dry-run] fastboot'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    fastboot "$@"
}

confirm() {
    [[ "$assume_yes" -eq 1 ]] && return 0
    local reply
    read -r -p "$1 [y/N] " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]] || die "aborted"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        singleboot|dualboot) mode="$1"; shift ;;
        --boot) boot_img="$2"; shift 2 ;;
        --root) root_img="$2"; shift 2 ;;
        --partition) partition="$2"; shift 2 ;;
        --linux-slot) linux_slot="$2"; shift 2 ;;
        --yes) assume_yes=1; shift ;;
        --dry-run) dry_run=1; shift ;;
        --force) force=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (try --help)" ;;
    esac
done

[[ -n "$mode" ]] || { usage >&2; exit 1; }
[[ "$linux_slot" == "a" || "$linux_slot" == "b" || "$linux_slot" == "auto" ]] \
    || die "--linux-slot must be a, b, or auto"
[[ "$partition" =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid partition name: $partition"

current_slot_from_fastboot() {
    fastboot getvar current-slot 2>&1 | awk -F': ' '/^current-slot:/{print $2; exit}' | tr -d '\r'
}

resolve_linux_slot() {
    [[ "$linux_slot" != "auto" ]] && return 0
    if [[ "$dry_run" -eq 1 ]]; then
        echo "dry-run: --linux-slot auto would use the opposite of current-slot (showing b, Android on a)"
        linux_slot="b"
        return 0
    fi
    local current
    current="$(current_slot_from_fastboot)"
    case "$current" in
        a) linux_slot="b" ;;
        b) linux_slot="a" ;;
        *) die "could not read current-slot (got '${current:-empty}'). Pass --linux-slot a|b." ;;
    esac
    echo "Android is on slot ${current}; Fedora will use slot ${linux_slot}"
}

need_file "$boot_img"
need_file "$root_img"

if [[ "$dry_run" -eq 0 ]]; then
    command -v fastboot >/dev/null || die "fastboot not found (install android-tools / platform-tools)"
fi

if [[ "$dry_run" -eq 0 ]]; then
    echo "Waiting for a fastboot device..."
    fastboot wait-for-device
    product="$(fastboot getvar product 2>&1 | awk -F': ' '/^product:/{print $2; exit}' | tr -d '\r')"
    echo "fastboot product: ${product:-unknown}"
    if [[ "$force" -eq 0 && -n "$product" && "$product" != "pipa" ]]; then
        die "device product is '$product', expected 'pipa'. Pass --force if this is intentional."
    fi
fi

case "$mode" in
    singleboot)
        cat <<EOF
This will REPLACE Android on this tablet (both boot slots + userdata).
  boot : $boot_img -> boot_a and boot_b
  root : $root_img -> userdata
  dtbo : erased on both slots
EOF
        confirm "Flash singleboot Fedora and wipe Android?"
        fb flash boot_ab "$boot_img"
        fb flash userdata "$root_img"
        fb erase dtbo_ab
        echo "Rebooting. Do not hold Power to force-reboot; wait for Fedora."
        fb reboot
        ;;
    dualboot)
        resolve_linux_slot
        android_slot="a"
        [[ "$linux_slot" == "a" ]] && android_slot="b"
        cat <<EOF
Dualboot flash (Android stays on slot ${android_slot}):
  boot : $boot_img -> boot_${linux_slot}
  root : $root_img -> ${partition}
  dtbo : erased on slot ${linux_slot} only
  slot : set active ${linux_slot} (Fedora)

The GPT partition '${partition}' must already exist and be larger than root.img.
See DUALBOOT.md if you have not repartitioned yet.
EOF
        confirm "Flash Fedora to slot ${linux_slot} / partition '${partition}'?"

        if [[ "$dry_run" -eq 0 ]]; then
            if ! fastboot getvar "partition-type:${partition}" 2>&1 | grep -qi "partition-type:${partition}:"; then
                die "fastboot does not see partition '${partition}'. Repartition first (DUALBOOT.md)."
            fi
        fi

        fb flash "boot_${linux_slot}" "$boot_img"
        fb flash "$partition" "$root_img"
        fb erase "dtbo_${linux_slot}"
        fb set_active "$linux_slot"
        echo "Rebooting into Fedora (slot ${linux_slot}). Do not force-reboot with Power."
        fb reboot
        ;;
esac

echo "Done."
echo "First boot credentials:  user / 147147    root / fedora"
if [[ "$mode" == "dualboot" ]]; then
    echo "Switch to Android:  fastboot set_active ${android_slot}"
    echo "  from Fedora:      sudo pipa-switch-slot ${android_slot}"
    echo "  from Android:     Boot Control app, then reboot"
fi
