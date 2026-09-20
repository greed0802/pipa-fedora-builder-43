#!/system/bin/sh
# Run from Android/GSI (Termux, Magisk su). Mounts the Fedora linux
# partition and sets multi-user.target + a backlight oneshot so the next
# slot-B boot is a text login instead of a black Plasma screen.
#
#   curl -fsSL https://raw.githubusercontent.com/greed0802/pipa-fedora-builder-43/arena/01a0bd69-pipa-fedora-builder-43/scripts/termux-fedora-textboot.sh | su -c sh

set -e

if [ "$(id -u)" -ne 0 ]; then
    echo "Need root:  su -c sh $0"
    exit 1
fi

MNT=/data/local/fedmnt
PART=/dev/block/by-name/linux
[ -e "$PART" ] || { echo "no linux partition"; exit 1; }

mkdir -p "$MNT"
if ! mountpoint -q "$MNT"; then
    mount -t ext4 "$PART" "$MNT"
fi

if [ ! -f "$MNT/etc/os-release" ]; then
    echo "linux partition did not look like Fedora"
    cat "$MNT/etc/os-release" 2>/dev/null || true
    umount "$MNT" || true
    exit 1
fi
echo "Found: $(grep PRETTY_NAME "$MNT/etc/os-release")"

ln -sfn /usr/lib/systemd/system/multi-user.target "$MNT/etc/systemd/system/default.target"

mkdir -p "$MNT/etc/systemd/system/multi-user.target.wants"
cat > "$MNT/etc/systemd/system/pipa-backlight.service" <<'EOF'
[Unit]
Description=Raise pipa backlight
After=systemd-udev-settle.service
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for b in /sys/class/backlight/*/brightness; do [ -w "$b" ] && echo 128 > "$b"; done; exit 0'
[Install]
WantedBy=multi-user.target
EOF
ln -sfn /etc/systemd/system/pipa-backlight.service \
    "$MNT/etc/systemd/system/multi-user.target.wants/pipa-backlight.service"

# Keep a getty on tty1 (already default on Fedora multi-user)
echo "default.target -> multi-user (text). Unmounting."
umount "$MNT"
echo "Done. From a PC in fastboot:"
echo "  fastboot set_active b && fastboot reboot"
echo "Plug a keyboard, login  user / 147147"
echo "Then:  journalctl -b -p err --no-pager | tail"
echo "GUI later:  sudo systemctl set-default graphical.target && sudo reboot"
