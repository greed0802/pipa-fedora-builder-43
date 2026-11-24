# Installation guide

Unlocked bootloader required. If you are still on MIUI 14, unlock **before**
updating to HyperOS. Use `fastboot` from Linux or macOS
([platform-tools](https://developer.android.com/tools/releases/platform-tools) or
`android-tools`). Fastboot on Windows is terminally unreliable on pipa.

Device keys, OrangeFox backups, `dtbo`, and GPT unbrick match the
[postmarketOS pipa wiki](https://wiki.postmarketos.org/wiki/Xiaomi_Pad_6_(xiaomi-pipa)).
Do **not** follow that page's U-Boot / `pmbootstrap` flash for these images —
see [DUALBOOT.md](./DUALBOOT.md) for the difference.

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

If the tablet is **already repartitioned** (including Tianma panels — no extra
flag), run `./scripts/flash.sh list` then dualboot with your partition name.

Once that partition exists:

```bash
./scripts/flash.sh dualboot --boot boot.img --root root.img --partition fedora
```

(`--linux-slot` defaults to `auto`: Fedora on the opposite of `current-slot`.)

Manual equivalent:

```bash
fastboot flash boot_b boot.img
fastboot flash -S 256M fedora root.img
fastboot erase dtbo_b
fastboot set_active b
fastboot reboot
```

Windows: always pass `-S 256M` on `root.img` or fastboot can `std::bad_alloc`.
Your partition name is `linux` if that is what GPT shows.

- Disable Android OTA updates or they will overwrite Fedora on slot B.
- Switch OS with `fastboot set_active a|b` (safest), `sudo pipa-switch-slot a|b`
  from Fedora, or [Boot Control](https://github.com/capntrips/BootControl) from Android.
- `linux` as a partition name is fine too: pass `--partition linux`.

</details>

## Upgrading from Fedora 44 to Fedora 45

There are two safe ways to move an existing pipa Fedora 44 install to Fedora 45.
**Back up your data first** (home directory, important configs, app data). Cross-release
upgrades on mobile hardware carry more risk than desktop upgrades.

### Recommended: reflash the Fedora 45 image

This is the cleanest path and avoids in-place upgrade issues.

1. Build or download the Fedora 45 image (`boot.img` + `root.img`).
2. Back up anything you care about from the device.
3. Flash the new image using the same path you used originally:
   - Singleboot: `./scripts/flash.sh singleboot --boot boot.img --root root.img`
   - Dualboot (partition already exists): `./scripts/flash.sh dualboot --boot boot.img --root root.img --partition fedora`
4. After first boot, change the default passwords (`user` / `root`).

### Advanced: in-place upgrade with dnf system-upgrade

Only attempt this if you are comfortable recovering from a bad boot. Make sure you have
a working fastboot setup and a known-good image before starting.

```bash
# On the device, as root:
sudo dnf upgrade --refresh
sudo dnf install dnf-plugin-system-upgrade
sudo dnf system-upgrade download --releasever=45
sudo dnf system-upgrade reboot
```

After the upgrade completes:

- Confirm the release: `cat /etc/os-release`
- Update packages: `sudo dnf upgrade --refresh`
- Reboot once more and verify Wi-Fi, GPU, audio, touch, and suspend.
- If the boot image/kernel comes from a COPR package, confirm the F45 package installed
  cleanly and the active boot slot has the expected kernel.

If the system fails to boot after an in-place upgrade, boot fastboot and reflash a known-good
`boot.img` (and `root.img` if needed). Keep the old Fedora 44 image around until F45 is verified.
