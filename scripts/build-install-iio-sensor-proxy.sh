#!/usr/bin/env bash
# Rebuild iio-sensor-proxy 3.9 with the pipa SSC fix series and install it as
# an RPM — on the running Pad, no image rebuild.
#
# Why: the sensor DSP and the FastRPC tunnel are fine (ssccli gets samples),
# but unpatched 3.9 never delivers measurements to clients — the probe
# close() during discovery breaks the later open, and the close signal
# handler kills measurement delivery. ArchPad, the Pad 6 Pro mainline tree
# and EndeavourOS pipa all carry this patch series; we vendor it in
# userspace-sensors/iio-sensor-proxy/patches.
#
# Run ON THE PAD, as root:
#   sudo ./scripts/build-install-iio-sensor-proxy.sh
#
# Revert to the COPR build any time:
#   sudo dnf distro-sync iio-sensor-proxy --repo=pocketblue:common
#
# Note: a future COPR build with a higher release replaces this one — that is
# fine once upstream carries equivalent fixes.
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: sudo ./scripts/build-install-iio-sensor-proxy.sh [tree-dir]

On the Xiaomi Pad 6 (aarch64 Fedora), as root:
  1. clone upstream iio-sensor-proxy tag 3.9 (gitlab, github fallback)
  2. apply the vendored SSC fix series (idempotent)
  3. meson build
  4. rpmbuild and install iio-sensor-proxy-3.9-2.pipa
  5. restart iio-sensor-proxy and run pipa-sensor-doctor
EOF
	exit 1
}

[[ ${1:-} == -h || ${1:-} == --help ]] && usage
[[ $(id -u) -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || { echo "run this on the Pad, not on a PC/WSL" >&2; exit 1; }

HERE=$(readlink -f "$(dirname "$0")/..")
PATCHDIR="$HERE/userspace-sensors/iio-sensor-proxy/patches"
SPEC="$HERE/userspace-sensors/iio-sensor-proxy/iio-sensor-proxy.spec"
TREE="${1:-$HOME/build/iio-sensor-proxy-3.9}"
[[ -f $SPEC ]] || { echo "spec missing: $SPEC — clone/pull the full repo" >&2; exit 1; }

echo "==> fetch upstream iio-sensor-proxy 3.9 into $TREE"
if [[ ! -d $TREE ]]; then
	mkdir -p "$(dirname "$TREE")"
	git clone --depth 1 --branch 3.9 \
		https://gitlab.freedesktop.org/hadess/iio-sensor-proxy.git "$TREE" ||
		git clone --depth 1 --branch 3.9 \
		https://github.com/hadess/iio-sensor-proxy.git "$TREE"
fi
grep -q "version: '3.9" "$TREE/meson.build" || {
	echo "$TREE is not 3.9 — remove it and re-run" >&2
	exit 1
}

echo "==> apply SSC fix series"
apply_one() {
	local p=$1
	if git -C "$TREE" apply --check "$p" >/dev/null 2>&1; then
		git -C "$TREE" apply "$p"
		echo "applied $(basename "$p")"
	elif git -C "$TREE" apply --reverse --check "$p" >/dev/null 2>&1; then
		echo "already applied $(basename "$p")"
	elif patch -d "$TREE" -p1 -R --dry-run -s -i "$p" >/dev/null 2>&1; then
		echo "already applied (patch) $(basename "$p")"
	elif patch -d "$TREE" -p1 -N --dry-run -i "$p" >/dev/null 2>&1; then
		patch -d "$TREE" -p1 -N -i "$p"
		echo "applied (patch) $(basename "$p")"
	else
		echo "SKIP (does not apply): $(basename "$p")" >&2
	fi
}
for p in "$PATCHDIR"/000{2,3,4,5}-*.patch; do
	apply_one "$p"
done

echo "==> build deps"
dnf install -y gcc meson ninja-build rpm-build \
	"pkgconfig(libssc)" "pkgconfig(gudev-1.0)" "pkgconfig(gio-2.0)" \
	"pkgconfig(polkit-gobject-1)"

echo "==> build"
meson setup "$TREE" "$TREE/build" --prefix /usr -Dssc-support=enabled -Dtests=false -Dgtk_doc=false
ninja -C "$TREE/build"

echo "==> rpm"
mkdir -p ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
rm -rf ~/rpmbuild/BUILD/iio-sensor-proxy-3.9
tar -C "$(dirname "$TREE")" \
	--transform "s,^$(basename "$TREE"),iio-sensor-proxy-3.9," \
	-czf ~/rpmbuild/SOURCES/iio-sensor-proxy-3.9.tar.gz "$(basename "$TREE")"
rpmbuild -ba --without=check "$SPEC"

echo "==> install"
dnf install -y ~/rpmbuild/RPMS/aarch64/iio-sensor-proxy-3.9-2.pipa*.rpm || \
	dnf upgrade -y ~/rpmbuild/RPMS/aarch64/iio-sensor-proxy-3.9-2.pipa*.rpm

if ldd /usr/libexec/iio-sensor-proxy | grep -q libssc; then
	echo "    installed binary links libssc"
else
	echo "    WARNING: binary does not link libssc?!" >&2
fi

echo "==> restart proxy + verify"
systemctl restart iio-sensor-proxy.service
sleep 2
"$HERE/mkosi.extra/usr/local/bin/pipa-sensor-doctor" || true

echo
echo "Now: sleep 20; monitor-sensor  — then tilt through all four orientations."
echo "Then the real test: sudo pipa-sensor-doctor --suspend-test"
echo "Revert: sudo dnf distro-sync iio-sensor-proxy --repo=pocketblue:common"
