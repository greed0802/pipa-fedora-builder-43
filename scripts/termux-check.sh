#!/system/bin/sh
# Inspect Xiaomi Pad 6 (pipa) slot + GPT from Termux or adb.
# Needs root. In Termux:
#
#   curl -fsSL https://raw.githubusercontent.com/greed0802/pipa-fedora-builder-43/arena/01a0bd69-pipa-fedora-builder-43/scripts/termux-check.sh | su -c sh

GETPROP=/system/bin/getprop
[ -x "$GETPROP" ] || GETPROP=getprop

if [ "$(id -u)" -ne 0 ]; then
    echo "Need root. In Termux run:"
    echo "  curl -fsSL https://raw.githubusercontent.com/greed0802/pipa-fedora-builder-43/arena/01a0bd69-pipa-fedora-builder-43/scripts/termux-check.sh | su -c sh"
    exit 1
fi

echo "=== Android ==="
echo "device:   $($GETPROP ro.product.device)"
echo "name:     $($GETPROP ro.product.name)"
echo "model:    $($GETPROP ro.product.model)"
echo "slot:     $($GETPROP ro.boot.slot_suffix)  (ro.boot.slot=$($GETPROP ro.boot.slot))"
echo "vbmeta:   $($GETPROP ro.boot.verifiedbootstate)  locked=$($GETPROP ro.boot.flash.locked)"
dev="$($GETPROP ro.product.device)"
if [ "$dev" != "pipa" ]; then
    echo
    echo "NOTE: ro.product.device is '$dev', not 'pipa'."
    echo "If cmdline has m82_36/m82_42 this is still a Pad 6 (Magisk spoof is common)."
    echo "fastboot getvar product should still say pipa."
fi
echo

echo "=== cmdline (panel + slot) ==="
tr ' ' '\n' </proc/cmdline | grep -E 'msm_drm|androidboot.slot|androidboot.mode' || cat /proc/cmdline
echo
echo "Tianma if you see:  m82_36_02_0a"
echo "CSOT   if you see:  m82_42_02_0b"
echo

echo "=== interesting partitions (MiB) ==="
for n in userdata fedora linux ubuntu artix esp super boot_a boot_b dtbo_a dtbo_b vbmeta_a vbmeta_b; do
    p=/dev/block/by-name/$n
    if [ -e "$p" ] || [ -L "$p" ]; then
        real=$(readlink -f "$p" 2>/dev/null || echo "$p")
        bytes=$(blockdev --getsize64 "$real" 2>/dev/null || echo 0)
        mib=$((bytes / 1048576))
        printf "%-12s %8s MiB  %s\n" "$n" "$mib" "$real"
    fi
done

echo
echo "=== all labels ==="
ls -1 /dev/block/by-name
echo
echo "Fedora dualboot:  ./scripts/flash.sh dualboot --partition <linux-root-name>"
echo "Use fedora, linux, or ubuntu — not esp, not userdata."
