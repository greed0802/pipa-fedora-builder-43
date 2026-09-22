# Cameras on pipa Fedora

Stock COPR `kernel-pipa` exposes CAMSS / Iris `/dev/video*` nodes but **no
sensors**. `cam --list` → `No sensor found` is expected until the board DTS
binds OV13B10 (rear) and HI846 (front).

Do **not** flash ArchPad `linux-archpad-pipa` onto Fedora. Different initramfs
and boot.img path; that is how display/audio/slots break.

## What actually works (tested on Pad 6, Fedora 44, slot B)

| Kernel | Sensors | Speakers |
| --- | --- | --- |
| COPR `kernel-pipa` **7.1.2-2** | no | yes |
| pipadb branch **`pipa/7.1`** (= **7.1.0**) | yes | **no** (`/dev/snd` = `timer` only, Dummy Output) |
| pipadb commit **`8205db9`** (**7.1.7**) + this `kernel-camera/` | **ov13b10 + hi846** | **yes** (after ADSP firmware is in the initramfs) |

HI846 `rotation` in `kernel-camera/sm8250-xiaomi-pipa-camera.dtsi` (Meet, pad in
landscape): **270** inverted, **90** clockwise, **0** upside-down, **180**
upright. Rear OV13B10 stays **90**.

## Build on the Pad (not WSL)

`make ARCH=arm64` on an x86_64 laptop produces the wrong Image. Compile and
`kernel-install` on the tablet so `pipa-kernel-flasher-hook` writes `boot.img`
the same way `dnf` does.

```bash
sudo dnf install -y git
# Do not: git clone --depth 1 pipadb/linux  (default = 7.0.8, kills PCM)
# Do not: git clone --branch pipa/7.1       (that is 7.1.0, cameras, no PCM)
mkdir -p ~/linux-pipa-71
git -C ~/linux-pipa-71 init
git -C ~/linux-pipa-71 remote add origin https://github.com/PipaDB/linux.git
git -C ~/linux-pipa-71 fetch --depth 1 origin 8205db9b0e34f9be5064c9244cc5ad94c4aca9a6
git -C ~/linux-pipa-71 checkout FETCH_HEAD
# Makefile must read VERSION=7 PATCHLEVEL=1 SUBLEVEL=7

git clone --depth 1 https://github.com/rr1111/pipa-fedora-builder-43.git
cd pipa-fedora-builder-43
./scripts/patch-kernel-pipa-cameras.sh ~/linux-pipa-71
sudo ./scripts/build-install-camera-kernel.sh ~/linux-pipa-71
```

30–90 minutes. The install script saves `~/boot-linux-backup.img` first.

If `~/linux-pipa-71` is root-owned from a previous `sudo` build, later `make dtbs`
fails with `Permission denied` on `include/config/kernel.release`. Use
`sudo make EXTRAVERSION=-pipa-cam dtbs` or `sudo rm -rf ~/linux-pipa-71` and
clone again.

## ADSP / Dummy Output

`adsp.mbn` lives on the rootfs:

`/usr/lib/firmware/qcom/sm8250/xiaomi/pipa/adsp.mbn`

A custom `7.1.7-pipa-cam+` initramfs often **omits** it. Then:

```
remoteproc2: Direct firmware load for qcom/sm8250/xiaomi/pipa/adsp.mbn failed with error -2
```

`/dev/snd` is `timer` only → PipeWire Dummy Output. The four AW88261 amps still
probe. After the rootfs is mounted you can start ADSP by hand:

```bash
# already offline → echo stop is EINVAL; just start
sudo sh -c 'echo start > /sys/class/remoteproc/remoteproc2/state'
ls /dev/snd   # expect controlC0 pcmC0D*
systemctl --user restart pipewire.socket pipewire pipewire-pulse wireplumber
wpctl status  # Built-in Audio Speaker, not Dummy
```

So it survives reboot, put firmware in the initramfs **before** the next
`kernel-install`:

```bash
echo 'install_items+=" /usr/lib/firmware/qcom/sm8250/xiaomi/pipa/* "' \
  | sudo tee /etc/dracut.conf.d/pipa-adsp.conf
sudo dracut -f --kver "$(uname -r)"
sudo kernel-install add "$(uname -r)" /usr/lib/modules/"$(uname -r)"/vmlinuz
```

Do **not** `dnf upgrade kernel-pipa` after this — COPR would replace the camera
kernel. Upstream hope: merge this DTS into `kernel-pipa` so `dnf` is enough.

## After reboot

```bash
uname -r   # 7.1.7-pipa-cam+
cam --list
```

```
Available cameras:
1: Internal front camera (.../cci@ac50000/i2c-bus@1/camera@20)   # hi846
2: Internal back camera  (.../cci@ac4f000/i2c-bus@0/camera@10)   # ov13b10
```

Rectangle / IPA-helper warnings are noise.

```bash
# qcam always picks max Bayer (rear 4208×3120) and dies:
#   Failed to allocate capture buffers (dma-heap)
# CmaTotal 128 MiB is still too small for 13 MP. Use 720p:
cam -c 1 -s width=1280,height=720,role=viewfinder --capture=5 -F /tmp/back-#.ppm
```

Meet / Firefox: **Built-in Back Camera** or **Built-in Front Camera** (libcamera).
Never Iris, never a raw `videoN`.

**Do not switch cameras in-call.** CAMSS is one pipeline. Opening HI846 while
OV13B10 is streaming hangs the ISP; both cameras die until reboot (or
`modprobe -r` if the modules are not busy). Leave the call, pick **one** camera
in site settings, join again.

Never `sudo systemctl --user …` — that talks to **root’s** empty session and
kills **your** PipeWire (speakers).

DTB-only rotation change (tree already patched):

```bash
sudo make -C ~/linux-pipa-71 EXTRAVERSION=-pipa-cam dtbs
sudo cp ~/linux-pipa-71/arch/arm64/boot/dts/qcom/sm8250-xiaomi-pipa.dtb \
  /usr/lib/modules/"$(uname -r)"/devicetree
sudo kernel-install add "$(uname -r)" /usr/lib/modules/"$(uname -r)"/vmlinuz
```

Confirm live DT (fish: no `while read`):

```bash
find /sys/firmware/devicetree/base -name rotation -print -exec xxd {} \;
# camera@10 (rear)  0000 005a  = 90
# camera@20 (front) 0000 00b4  = 180
```

## Black screen after a bad kernel

PC + WSL/`usbipd` (not Windows `fastboot` for this):

```bash
fastboot flash boot_b ./boot-linux-backup.img
fastboot erase dtbo_b
fastboot set_active b
```

Copy `boot-linux-backup.img` off the Pad **before** you reboot into a kernel
you have not tried.

## This directory

| Path | Role |
| --- | --- |
| `kernel-camera/sm8250-xiaomi-pipa-camera.dtsi` | OV13B10 + HI846 bind, GPIOs from ArchPad / Xiaomi `pipa-t-oss` |
| `kernel-camera/patches/0001–0009` | ov13b10 OF + hi846 bring-up (ArchPad) |
| `kernel-camera/config.fragment` | `VIDEO_{OV13B10,HI846,QCOM_CAMSS}`, CMA 128 MiB |
| `scripts/patch-kernel-pipa-cameras.sh` | apply onto a pipadb 7.1.2+ tree |
| `scripts/build-install-camera-kernel.sh` | Pad-side `make` + `kernel-install` |

Userspace IPA stubs (optional): `mkosi.extra/usr/share/libcamera/ipa/simple/{ov13b10,hi846}.yaml`.
