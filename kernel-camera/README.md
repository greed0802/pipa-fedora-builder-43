# Assimilate ArchPad cameras into kernel-pipa

Fedora on pipa boots `kernel-pipa` from [pipadb/linux](https://github.com/pipadb/linux)
packaged by COPR. ArchPad’s `linux-archpad-pipa` is a **different** kernel
(vanilla 7.1.4 + patches, mkinitcpio, systemd-boot). Swapping that Image onto
Fedora `boot.img` is how you lose display/audio/slots.

This directory copies **only** ArchPad’s camera work onto pipadb:

| Piece | Origin |
| --- | --- |
| `patches/0001` ov13b10 OF + dvdd/dovdd | ArchPad 0007 (bluebunny / pmOS) |
| `patches/0002–0009` hi846 | ArchPad 0017–0025 |
| `sm8250-xiaomi-pipa-camera.dtsi` | ArchPad 0001 rear + 0021 front + 0028 rotation, retargeted at pipadb’s single `.dts` |
| `config.fragment` | ArchPad `CONFIG_VIDEO_{OV13B10,HI846,QCOM_CAMSS}` |

GPIO/regulator map is ArchPad’s reading of Xiaomi `pipa-t-oss`, not invented here.
VCM (DW9714 on CCI0 0x0c / L7 2.85 V) is **not** enabled — ArchPad never added
the VCM node, only `regulator-always-on` on L7.

## Build and install **on the Pad**

Do not `make ARCH=arm64` on WSL x86_64. Steps: [CAMERA.md](../CAMERA.md).

```bash
# on the Pad
~/pipa-fedora-builder-43/scripts/patch-kernel-pipa-cameras.sh ~/linux-pipa
sudo ~/pipa-fedora-builder-43/scripts/build-install-camera-kernel.sh ~/linux-pipa
```

## After install on the Pad

```bash
cam --list          # expect ov13b10 and/or hi846
dmesg | grep -iE 'ov13|hi846|camss|cci'
```
