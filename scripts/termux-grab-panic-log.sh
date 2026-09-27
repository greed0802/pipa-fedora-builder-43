#!/system/bin/sh
# Grab the Fedora kernel-panic log from Qualcomm ramoops, on the tablet itself,
# with no PC and no keyboard. Run this on the ANDROID side (Termux, root) right
# after a Fedora panic + reboot into Android:
#
#   curl -fsSL https://raw.githubusercontent.com/greed0802/pipa-fedora-builder-43/arena/01a0e199-pipa-fedora-builder-43/scripts/termux-grab-panic-log.sh | su -c sh
#
# The panic text is saved to /sdcard/Download/pipa-panic/ so it can be opened,
# photographed, or shared from the Files app.

set -e

[ "$(id -u)" -eq 0 ] || { echo "need root:  su -c sh $0"; exit 1; }

OUT=/sdcard/Download/pipa-panic
mkdir -p "$OUT"

echo "== pstore entries =="
ls -la /sys/fs/pstore/ 2>/dev/null || echo "no /sys/fs/pstore (ramoops driver not exposed on this ROM)"

n=0
for f in /sys/fs/pstore/*; do
    [ -f "$f" ] || continue
    n=$((n+1))
    cp "$f" "$OUT/$(basename "$f")" 2>/dev/null || true
done
[ "$n" -eq 0 ] && echo "pstore was empty - the panic may have been overwritten by later boots."

# Also keep the Android-side last_kmsg variants if they exist
for f in /proc/last_kmsg /sys/fs/pstore/dmesg-ramoops-*; do
    [ -f "$f" ] && cp "$f" "$OUT/" 2>/dev/null || true
done

echo
echo "== panic lines found =="
grep -a -i -m 40 -E "kernel panic|oops|bug:|call trace|hardware name|pipa|unable to handle" \
    "$OUT"/* 2>/dev/null | head -60 || echo "(no panic markers found in saved files)"

echo
echo "Saved to $OUT - open the Files app -> Download -> pipa-panic."
echo "The line that matters starts with:  Kernel panic - not syncing:"
