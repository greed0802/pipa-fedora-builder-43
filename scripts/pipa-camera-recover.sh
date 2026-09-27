#!/usr/bin/env bash
# Unstick the camera after a call ends uncleanly (killed tab, crash, browser
# stuck at "Starting camera"), or before handing it to another browser.
#
# Reality on pipa (learned the hard way):
#  * WirePlumber's libcamera monitor always holds /dev/media0 + /dev/video0
#    open — that is NORMAL and does not block anyone.
#  * The wedge is a kernel-internal reference: a stream that never saw
#    STREAMOFF. It can survive with zero userspace fds, which is why
#    "who holds the node" is sometimes nobody.
#  * So the goal is not "unload modules" — it is "camera usable again".
#    This script tries, in order: nothing → WirePlumber restart → module
#    reload → full PipeWire stop + capture test → report, and only says
#    "reboot" when capture truly fails everywhere.
set -uo pipefail
# (no `set -e`: every step has its own fallback and reports for itself)

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

USER_UNITS="pipewire.socket pipewire-pulse.socket pipewire.service pipewire-pulse.service wireplumber.service"

stop_family() {
  # Sockets and services must stop in ONE transaction: stopping services
  # alone races socket activation and the jobs get canceled.
  as_user systemctl --user stop $USER_UNITS || true
  sleep 1
}

start_family() {
  as_user systemctl --user start $USER_UNITS || true
}

test_capture() {
  # The only verdict that matters. 20 s timeout so a wedged sensor cannot
  # hang the script.
  rm -f /tmp/pipa-cam-test.ppm
  timeout 20 cam -c 1 -s width=1280,height=720,role=viewfinder \
    --capture=1 --file=/tmp/pipa-cam-test.ppm >/dev/null 2>&1
  [[ -s /tmp/pipa-cam-test.ppm ]]
}

show_holders() {
  # fuser/lsof are not installed here; scan /proc directly. v4l-subdev*
  # included: subdevice fds pin the sensor module just as well.
  echo "    Open camera device fds:" >&2
  local fd tgt pid cmd found=""
  for fd in /proc/[0-9]*/fd/*; do
    tgt=$(readlink "$fd" 2>/dev/null) || continue
    case $tgt in
      /dev/video*|/dev/media*|/dev/v4l-subdev*|/dev/v4l2-*)
        pid=${fd#/proc/}; pid=${pid%%/*}
        cmd=$(tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null)
        echo "    pid $pid: ${cmd:-[no cmdline]} -> $tgt" >&2
        found=1 ;;
    esac
  done
  [[ -n $found ]] || echo "    (none — wedge is kernel-internal)" >&2
}

module_state() {
  lsmod | grep -E '^(qcom_camss|hi846|ov13b10)\b' >&2 || echo "    modules not loaded" >&2
}

try_module_reload() {
  echo "    modprobe -r hi846 ov13b10 qcom_camss:" >&2
  modprobe -r hi846 ov13b10 qcom_camss 2>&1 | sed 's/^/      /' >&2
  if lsmod | grep -q '^qcom_camss'; then
    return 1
  fi
  modprobe qcom_camss 2>&1 | sed 's/^/      /' >&2
  modprobe ov13b10 2>&1 | sed 's/^/      /' >&2
  modprobe hi846 2>&1 | sed 's/^/      /' >&2
  sleep 1
}

echo "==> step 0: is the camera already usable? (test capture, touch nothing)"
if test_capture; then
  echo "    Camera works as-is — no recovery needed. Restarting WirePlumber"
  echo "    so browsers re-scan devices, then done."
  start_family
  exit 0
fi

echo "==> step 1: light path — restart WirePlumber only (audio stays up)"
as_user systemctl --user stop wireplumber.service || true
sleep 1
if test_capture; then
  echo "    Camera usable after WirePlumber restart. Audio was never touched."
  start_family
  echo "Done. Rules: end calls with the app's Leave button; pick front/rear"
  echo "in the site's settings BEFORE enabling video; never flip mid-call."
  exit 0
fi

echo "==> step 2: reload camera modules (true reset of a stuck stream)"
if try_module_reload; then
  echo "    Modules reloaded cleanly."
  if test_capture; then
    start_family
    echo "Done — capture verified after module reset."
    exit 0
  fi
  echo "    Modules fresh but capture still fails; continuing." >&2
else
  echo "    Unload refused:" >&2
  module_state
  show_holders
fi

echo "==> step 3: full path — stop the whole user PipeWire family"
stop_family
if test_capture; then
  start_family
  echo "Camera usable again (module may still be pinned — harmless until"
  echo "reboot). Done."
  exit 0
fi

echo "==> step 4: last reset — module reload with everything stopped"
if try_module_reload; then
  if test_capture; then
    start_family
    echo "Done — capture verified after full stop + module reset."
    exit 0
  fi
else
  echo "    Unload refused even with all user services stopped:" >&2
  module_state
  show_holders
fi

start_family
echo "" >&2
echo "RECOVERY FAILED — the camera does not capture in any state." >&2
if lsmod | grep -q '^qcom_camss'; then
  echo "qcom_camss cannot unload with zero userspace holders: the kernel is" >&2
  echo "holding an internal reference (a stream that never got STREAMOFF)." >&2
  echo "Only a reboot clears it. Please capture evidence for the kernel" >&2
  echo "folks before rebooting:" >&2
  echo "  dmesg | grep -iE 'camss|hi846|ov13b' | tail -30" >&2
else
  echo "Modules unloaded but capture still fails — check:" >&2
  echo "  systemctl status hexagonrpcd-sdsp   (ISP firmware tunnel)" >&2
  echo "  dmesg | tail -30" >&2
fi
exit 1
