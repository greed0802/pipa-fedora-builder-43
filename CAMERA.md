# Cameras on pipa Fedora

`cam --list` showing **No sensor found** with many `/dev/video*` nodes is expected
on this kernel. Those nodes are the Qualcomm CAMSS ISP and Venus decoder, not
the OV13B10 / HI846 chips.

## Why this builder cannot “enable” the sensors

`kernel-pipa` (from [pipadb/linux](https://github.com/pipadb/linux)
`sm8250-xiaomi-pipa.dts`) has **no** `camss` / `cci` / `ov13b10` / `hi846`
board nodes. Without that device tree, libcamera has nothing to open. Guessing
GPIOs and regulators in an overlay can brown out the PMIC — we will not ship
that.

Userspace (Meet, Messenger, Firefox) can only use a camera after `cam --list`
prints a real sensor. This image now preinstalls:

- `libcamera`, `libcamera-ipa`, `libcamera-tools`, `libcamera-v4l2`
- `pipewire-plugin-libcamera`, `v4l-utils`

so the stack is ready when `kernel-pipa` grows camera DT.

## On a running tablet

```bash
cam --list
v4l2-ctl --list-devices
dmesg | grep -iE 'ov13|hi846|camss|cci'
```

Empty `cam --list` → use a USB webcam, or wait for a kernel-pipa release that
binds the sensors (ArchPad’s kernel claims this; it is a different tree).

Do not pick “Iris Decoder” or random `videoN` in Google Meet.

## If a future kernel lists ov13b10

```bash
qcam
# system Firefox, Meet → Settings → Video → ov13b10
```
