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

show_holders() {
  # qcom_camss is pinned: some process still has /dev/video* or /dev/media*
  # open (a stuck browser claim, a hung `cam`, ...). Scan /proc directly —
  # fuser/lsof are not installed on this image.
  echo "    Devices still held by:" >&2
  local fd tgt pid cmd
  for fd in /proc/[0-9]*/fd/*; do
    tgt=$(readlink "$fd" 2>/dev/null) || continue
    case $tgt in
      /dev/video*|/dev/media*)
        pid=${fd#/proc/}; pid=${pid%%/*}
        cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)
        echo "    pid $pid: ${cmd:-[no cmdline]} -> $tgt" >&2 ;;
    esac
  done
}

# Stop the user session's PipeWire family. Sockets and services MUST go in
# one transaction: stopping services alone races socket activation and the
# stop jobs get canceled ("Job for pipewire.socket canceled").
stop_pipewire_family() {
  as_user systemctl --user stop \
    pipewire.socket pipewire-pulse.socket \
    pipewire.service pipewire-pulse.service wireplumber.service || true
  sleep 1
}

echo "==> light path: restart WirePlumber only (audio stays up)"
as_user systemctl --user stop wireplumber.service || true
sleep 1

if reload_modules; then
  as_user systemctl --user start wireplumber.service
  echo "Recovered the light way. Audio was never touched."
else
  show_holders
  echo "==> modules pinned — full path: stop the whole user PipeWire family"
  stop_pipewire_family
  if ! reload_modules; then
    show_holders
    echo "Close/kill the processes above and re-run this script." >&2
    echo "If nothing is listed, reboot the Pad (do not rmmod -f)." >&2
    as_user systemctl --user start pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service || true
    exit 1
  fi
  as_user systemctl --user start pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service
fi

echo "Recovered. Rules of thumb:"
echo "  End calls with the app's Leave button (a killed tab wedges CAMSS)."
echo "  Pick front/rear in the site's settings BEFORE enabling video —"
echo "  never flip mid-call."
echo "Test:  cam -c 1 -s width=1280,height=720 --capture=1 --file=/tmp/t.ppm"
