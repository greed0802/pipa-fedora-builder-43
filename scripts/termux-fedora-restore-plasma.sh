#!/system/bin/sh
# Run from Android (Termux + root) to undo a broken display-manager change on
# the Fedora pipa slot. Fixes the state left behind by:
#     systemctl disable plasmalogin   (+ a failed niri-install)
#
# It restores SDDM (plasmalogin), switches Fedora back to graphical.target,
# removes any greetd unit leftovers, and adds SDDM autologin for `user` so the
# tablet boots straight into Plasma with no keyboard needed.
#
#   su -c sh termux-fedora-restore-plasma.sh
#
# Then boot Fedora again (from a PC:  fastboot set_active b && fastboot reboot,
# or with Magisk root in Termux:  su -c setprop sys.powerctl reboot,bootloader
# followed by  fastboot set_active b && fastboot reboot  on the PC).

set -e

[ "$(id -u)" -eq 0 ] || { echo "need root:  su -c sh $0"; exit 1; }

MNT=/data/local/fedmnt
PART=""
for p in /dev/block/by-name/fedora /dev/block/by-name/linux; do
    [ -e "$p" ] && PART="$p" && break
done
[ -n "$PART" ] || { echo "no fedora/linux partition found"; exit 1; }

mkdir -p "$MNT"
mountpoint -q "$MNT" || mount -t ext4 "$PART" "$MNT"

if [ ! -f "$MNT/etc/os-release" ]; then
    echo "$PART does not look like Fedora:"
    cat "$MNT/etc/os-release" 2>/dev/null || true
    umount "$MNT" || true
    exit 1
fi
echo "Found: $(grep PRETTY_NAME "$MNT/etc/os-release")"

# 1. graphical target back (undoes termux-fedora-textboot.sh too)
rm -f "$MNT/etc/systemd/system/default.target"
ln -sfn /usr/lib/systemd/system/graphical.target \
    "$MNT/etc/systemd/system/default.target"

# 2. restore the display manager -> plasmalogin (SDDM)
rm -f "$MNT/etc/systemd/system/display-manager.service"
ln -sfn /usr/lib/systemd/system/plasmalogin.service \
    "$MNT/etc/systemd/system/display-manager.service"

# 3. make sure greetd can never grab the seat at boot
rm -f "$MNT/etc/systemd/system/graphical.target.wants/greetd.service" \
      "$MNT/etc/systemd/system/multi-user.target.wants/greetd.service" \
      "$MNT/etc/systemd/system/display-manager.service.wants/greetd.service"

# 4. SDDM autologin so the touchscreen alone is enough
mkdir -p "$MNT/etc/sddm.conf.d"
cat > "$MNT/etc/sddm.conf.d/zz-autologin.conf" <<'EOF'
[Autologin]
User=user
Session=plasma
Relogin=false
EOF
chmod 644 "$MNT/etc/sddm.conf.d/zz-autologin.conf"

# 5. drop the text-boot backlight oneshot if it was ever installed
rm -f "$MNT/etc/systemd/system/pipa-backlight.service" \
      "$MNT/etc/systemd/system/multi-user.target.wants/pipa-backlight.service"

umount "$MNT"
echo
echo "Fixed. Boot Fedora again:"
echo "  PC:        fastboot set_active b && fastboot reboot"
echo "  Magisk:    su -c 'setprop sys.powerctl reboot,bootloader'  then fastboot"
echo "It will autologin into Plasma (user / 147147 still valid for sudo/ssh)."
