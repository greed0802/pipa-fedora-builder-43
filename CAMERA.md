# Cameras on pipa Fedora

`cam --list` showing **No sensor found** with many `/dev/video*` nodes is expected
on stock `kernel-pipa`. Those nodes are CAMSS ISP + Iris, not OV13B10 / HI846.

## Assimilate ArchPad into kernel-pipa (not a kernel swap)

ArchPad claims working cameras. Their kernel is **not** drop-in on this Fedora
image. Use [kernel-camera/](./kernel-camera/README.md) and:

```bash
./scripts/patch-kernel-pipa-cameras.sh /path/to/pipadb/linux
```

That patches **pipadb/linux** with ArchPad’s ov13b10/hi846 drivers and a camera
DTSI. You must rebuild/install that as `kernel-pipa` (WSL). This mkosi tree
cannot produce a new `boot.img` by itself.

Userspace already ships libcamera + PipeWire plugin + IPA YAML
(`mkosi.extra/usr/share/libcamera/ipa/simple/{ov13b10,hi846}.yaml`).

## On a running tablet (stock kernel)

```bash
cam --list
v4l2-ctl --list-devices
dmesg | grep -iE 'ov13|hi846|camss|cci'
```

Empty `cam --list` → USB webcam, or the patched kernel above.

Do not pick “Iris Decoder” in Meet.
