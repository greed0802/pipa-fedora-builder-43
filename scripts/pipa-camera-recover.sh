#!/usr/bin/env bash
# Unstick CAMSS after Meet/Messenger switches rear ↔ front, after a call
# ends uncleanly (killed tab/crash/suspend mid-call), or before handing the
# camera to another browser.
#
# Qualcomm CAMSS on pipa streams ONE sensor at a time; a stale holder or a
# failed STREAMON leaves the sensor busy and every next open hangs. This
# script tries the light path first (restart WirePlumber only — audio keeps
# flowing through PipeWire) and escalates to the full PipeWire restart only
# if the kernel modules are still pinned.
set -euo pipefail

as_user() {
  if [[ -n ${SUDO_USER:-} && $(id -u) -eq 0 ]]; then
    local uid
    uid=$(id -u "$SUDO_USER")
    sudo -u "$SUDO_USER" env XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
  else
    "$@"
  fi
}

if [[ $(id -u) -ne 0 ]]; then
  echo "re-run with sudo to reload camera modules" >&2
  exit 1
fi

reload_modules() {
  modprobe -r hi846 ov13b10 qcom_camss 2>/dev/null || true
  if lsmod | grep -q qcom_camss; then
    return 1
  fi
  modprobe qcom_camss
  modprobe ov13b10
  modprobe hi846
  sleep 1
}

echo "==> light path: restart WirePlumber only (audio stays up)"
as_user systemctl --user stop wireplumber || true
sleep 1

if reload_modules; then
  as_user systemctl --user start wireplumber
  echo "Recovered the light way. Audio was never touched."
else
  echo "==> modules pinned — full path: restart your PipeWire too"
  as_user systemctl --user stop pipewire-pulse pipewire.socket pipewire || true
  sleep 1
  if ! reload_modules; then
    echo "qcom_camss still in use — reboot the Pad instead of rmmod -f" >&2
    as_user systemctl --user start pipewire.socket pipewire pipewire-pulse wireplumber || true
    exit 1
  fi
  as_user systemctl --user start pipewire.socket pipewire pipewire-pulse wireplumber
fi

echo "Recovered. Rules of thumb:"
echo "  End calls with the app's Leave button (a killed tab wedges CAMSS)."
echo "  Pick front/rear in the site's settings BEFORE enabling video —"
echo "  never flip mid-call."
echo "Test:  cam -c 1 -s width=1280,height=720 --capture=1 --file=/tmp/t.ppm"
