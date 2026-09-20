# Installation guide

Unlocked bootloader required. Use `fastboot` from Linux or macOS
([platform-tools](https://developer.android.com/tools/releases/platform-tools) or
`android-tools`). Fastboot on Windows is terminally unreliable on pipa.

Build images with [BUILD.md](./BUILD.md), or unzip `boot.img` and `root.img`
from a [release](https://github.com/rr1111/pipa-fedora-builder-43/releases).

**Credentials:** user `147147` · root `fedora` — change these after the first boot.

Reboot into bootloader with **Volume Down + Power**. After flashing, run
`fastboot reboot` and wait. Do not hold Power to force a reboot while UFS is
still writing.

<details>
  <summary><strong>Singleboot installation</strong></summary>

Replaces Android. Both boot slots and `userdata` become Fedora.

```bash
./scripts/flash.sh singleboot --boot boot.img --root root.img
```

Manual equivalent:

```bash
fastboot flash boot_ab boot.img
fastboot flash userdata root.img
fastboot erase dtbo
fastboot reboot
```

</details>

<details>
  <summary><strong>Dualboot installation (Android slot A, Fedora slot B)</strong></summary>

**This wipes Android userdata.** You must shrink `userdata` and create a GPT
partition named `fedora` before the flash commands below. The full walkthrough
(backup, temporary boot on `super`, `pipa-repartition-dualboot`, restore stock
`super`/`dtbo_a`, switch OS, unbrick) is in **[DUALBOOT.md](./DUALBOOT.md)**.

Once that partition exists:

```bash
./scripts/flash.sh dualboot --boot boot.img --root root.img --partition fedora --linux-slot b
```

Manual equivalent:

```bash
fastboot flash boot_b boot.img
fastboot flash fedora root.img
fastboot erase dtbo_b
fastboot set_active b
fastboot reboot
```

- Disable Android OTA updates or they will overwrite Fedora on slot B.
- Switch OS with `fastboot set_active a|b` (safest), `sudo pipa-switch-slot a|b`
  from Fedora, or [Boot Control](https://github.com/capntrips/BootControl) from Android.
- `linux` as a partition name is fine too: pass `--partition linux`.

</details>
