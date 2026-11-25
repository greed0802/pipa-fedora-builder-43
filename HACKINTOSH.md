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
