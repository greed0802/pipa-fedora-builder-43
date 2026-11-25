#!/bin/sh
# Read-only hardware inventory for the pipa macOS feasibility notes.
# This script does not invoke privileged commands or write to storage.
set -u

printf '%s\n' '=== Read-only platform inventory ==='
printf '%s\n' 'Do not share output without reviewing it for sensitive information.'
printf 'Kernel: '; uname -srmo 2>/dev/null || uname -a

if command -v getprop >/dev/null 2>&1; then
    for prop in ro.product.device ro.product.model ro.board.platform ro.boot.slot_suffix; do
        printf '%s: ' "$prop"
        getprop "$prop" 2>/dev/null || true
    done
fi

for item in /sys/firmware/devicetree/base/model /sys/firmware/devicetree/base/compatible; do
    if [ -r "$item" ]; then
        printf '%s: ' "$item"
        tr '\000' ' ' < "$item"
        printf '\n'
    fi
done
if [ -d /sys/firmware/efi ]; then
    echo 'EFI runtime detected (this does not establish macOS compatibility).'
else
    echo 'No EFI runtime detected in this boot.'
fi

printf '\n%s\n' '=== Storage (inventory only) ==='
if command -v lsblk >/dev/null 2>&1; then
    # No filesystem UUIDs, serial numbers, or mount paths are requested.
    lsblk -o NAME,TYPE,SIZE 2>/dev/null || echo 'Storage inventory unavailable.'
elif [ -r /proc/partitions ]; then
    cat /proc/partitions
else
    echo 'Storage inventory unavailable without additional tools or permissions.'
fi

printf '\n%s\n' '=== Kernel-visible device classes ==='
for class in drm sound net bluetooth input iio; do
    path="/sys/class/$class"
    if [ -d "$path" ]; then
        printf '%s: ' "$class"
        found=0
        for device in "$path"/*; do
            [ -e "$device" ] || continue
            printf '%s ' "${device##*/}"
            found=1
        done
        [ "$found" -eq 1 ] || printf '%s' '(none visible)'
        printf '\n'
    else
        printf '%s: unavailable\n' "$class"
    fi
done
cat <<'NOTICE'

This inventory describes the currently running OS only. It does not prove that
macOS can boot, access storage, or drive any listed device. No partition changes
or bootloader changes were made. See HACKINTOSH.md for the compatibility blockers.
NOTICE
