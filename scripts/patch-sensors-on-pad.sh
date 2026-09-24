#!/usr/bin/env bash
# Apply the sensor stack onto a RUNNING pipa Fedora install — no image rebuild.
#
# This is the userspace twin of patch-kernel-pipa-cameras.sh: it copies the
# mkosi.extra sensor overlay onto the live rootfs, installs the COPR packages
# and activates everything. Same result as building a fresh image with the
# new build.sh; nothing here touches the kernel or boot partition.
#
# Run ON THE PAD, as root:
#   sudo ./scripts/patch-sensors-on-pad.sh
#
# Safe to re-run (idempotent). Revert by removing the files listed at the
# end of SENSORS.md and `dnf remove pipa-sensors`.
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: sudo ./scripts/patch-sensors-on-pad.sh

On the Xiaomi Pad 6 (Fedora, aarch64):
  1. dnf install pipa-sensors libssc iio-sensor-proxy hexagonrpc (COPR repos)
  2. copy the mkosi.extra sensor overlay onto the live rootfs
  3. tmpfiles + persist registry + daemon-reload + udev reload
  4. enable & start pipa-sensors-persist, hexagonrpcd-sdsp,
     iio-sensor-proxy, pipa-sensor-resume
  5. run pipa-sensor-doctor to verify

No reboot needed. If the desktop was already running, toggle screen
rotation once (or relogin) so it re-claims the accelerometer.
EOF
	exit 1
}

[[ ${1:-} == -h || ${1:-} == --help ]] && usage
[[ $# -eq 0 ]] || usage
[[ $(id -u) -eq 0 ]] || { echo "run as root (sudo)" >&2; exit 1; }
[[ $(uname -m) == aarch64 ]] || {
	echo "This is $(uname -m). Run this on the Pad, not on a PC/WSL." >&2
	exit 1
}

HERE=$(readlink -f "$(dirname "$0")/..")
EXTRA="$HERE/mkosi.extra"
[[ -f $EXTRA/etc/udev/rules.d/81-libssc-xiaomi-pipa.rules ]] || {
	echo "overlay missing under $EXTRA — clone/pull the full repo" >&2
	exit 1
}

echo "==> install packages (pocketblue/reyr111 COPR repos)"
dnf install -y pipa-sensors libssc iio-sensor-proxy hexagonrpc

# The proxy must be built with SSC support (libssc). Fedora's stock build has
# none and would silently ignore the accelerometer.
if ldd /usr/libexec/iio-sensor-proxy 2>/dev/null | grep -q libssc; then
	echo "    iio-sensor-proxy has SSC (libssc) support"
else
	echo "    WARNING: /usr/libexec/iio-sensor-proxy does NOT link libssc." >&2
	echo "    Fedora's stock package ignores SSC sensors. Force the pocketblue:common build:" >&2
	echo "      dnf upgrade --refresh 'iio-sensor-proxy' --enablerepo='pocketblue:common'" >&2
fi

echo "==> copy overlay onto the live rootfs"
install -Dm644 "$EXTRA/etc/udev/rules.d/81-libssc-xiaomi-pipa.rules" \
	/etc/udev/rules.d/81-libssc-xiaomi-pipa.rules
install -Dm644 "$EXTRA/usr/lib/tmpfiles.d/pipa-sensors.conf" \
	/usr/lib/tmpfiles.d/pipa-sensors.conf
for unit in \
	usr/lib/systemd/system/pipa-sensors-persist.service \
	usr/lib/systemd/system/pipa-sensor-resume.service \
	usr/lib/systemd/system/hexagonrpcd-sdsp.service.d/pipa.conf \
	usr/lib/systemd/system/iio-sensor-proxy.service.d/pipa.conf \
	usr/lib/systemd/system-sleep/pipa-sensor-restart; do
	install -Dm644 "$EXTRA/$unit" "/$unit"
done
for bin in pipa-prepare-sensor-persist pipa-wait-ssc pipa-sensor-resume pipa-sensor-doctor; do
	install -Dm755 "$EXTRA/usr/local/bin/$bin" "/usr/local/bin/$bin"
done

echo "==> activate"
systemd-tmpfiles --create /usr/lib/tmpfiles.d/pipa-sensors.conf
/usr/local/bin/pipa-prepare-sensor-persist
systemctl daemon-reload
udevadm control --reload
if [ -e /dev/fastrpc-sdsp ]; then
	udevadm trigger --subsystem-match=misc --sysname-match=fastrpc-sdsp || true
else
	echo "    /dev/fastrpc-sdsp not present yet (SLPI still booting?) — udev will start the tunnel when it appears"
fi

systemctl enable --now pipa-sensors-persist.service hexagonrpcd-sdsp.service pipa-sensor-resume.service
systemctl enable --now iio-sensor-proxy.service

echo
echo "==> verify"
/usr/local/bin/pipa-sensor-doctor || true

echo
echo "Done. Rotation check: run 'monitor-sensor' and tilt the pad."
echo "Full suspend cycle check: sudo pipa-sensor-doctor --suspend-test"
echo "If rotation is dead in an already-running desktop: toggle rotation once,"
echo "or 'systemctl restart iio-sensor-proxy' (GNOME/KDE re-claim on the new proxy)."
