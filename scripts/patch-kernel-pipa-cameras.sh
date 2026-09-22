#!/usr/bin/env bash
# Apply ArchPad camera drivers + pipadb DTS bind onto a kernel-pipa source tree.
# Does NOT build the kernel. Does NOT replace kernel-pipa with linux-archpad-pipa.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: patch-kernel-pipa-cameras.sh /path/to/pipadb/linux

Assimilates ArchPad-Pipa camera support into kernel-pipa (pipadb/linux):
  - ov13b10 OF + dvdd/dovdd
  - hi846 pipa bring-up patches
  - sm8250-xiaomi-pipa-camera.dtsi (OV13B10 + HI846)
  - kconfig fragment

Then you still have to *build* that tree as kernel-pipa (WSL/aarch64) and
install the RPM / flash the new boot.img. This script never flashes.

Do not boot linux-archpad-pipa on Fedora: different initramfs/boot.img path.
EOF
  exit 1
}

[[ ${1:-} == -h || ${1:-} == --help ]] && usage
[[ $# -eq 1 ]] || usage

TREE=$(readlink -f "$1")
HERE=$(readlink -f "$(dirname "$0")/..")
PATCHES="$HERE/kernel-camera/patches"
DTSI_SRC="$HERE/kernel-camera/sm8250-xiaomi-pipa-camera.dtsi"
BOARD="$TREE/arch/arm64/boot/dts/qcom/sm8250-xiaomi-pipa.dts"
DTSI_DST="$TREE/arch/arm64/boot/dts/qcom/sm8250-xiaomi-pipa-camera.dtsi"

[[ -d $TREE && -f $BOARD ]] || {
  echo "Not a pipadb/linux tree (missing $BOARD)" >&2
  exit 1
}

kver=$(awk '/^VERSION =/{v=$3} /^PATCHLEVEL =/{p=$3} END{print v "." p}' "$TREE/Makefile")
case $kver in
  7.1|7.2) ;;
  *)
    echo "Refusing $TREE (Linux $kver). kernel-pipa is 7.1.x; 7.0.8-pipa-cam killed speakers." >&2
    echo "Clone the 7.1 tree, e.g.:" >&2
    echo "  git clone --depth 1 https://github.com/pipadb/linux.git ~/linux-pipa-71" >&2
    echo "  git -C ~/linux-pipa-71 fetch --depth 1 origin 8205db9b0e34f9be5064c9244cc5ad94c4aca9a6" >&2
    echo "  git -C ~/linux-pipa-71 checkout 8205db9b0e34f9be5064c9244cc5ad94c4aca9a6" >&2
    exit 1
    ;;
esac

apply_one() {
  local p=$1
  if git -C "$TREE" apply --check "$p" >/dev/null 2>&1; then
    git -C "$TREE" apply "$p"
    echo "applied $(basename "$p")"
  elif git -C "$TREE" apply --reverse --check "$p" >/dev/null 2>&1; then
    echo "already applied $(basename "$p")"
  elif patch -d "$TREE" -p1 -N --dry-run -i "$p" >/dev/null 2>&1; then
    patch -d "$TREE" -p1 -N -i "$p"
    echo "applied (patch) $(basename "$p")"
  else
    echo "SKIP (does not apply, tree may already have it): $(basename "$p")" >&2
  fi
}

shopt -s nullglob
for p in "$PATCHES"/000{1,2,3,4,5,6,7,8,9}-*.patch; do
  apply_one "$p"
done

cp -f "$DTSI_SRC" "$DTSI_DST"
echo "installed $(basename "$DTSI_DST")"

if ! grep -q 'sm8250-xiaomi-pipa-camera.dtsi' "$BOARD"; then
  printf '\n#include "sm8250-xiaomi-pipa-camera.dtsi"\n' >>"$BOARD"
  echo "included camera dtsi from board dts"
else
  echo "board dts already includes camera dtsi"
fi

if grep -q '/\* L2-4 are unused. \*/' "$BOARD"; then
  python3 - "$BOARD" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
text = p.read_text()
old = "\t\t/* L2-4 are unused. */\n"
new = """\t\tvreg_l2c_1p2: ldo2 {
\t\t\tregulator-name = \"vreg_l2c_1p2\";
\t\t\tregulator-min-microvolt = <1200000>;
\t\t\tregulator-max-microvolt = <1200000>;
\t\t\tregulator-initial-mode = <RPMH_REGULATOR_MODE_HPM>;
\t\t};

\t\tvreg_l3c_1p2: ldo3 {
\t\t\tregulator-name = \"vreg_l3c_1p2\";
\t\t\tregulator-min-microvolt = <1200000>;
\t\t\tregulator-max-microvolt = <1200000>;
\t\t\tregulator-initial-mode = <RPMH_REGULATOR_MODE_HPM>;
\t\t};

\t\t/* L4 is unused. */
"""
if old not in text:
    raise SystemExit("L2-4 marker not found after grep")
p.write_text(text.replace(old, new, 1))
PY
  echo "enabled PM8150C LDO2/LDO3 for camera digital rails"
elif grep -q 'vreg_l2c_1p2' "$BOARD" && grep -q 'vreg_l3c_1p2' "$BOARD"; then
  echo "LDO2/LDO3 already present"
else
  echo "WARNING: could not find 'L2-4 are unused' — add vreg_l2c_1p2 and vreg_l3c_1p2 by hand" >&2
fi

CFG=$TREE/.config
FRAG="$HERE/kernel-camera/config.fragment"
if [[ -f $CFG ]]; then
  if [[ -x $TREE/scripts/kconfig/merge_config.sh ]]; then
    "$TREE/scripts/kconfig/merge_config.sh" -m -O "$TREE" "$CFG" "$FRAG"
    echo "merged camera kconfig fragment"
  else
    echo "no merge_config.sh; append $FRAG to .config yourself"
  fi
else
  echo "no .config yet; after olddefconfig, merge $FRAG"
fi

echo
echo "Next (on WSL, aarch64 or cross):"
echo "  cd $TREE"
echo "  make ARCH=arm64 olddefconfig"
echo "  make ARCH=arm64 -j\$(nproc) Image dtbs modules"
echo "Install like kernel-pipa so /boot/dtb still ships qcom/sm8250-xiaomi-pipa.dtb"
echo "and the pipa boot.img hook flashes the active slot. Then on the Pad:"
echo "  cam --list"
