#!/usr/bin/env bash
# Build the patched pipadb/linux tree and install it like kernel-pipa.
# Run on the Pad (aarch64 Fedora), not on WSL x86_64.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sudo ./scripts/build-install-camera-kernel.sh /path/to/linux-pipa

On the Xiaomi Pad 6, as root:
  1. Backs up the current Linux boot partition to ~/boot-linux-backup.img
  2. Merges kernel-camera/config.fragment into .config (from /boot/config-$(uname -r))
  3. make Image.gz modules dtbs
  4. modules_install + dtb as kernel-pipa expects
  5. dracut + kernel-install add  (pipa-kernel-flasher-hook writes boot_<slot>)

Revert if it does not boot (PC + usbipd/WSL fastboot):
  fastboot flash boot_b $HOME/boot-linux-backup.img
  fastboot erase dtbo_b
EOF
  exit 1
}

[[ ${1:-} == -h || ${1:-} == --help ]] && usage
[[ $# -eq 1 ]] || usage
[[ $(id -u) -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || {
  echo "This is $(uname -m). Build/install on the Pad, not WSL." >&2
  exit 1
}

TREE=$(readlink -f "$1")
HERE=$(readlink -f "$(dirname "$0")/..")
BOARD="$TREE/arch/arm64/boot/dts/qcom/sm8250-xiaomi-pipa.dts"
DTB="$TREE/arch/arm64/boot/dts/qcom/sm8250-xiaomi-pipa.dtb"
FRAG="$HERE/kernel-camera/config.fragment"
EXTRAVERSION="${EXTRAVERSION:--pipa-cam}"

[[ -f $BOARD ]] || { echo "not pipadb/linux: $BOARD" >&2; exit 1; }
kver=$(awk '/^VERSION =/{v=$3} /^PATCHLEVEL =/{p=$3} END{print v "." p}' "$TREE/Makefile")
case $kver in
  7.1|7.2) ;;
  *)
    echo "Refusing Linux $kver. Boot 7.1.2-2.pipa.fc44 and patch a 7.1 pipadb tree." >&2
    exit 1
    ;;
esac
grep -q 'sm8250-xiaomi-pipa-camera.dtsi' "$BOARD" || {
  echo "Camera DTSI not included. Run: $HERE/scripts/patch-kernel-pipa-cameras.sh $TREE" >&2
  exit 1
}

BACKUP="${SUDO_HOME:-$HOME}/boot-linux-backup.img"
if [[ $BACKUP == /root/boot-linux-backup.img && -n ${SUDO_USER:-} ]]; then
  BACKUP=$(getent passwd "$SUDO_USER" | cut -d: -f6)/boot-linux-backup.img
fi

echo "==> backup Linux boot slot to $BACKUP"
if [[ ! -s $BACKUP ]]; then
  bootpart=
  for n in /dev/disk/by-partlabel/boot_b /dev/disk/by-partlabel/boot_a \
           /dev/block/by-name/boot_b /dev/block/by-name/boot_a; do
    [[ -e $n ]] || continue
    # Fedora is slot B in this dualboot; prefer boot_b if present.
    bootpart=$n
    [[ $n == *boot_b* ]] && break
  done
  [[ -n $bootpart ]] || { echo "no boot_a/boot_b char device" >&2; exit 1; }
  dd if="$bootpart" of="$BACKUP" bs=4M status=progress
  echo "saved $bootpart"
else
  echo "keeping existing $BACKUP"
fi

echo "==> build deps"
dnf install -y gcc gcc-c++ make flex bison openssl-devel elfutils-devel \
  bc python3 python3-pyyaml dwarves rsync ncurses-devel perl-interpreter \
  openssl openssl-devel-engine 2>/dev/null || \
dnf install -y gcc gcc-c++ make flex bison openssl-devel elfutils-devel \
  bc python3 python3-pyyaml dwarves rsync ncurses-devel perl

echo "==> .config from running kernel-pipa"
if [[ ! -f $TREE/.config ]]; then
  [[ -f /boot/config-$(uname -r) ]] || { echo "missing /boot/config-$(uname -r)" >&2; exit 1; }
  cp "/boot/config-$(uname -r)" "$TREE/.config"
fi
if [[ -x $TREE/scripts/kconfig/merge_config.sh ]]; then
  "$TREE/scripts/kconfig/merge_config.sh" -m -O "$TREE" "$TREE/.config" "$FRAG"
fi

make -C "$TREE" EXTRAVERSION="$EXTRAVERSION" olddefconfig
# Camera symbols must not stay =n after olddefconfig
for s in VIDEO_OV13B10 VIDEO_HI846 VIDEO_QCOM_CAMSS I2C_QCOM_CCI; do
  grep -q "^CONFIG_${s}=[my]" "$TREE/.config" || echo "CONFIG_${s}=m" >>"$TREE/.config"
done
make -C "$TREE" EXTRAVERSION="$EXTRAVERSION" olddefconfig

echo "==> compile (30–90 min on pipa)"
make -C "$TREE" EXTRAVERSION="$EXTRAVERSION" -j"$(nproc)" Image.gz modules dtbs
[[ -f $DTB ]] || { echo "dtb missing — camera dtsi failed to compile" >&2; exit 1; }

KVER=$(make -C "$TREE" EXTRAVERSION="$EXTRAVERSION" -s kernelrelease)
echo "==> install $KVER"
make -C "$TREE" EXTRAVERSION="$EXTRAVERSION" modules_install
MODDIR=/usr/lib/modules/$KVER
cp -f "$DTB" "$MODDIR/devicetree"
ln -sfn devicetree "$MODDIR/dtb"
cp -f "$TREE/arch/arm64/boot/Image.gz" "$MODDIR/vmlinuz"
cp -f "$TREE/arch/arm64/boot/Image.gz" "/boot/vmlinuz-$KVER"
cp -f "$TREE/System.map" "/boot/System.map-$KVER"
cp -f "$TREE/.config" "/boot/config-$KVER"
rm -f "$MODDIR/build" "$MODDIR/source"

depmod -a "$KVER"
dracut -f --kver "$KVER" "$MODDIR/initramfs.img"
kernel-install add "$KVER" "$MODDIR/vmlinuz" "$MODDIR/initramfs.img"

echo
echo "Installed $KVER and ran kernel-install (flashed Linux boot slot)."
echo "Reboot. Then:  cam --list"
echo "If black screen: fastboot flash boot_b $BACKUP && fastboot erase dtbo_b"
echo "Do not: dnf upgrade kernel-pipa  (COPR would overwrite this)."
