#!/usr/bin/env bash
# Unstick CAMSS after Meet/Messenger switches rear ↔ front.
# Qualcomm CAMSS on pipa can only stream one sensor; a failed HI846 STREAMON
# holds the ISP and the OV13B10 dies too until these modules reload.
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

echo "==> stop PipeWire (releases /dev/video*)"
as_user systemctl --user stop wireplumber pipewire-pulse pipewire || true
sleep 1

if [[ $(id -u) -ne 0 ]]; then
  echo "re-run with sudo to reload camera modules" >&2
  exit 1
fi

echo "==> reload hi846, ov13b10, qcom_camss"
modprobe -r hi846 ov13b10 qcom_camss 2>/dev/null || true
modprobe qcom_camss
modprobe ov13b10
modprobe hi846
sleep 1

echo "==> start PipeWire"
as_user systemctl --user start pipewire pipewire-pulse wireplumber

echo "Recovered. Do not hot-switch cameras in Meet."
echo "Front: start the call with Internal front already selected."
echo "Back:  start the call with Internal back already selected."
echo "Test front only:  cam -c 2 -s width=1280,height=720 -C 20"
