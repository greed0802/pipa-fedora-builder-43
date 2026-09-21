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

Rectangle/IPA-helper warnings are normal. Then:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
qcam          # preview; pick Internal front or Internal back
```

Meet / Messenger / Firefox: camera device **Internal front camera** or **Internal back camera**. Never Iris / random `videoN`.

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
