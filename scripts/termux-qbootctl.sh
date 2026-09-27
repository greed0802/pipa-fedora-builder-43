#!/system/bin/sh
# Build Qualcomm's qbootctl on-device in Termux and switch the Xiaomi Pad 6
# (pipa) A/B slot WITHOUT a PC. Same operation as the BootControl app, and as
# `pipa-switch-slot` on the Fedora side - just compiled and run from Termux.
#
#   pkg install clang git -y                 # as the normal Termux user
#   curl -fsSL https://raw.githubusercontent.com/greed0802/pipa-fedora-builder-43/arena/01a0e199-pipa-fedora-builder-43/scripts/termux-qbootctl.sh -o qswitch.sh
#   su -c "sh qswitch.sh"                    # build + show current slot
#   su -c "sh qswitch.sh a"                  # set slot a (Android)  + reboot
#   su -c "sh qswitch.sh b"                  # set slot b (Fedora)   + reboot
#
# NOTE: userspace slot switching carries a small known risk on pipa (see
# DUALBOOT.md): a few units land in a fastboot loop afterwards, which needs a
# PC + `fastboot flash partition:N gpt_bothN.bin` to undo. If a PC is easy to
# borrow, `fastboot set_active a` is still the gold standard.

set -e

PREFIX_DIR="$HOME/qbootctl-src"
BIN="$HOME/qbootctl"

say() { echo "== $*"; }

fetch_hdr() {  # fetch_hdr <repo-path> <dest>
    curl -fsSL "https://raw.githubusercontent.com/torvalds/linux/master/$1" -o "$2" 2>/dev/null \
      || curl -fsSL "https://cdn.jsdelivr.net/gh/torvalds/linux@master/$1" -o "$2"
}

build() {
    command -v clang >/dev/null || { echo "run:  pkg install clang git -y   (as normal Termux user) first"; exit 1; }
    say "fetching qbootctl source"
    rm -rf "$PREFIX_DIR"
    git clone --quiet --depth 1 https://github.com/linux-msm/qbootctl "$PREFIX_DIR"
    say "fetching uapi headers (bsg, scsi_bsg_ufs)"
    mkdir -p "$PREFIX_DIR/inc/linux" "$PREFIX_DIR/inc/scsi"
    fetch_hdr "include/uapi/linux/bsg.h"          "$PREFIX_DIR/inc/linux/bsg.h"
    fetch_hdr "include/uapi/scsi/scsi_bsg_ufs.h"  "$PREFIX_DIR/inc/scsi/scsi_bsg_ufs.h"
    say "compiling"
    clang -std=gnu11 -O2 -o "$BIN" \
        "$PREFIX_DIR/qbootctl.c" \
        "$PREFIX_DIR/bootctrl_impl.c" \
        "$PREFIX_DIR/gpt-utils.c" \
        "$PREFIX_DIR/ufs-bsg.c" \
        "$PREFIX_DIR/crc32.c" \
        -I"$PREFIX_DIR/inc"
    say "built: $BIN"
}

# qbootctl expects /dev/disk/by-partlabel; Android only provides
# /dev/block/by-name. Bridge them.
fix_devlinks() {
    mkdir -p /dev/disk/by-partlabel
    for p in /dev/block/by-name/*; do
        ln -sf "$(readlink -f "$p")" "/dev/disk/by-partlabel/$(basename "$p")" 2>/dev/null || true
    done
}

[ "$(id -u)" -eq 0 ] || { echo "need root:  su -c \"sh $0 [a|b]\""; exit 1; }

[ -x "$BIN" ] || build
fix_devlinks

slot="${1:-}"
if [ -z "$slot" ]; then
    echo
    say "current slot info:"
    "$BIN" -c || true
    echo
    echo "switch with:  su -c \"sh $0 a\"   (a=Android, b=Fedora)"
    exit 0
fi

[ "$slot" = "a" ] || [ "$slot" = "b" ] || [ "$slot" = "0" ] || [ "$slot" = "1" ] || {
    echo "slot must be a or b"; exit 1; }

echo "BEFORE:"; "$BIN" -c || true
say "setting active slot to $slot"
"$BIN" -s "$slot"
sync
echo "AFTER:"; "$BIN" -c || true
echo
say "rebooting into slot $slot in 5 seconds (Ctrl-C to abort)"
sleep 5
/system/bin/reboot
