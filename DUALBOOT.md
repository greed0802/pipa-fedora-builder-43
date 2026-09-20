# Dualboot Android + Fedora on Xiaomi Pad 6 (pipa)

Hardware facts (keys, backups, `dtbo`, qbootctl bricks) follow the
[postmarketOS pipa wiki](https://wiki.postmarketos.org/wiki/Xiaomi_Pad_6_(xiaomi-pipa)).
The **install method on that page is not this project.**

| | This Fedora builder | postmarketOS wiki (current) |
| --- | --- | --- |
| Bootloader | Stock ABL + Android `boot.img` | U-Boot as *secondary* bootloader on `boot` |
| Rootfs | ext4 `root.img` on `userdata` or a `fedora` partition | `pmbootstrap flasher flash_rootfs` |
| Dualboot | Slot A Android / slot B Fedora | Not documented there (U-Boot + one Linux) |
| Panel (CSOT / Tianma) | `kernel-pipa` ships both | Chosen at `pmbootstrap init` |

Do **not** flash the wiki's U-Boot image over this project's `boot.img`.
`dnf` kernel updates re-flash the active Android boot slot; U-Boot would be
wiped, and `pmbootstrap flasher flash_kernel` would wipe Fedora the same way.

This is the A/B-slot layout used by the original pipa Fedora images and ARMtix:

| Slot | OS | boot | dtbo | rootfs |
| --- | --- | --- | --- | --- |
| A | Android / HyperOS | stock `boot_a` | stock `dtbo_a` | `userdata` |
| B | Fedora | this project's `boot.img` | **erased** `dtbo_b` | GPT partition named `fedora` |

Linux boots because `dtbo` on that slot is empty. If it is not erased, mainline
Linux will not boot at all. Android keeps its overlay on slot A. Kernel updates
from `dnf` flash the *active* slot, so stay on slot B while you are in Fedora.

**You cannot keep Android's current userdata.** Shrinking `userdata` on an FBE
device destroys the encrypted Android data. Back up first.

The Fedora 44 images themselves are the same for singleboot and dualboot.
What changes is the GPT and which slot you flash. Follow the steps in order.
Do not run a batch of commands you have not read.

## What you need

- Unlocked bootloader. If you are still on **MIUI 14, do not update to HyperOS
  before unlocking** — Xiaomi makes it much harder afterwards
  ([pmOS unlocking notes](https://wiki.postmarketos.org/wiki/Unlocking_Bootloaders#Xiaomi)).
- A PC running Linux or macOS with `fastboot` / `adb` (`android-tools`).
  Fastboot on Windows is unreliable for this device.
- This project's `boot.img` and `root.img` (build them, or unzip a [release](https://github.com/rr1111/pipa-fedora-builder-43/releases))
- A HyperOS **fastboot** ROM for **your** region, to restore `super` / `dtbo_a` after the temporary Linux boot:
  - Global/EEA `23043RP34G`
  - China `23043RP34C`
  - India `23043RP34I`
  Do not cross-flash CN and Global packages.
- USB-C cable, and a keyboard (official folio, or USB-C after Linux is up).
  U-Boot USB host is broken on this SoC; that does not apply once Fedora's
  kernel is running.
- Enough space: Plasma root.img is typically 8–12 GiB. Give Fedora **24 GiB or more**.

### Keys

- **Fastboot:** hold **Power + Volume Down**
- **Android recovery:** hold **Power + Volume Up** (Android only; gone once
  that slot is Linux)

## 0. Backup (OrangeFox + `adb pull`)

Copy off anything you care about from Android first.

Boot [OrangeFox for pipa](https://sourceforge.net/projects/recovery-for-xiaomi-devices/files/pipa/)
once — same procedure as the wiki. Rename the image to `recovery.img`:

```bash
fastboot boot recovery.img
```

Optional: note the panel variant (Fedora does not ask, but it is useful if you
ever build pmOS). In the recovery shell:

```bash
adb shell grep -o 'msm_drm[^ ]*' /proc/cmdline
```

- CSOT: `msm_drm.dsi_display0=qcom,mdss_dsi_m82_42_02_0b_dual_dphy_video:`
- Tianma: `msm_drm.dsi_display0=qcom,mdss_dsi_m82_36_02_0a_dual_dphy_video:`

Pull the partitions you are about to replace:

```bash
adb pull /dev/block/by-name/super super.img
adb pull /dev/block/by-name/boot_a boot_a.img
adb pull /dev/block/by-name/boot_b boot_b.img
adb pull /dev/block/by-name/dtbo_a dtbo_a.img
adb pull /dev/block/by-name/dtbo_b dtbo_b.img
```

`super.img` is large. Skip it only if you will reflash a full fastboot ROM.

Also record:

```bash
fastboot getvar current-slot
fastboot getvar product          # should be pipa
```

## 1. Temporary Fedora on `super` (so you can edit the GPT)

`super` is only a staging area. Android will not boot until you restore it.

Reboot to bootloader (Volume Down + Power):

```bash
fastboot flash boot_ab boot.img
fastboot flash super root.img
fastboot erase dtbo_ab
fastboot reboot
```

Wait. Do **not** hold Power to force a reboot while the image is still writing.

Log in: `user` / `147147` (or `root` / `fedora`). Open a terminal.

## 2. Shrink userdata, create `fedora`

On the tablet:

```bash
sudo pipa-repartition-dualboot --android-size 80G
```

That is a dry run. `80G` is Android's new userdata size; Fedora gets the rest.
Pick numbers that fit your 128/256 GiB UFS. Then:

```bash
sudo pipa-repartition-dualboot --android-size 80G --apply
```

Copy `/root/pipa-gpt-backup.bin` off the tablet (`scp`, USB gadget, etc.)
**before** you reboot.

If you would rather click around, `sudo cfdisk /dev/sda` works too: resize
`userdata`, create a new partition in the free space, `sudo parted /dev/sda name <N> fedora`.
Do not touch any partition other than `userdata` and the new one.

## 3. Wipe Android userdata and restore Android on slot A

Back to fastboot (Volume Down + Power):

```bash
fastboot -w
```

Reflash stock `super` and slot-A dtbo from the HyperOS fastboot ROM `images/`
directory (paths vary slightly by package):

```bash
fastboot flash super images/super.img
fastboot flash dtbo_a images/dtbo.img
fastboot flash boot_a images/boot.img
```

If the ROM uses sparse `super.img`, `fastboot flash super` still accepts it.
Do **not** flash `dtbo_b` — Fedora needs it empty.

If Android was already a custom ROM you want to keep, flash that ROM's
`super` / `boot_a` / `dtbo_a` instead.

## 4. Flash Fedora to slot B

From the directory that contains this repo's `boot.img` and `root.img`:

```bash
./scripts/flash.sh dualboot --boot boot.img --root root.img --partition fedora --linux-slot b
```

Equivalent manual commands (the original INSTALL.md was missing `set_active`):

```bash
fastboot flash boot_b boot.img
fastboot flash fedora root.img
fastboot erase dtbo_b
fastboot set_active b
fastboot reboot
```

The `fedora` partition must be **larger** than `root.img`. First boot grows
the ext4 filesystem (`x-systemd.growfs` in fstab).

## 5. Switch between Android and Fedora

| From | To Android (slot A) | To Fedora (slot B) |
| --- | --- | --- |
| PC (safest) | `fastboot set_active a && fastboot reboot` | `fastboot set_active b && fastboot reboot` |
| Fedora | `sudo pipa-switch-slot a` then reboot | — |
| Android (root) | — | [Boot Control](https://github.com/capntrips/BootControl) → slot B, reboot |

Disable Android OTA updates. An OTA on slot B overwrites Fedora's `boot_b`.

`pipa-switch-slot` is a wrapper around `qbootctl`. The wiki documents that
switching the ABL slot from userspace can leave pipa in an endless fastboot
loop. Prefer `fastboot set_active` when a PC is nearby. Recovery is below.

## Unbrick / fastboot loop

Same recovery as the wiki: reflash GPT from a Xiaomi **fastboot** firmware
archive (`images/gpt_both*.bin` inside the unpacked `.tgz`). No EDL required.

```bash
fastboot flash partition:1 gpt_both1.bin
fastboot flash partition:2 gpt_both2.bin
fastboot flash partition:3 gpt_both3.bin
fastboot flash partition:4 gpt_both4.bin
fastboot flash partition:5 gpt_both5.bin
fastboot reboot
```

That restores the **stock** partition table (Fedora's extra partition is gone).
You can also `sgdisk --load-backup=pipa-gpt-backup.bin` from a temporary Linux
if you still have the file from step 2.

## Going back to Android-only

Flash a full HyperOS package with `./flash_all.sh` (**not** `flash_all_lock.sh`).
That restores stock GPT, `super`, both boot slots, and userdata.

## After Fedora is up

These are device quirks from the same wiki; they apply on Fedora too:

- **Sensors** talk through the Hexagon DSP and often die after suspend.
  `sudo systemctl restart hexagonrpcd-sdsp` (or install `pipa-sensor-restart`).
- **HDMI/DP:** unplug the monitor from power before plugging the cable in.
- **Speakers:** AW88261 on tertiary TDM; a right-channel-only test tone can
  be silent even when the left speaker works.
- **Rear camera** may work poorly; **front camera** does not.

## Why not EFI / U-Boot multiboot?

Some pipa ports (TheMojoMan, nabu-style DBKP, current pmOS) boot Linux via
UEFI/U-Boot. This project ships an Android `boot.img` that the kernel-install
hook re-flashes on `dnf update`. Slot-based dualboot matches that model: one
Linux, one Android, no extra bootloader.

If you already have an `esp` + `linux` layout from another distro, you can
still `fastboot flash linux root.img` and `fastboot flash boot_b boot.img` —
use `--partition linux` — as long as you accept that kernel updates will write
`boot.img` to whichever slot is active.
