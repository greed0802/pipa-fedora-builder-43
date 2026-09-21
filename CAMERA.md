# Cameras on pipa Fedora

`cam --list` showing **No sensor found** with many `/dev/video*` nodes is expected
on stock `kernel-pipa`. Those nodes are CAMSS ISP + Iris, not OV13B10 / HI846.

## Install the patched kernel (on the Pad, not WSL)

WSL only **patched source**. `make ARCH=arm64` on the laptop builds the wrong
arch. Compile and `kernel-install` on the tablet so `pipa-kernel-flasher-hook`
writes Fedora’s `boot.img` the same way `dnf` does.

### 1. On the Pad (Konsole, Wi‑Fi)

```bash
sudo dnf install -y git
cd ~
git clone --depth 1 https://github.com/pipadb/linux.git linux-pipa
git clone --depth 1 -b arena/01a0bd69-pipa-fedora-builder-43 \
  https://github.com/greed0802/pipa-fedora-builder-43.git
cd pipa-fedora-builder-43
./scripts/patch-kernel-pipa-cameras.sh ~/linux-pipa
sudo ./scripts/build-install-camera-kernel.sh ~/linux-pipa
```

That takes **30–90 minutes**. It saves `~/boot-linux-backup.img` first.

If you already patched `~/linux-pipa` in WSL, copy that tree to the Pad
instead of cloning again (`scp -r` from WSL, or a USB stick). Still **build
on the Pad**.

### 2. Reboot, still Fedora slot B

```bash
cam --list
dmesg | grep -iE 'ov13|hi846|cci'
```

Expect:

```
Available cameras:
1: Internal back camera (.../camera@10)
2: Internal front camera (.../camera@20)
```

Rectangle/IPA-helper warnings are normal. Fedora’s `libcamera-tools` has `cam`, not `qcam`:

```bash
sudo dnf install -y libcamera-qcam libcamera-gstreamer gstreamer1-plugins-good
systemctl --user restart pipewire pipewire-pulse wireplumber
qcam
# or:
cam -c 1 -s width=1280,height=720 --capture=20   # back
cam -c 2 -s width=1280,height=720 --capture=20   # front (2-lane; do not request 3264x*)
```

Meet / Messenger / Firefox: **Internal front camera** or **Internal back camera**. Never Iris / random `videoN`.

**Do not switch cameras mid-call.** CAMSS can stream one sensor. Opening HI846 while OV13B10 is live hangs the ISP and **both** cameras die.

Never run `sudo systemctl --user …` — that stops **root’s** empty session and leaves **your** PipeWire (speakers + mics) dead, while `qcom_camss` stays busy.

Fastest recover: **reboot**.

Or, as `user` (sudo only on modprobe):

```bash
systemctl --user stop wireplumber pipewire-pulse pipewire
sudo modprobe -r hi846 ov13b10 qcom_camss
sudo modprobe qcom_camss ov13b10 hi846
systemctl --user start pipewire pipewire-pulse wireplumber
```

If `qcom_camss is in use`, reboot. Then start a **new** Meet tab with the camera already chosen.

Then start a **new** Meet tab with the camera you want already chosen (site settings), not the in-call switcher.

If the plugin was installed after login, log out once so PipeWire reloads `pipewire-plugin-libcamera`.

### 3. If the panel stays black

PC + WSL/`usbipd` (not Windows `fastboot` for this):

```bash
fastboot flash boot_b ./boot-linux-backup.img
fastboot erase dtbo_b
fastboot set_active b
```

Copy `boot-linux-backup.img` off the Pad **before** you reboot into a bad kernel
(KDE, USB stick, or `scp`).

Do **not** `dnf upgrade kernel-pipa` after this — COPR would replace the camera
kernel. Do **not** flash `linux-archpad-pipa`.

Userspace IPA files (for a future image rebuild):
`mkosi.extra/usr/share/libcamera/ipa/simple/{ov13b10,hi846}.yaml`.
On the running Pad, copy them if missing:

```bash
sudo mkdir -p /usr/share/libcamera/ipa/simple
sudo cp ~/pipa-fedora-builder-43/mkosi.extra/usr/share/libcamera/ipa/simple/*.yaml \
  /usr/share/libcamera/ipa/simple/
```
