# macOS feasibility on Xiaomi Pad 6 (pipa)

## Bottom line

This repository targets Fedora on the Xiaomi Pad 6 (Qualcomm Snapdragon 870 / SM8250 family). It does **not** provide a macOS port. There is no known, demonstrated bootable macOS implementation for this device in this project. A conventional PC Hackintosh guide, an x86 OpenCore EFI, or an existing Apple-silicon macOS image is not a drop-in solution for this ARM tablet. Do not flash an image or repartition the tablet in pursuit of this plan.

macOS for Apple silicon targets Apple platforms; sharing the ARM64 instruction set does not make its boot chain, platform firmware, device drivers, or hardware interfaces compatible with Qualcomm hardware. OpenCore is a boot manager, not a replacement for the missing platform and device support. The Linux device tree, kernel and Fedora drivers in this repository cannot be used as macOS kernel extensions. Building a complete port would require substantial low-level research and development, and even a successful boot would not imply working graphics or peripherals. Apple software licensing and distribution terms also need to be reviewed; see [Apple's software license agreements](https://www.apple.com/legal/sla/). This repository does not distribute macOS or Apple firmware.

## Safe first step: inventory, not installation

On the tablet running Fedora (or Android with a shell and standard utilities), run:

```sh
sh scripts/hackintosh-assess.sh
```

The script reads system information and block-device metadata only; it does not need root, mount partitions, modify storage, download software, or flash anything. Some fields may be unavailable under Android permissions. Its output describes **the current OS**, not macOS support. Review output before sharing: model, device names and partition layout can still be identifying. It deliberately omits serials, filesystem UUIDs and mount paths.

For the existing, supported Fedora route, see [INSTALL.md](INSTALL.md) and [DUALBOOT.md](DUALBOOT.md). Back up important data and verify recovery procedures before any separate installation or partition operation. Never assume that an inactive boot slot isolates shared data or the GPT.

## Work required before any install could be attempted

| Area | Status on pipa for macOS | Research/development needed |
| --- | --- | --- |
| Boot chain and kernel | Not established | Determine whether a legally obtained macOS release can start on this platform, and whether a compatible firmware/boot environment and platform initialization can be implemented. Android boot images and Linux DTs do not solve this. |
| Storage | Not established | A macOS-compatible UFS controller driver and storage stack must work before safe access is possible. Identify the exact controller and partition layout; prove read-only access and recovery before contemplating writes. APFS support alone is not a controller driver. |
| GPU and display | Not established | Qualcomm Adreno GPU support and the panel/display pipeline would require compatible drivers; framebuffer-only output, if achieved, would not mean acceleration. Identify panel variant, display controller and interfaces. |
| Audio | Not established | Identify codec, amplifier, DSP and routing, then implement compatible drivers and firmware interfaces. |
| Wi-Fi and Bluetooth | Not established | Identify the actual radio, bus, firmware and power sequencing; macOS-compatible drivers and lawfully sourced firmware would be needed. Linux connectivity does not establish macOS support. |
| Touch, pen, sensors, cameras | Not established | Identify controllers and buses, then implement and test input, sensor and camera drivers independently. |
| Power, charging, sleep, USB | Not established | Platform power management, battery/charging, suspend and USB roles need compatible drivers and extensive safety testing. |

There are no working kexts, patched macOS kernel, EFI, installer, or partitioning instructions supplied here. No claim is made that these components can be built from the Linux sources or that such a port is practical. Avoid third-party images or guides claiming otherwise unless their source, device support, licensing and recovery steps can be independently verified.

## More realistic alternatives

* Use this project's Fedora image for native hardware support; its [README](README.md) lists known limitations.
* Use a properly licensed Mac for macOS applications, optionally accessing it remotely from the tablet. Availability and licensing depend on the application and macOS terms.
* If the goal is only the appearance of macOS, customize the Fedora desktop rather than changing the boot chain.

References: [OpenCore documentation](https://github.com/acidanthera/OpenCorePkg/tree/master/Docs), [Linux pipa kernel](https://github.com/pipa-mainline/linux), and [Apple software licenses](https://www.apple.com/legal/sla/).

### More detailed one-shot inventory

Run `python3 scripts/pipa-compat-check.py` on Fedora. This read-only, best-effort
checker collects Linux device-tree compatible strings, drivers, display, storage
layout, audio, networking, input, sensor, power and bus details. It requires
Python 3; `lsblk`, `lspci`, or individual sysfs entries may be unavailable.
It does not determine macOS driver availability or installation readiness.
Review the output before sharing: partition labels and USB product names can
reveal personal details. The tool omits MAC addresses, serial numbers and UUIDs.

## Research update: a Fedora pipa inventory (2026-11-25)

A Pad 6 inventory supplied by a user identified the following. Device-tree
compatibles identify what that Linux boot describes, not verified macOS support
or necessarily a complete list of physical components.

| Area | Linux observations | macOS research gap |
| --- | --- | --- |
| Boot | SM8250 device tree; EFI runtime not exposed in this boot | A different boot environment may be possible; absence of EFI runtime here does not prove firmware cannot be built. XNU and boot-chain integration remain untested on this device. |
| Storage | `qcom,sm8250-ufshc`; Linux saw an Android `userdata` and an ext4 `linux` partition | UFS initialization, DMA/IOMMU, block I/O and APFS access require independent validation. Neither partition is a safe install target. |
| Display / GPU | SM8250 DPU, DSI panel `xiaomi,pipa-nt36532`, 1800x2880; Adreno 650.2 | Panel initialization, framebuffer handoff, GPU and Metal support need device-specific proof. A DRM card identifying DPU alone is not proof of accelerated rendering. |
| Audio | `snd-sm8250`, WCD9380, SoundWire | Codec, DSP, amplifier and routing integration have not been verified for macOS. |
| Wireless | QCA6390 Wi-Fi `17cb:1101` using `ath11k_pci`; Bluetooth `qca6390-bt` using `hci_uart_qca` | Linux drivers cannot simply be installed as macOS drivers; native support is unverified. |
| Input and cameras | Novatek SPI touchscreen/pen; DT nodes for OV13B10 and HI846 | Device-tree entries and input enumeration do not prove macOS operation or even camera functionality in Linux. |
| Sensors and power | No IIO devices visible; PM8150-family charging, fuel gauge and thermal devices visible | Sensor enumeration, charging, thermal and sleep behavior remain to be tested; do not infer absent hardware from an empty IIO class. |

### Existing work worth examining, not installing

* [UniXNU-pipa](https://github.com/xVanTuring/UniXNU-pipa/tree/cdb3d62771e31d48d832853ee0c90964346d78da) contains pipa-specific XNU, UFS, GPU and touch work. Its README reports booting **iPadOS 17.7.11** on a Pad 6 with working display and touch, and experimental GPU acceleration. These are upstream reports, not independently verified here, and are not a macOS boot. Audio and networking are reported unavailable. Some comments still say untested, contradicting the newer README.
* [uefi-pipa](https://github.com/xVanTuring/uefi-pipa/tree/1f6a1520f84c699a6f748e7b0b0ee72b79c7997b) is a related experimental UEFI fork. UniXNU-pipa reports reaching its menu on hardware with this revision, although the UEFI repository description still says untested. A vendor UEFI component or a partition named `uefivarstore` does not establish macOS compatibility.
* [Snapintosh](https://github.com/Snapintosh/Snapintosh/tree/940eeb95ba637528dc45ba098e6b8091163dd489) describes a macOS boot and Adreno stack for an **ASUS Snapdragon X2 Elite laptop**, not pipa's Snapdragon 870. It is a reference for research, not a compatible pipa image. Its components have different licenses; inspect their licenses and third-party notices before reuse.
* [pipa-mainline/linux](https://github.com/pipa-mainline/linux) is useful for hardware initialization and Linux device descriptions, not as a drop-in macOS driver. Observe the applicable licenses when studying or reusing code.

A sensible sequence is source and license review, then offline builds and tests,
then a separately reviewed recovery plan and controlled hardware experiments.
No candidate image in these links has been validated by this project. Do not
flash firmware, resize partitions, or run write-capable UFS tests as a result of
this inventory. Successful compilation would not mean a safe or working boot.

### Offline source review and host tests (2026-11-25)

Reviewed UniXNU-pipa commit `cdb3d62771e31d48d832853ee0c90964346d78da`
from a shallow clone. The actual README has newer hardware reports than the
repository summary returned by search; the prior statement that its authors
said nothing had run on hardware was incorrect. We have not independently
verified those reports. Its documented target is iPadOS, not macOS.

On an x86-64 Linux host, using `cc -std=c11 -Wall -Wextra -Werror` on each
standalone file, `ButtonsTests`, `TouchBoardTests`, `NativeBatteryTests`,
`GpuPowerBoardTests`, and `GesturesTests` built and passed. These test helper
logic and simulated state only; they do not build XNU or validate hardware.
`A650GmuTests` could not compile standalone because `AdrenoHfiStartup.h`
was unavailable; it needs its additional kit/build dependencies. Full
firmware/kernel builds were not attempted: the environment lacks clang, lld,
cmake, ninja, dtc and mtools, and the documented workflow also requires
additional source trees, vendor inputs, and an iPadOS IPSW. No Apple or vendor
firmware was downloaded.

**Data-loss warning:** upstream's `board.toml` hard-codes another tablet's
userdata LBAs and RAM layout, and its README describes flashing an image to
`userdata`, which erases Android data. Your inventory shows `userdata` as
`sda34` and Fedora `linux` as `sda35`; neither is free space. Do not run its
`fastboot flash userdata`, kernel-round script, or other device-writing steps.
The project also describes untested battery code and a possible charger
watchdog issue. A build or host-test pass does not make these safe.

Next research gate: inspect the exact pinned driver sources and their licenses,
reproduce isolated build and unit tests with dependencies, and assess whether
the iPadOS-specific approach can inform a *separate* macOS target. Device
geometry, recovery, and an explicitly approved non-destructive test plan
would be prerequisites for any later hardware work.
