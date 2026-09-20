#!/usr/bin/env python3
"""Append extra words to the kernel cmdline inside an Android boot.img.

Does not load the Pad's linux partition. Safe to run on Windows against the
same boot.img you already flashed to boot_b (~37 MiB).

    python patch-boot-cmdline.py boot.img boot-text.img systemd.unit=multi-user.target
    fastboot flash boot_b boot-text.img
    fastboot erase dtbo_b
    fastboot set_active b
    fastboot reboot
"""

from __future__ import annotations

import argparse
import sys


def patch(data: bytearray, extra: str) -> bytearray:
    extra_b = extra.strip().encode("ascii")
    marker = b"fbcon=rotate:1"
    idx = data.find(marker)
    if idx < 0:
        marker = b"root=UUID="
        idx = data.find(marker)
    if idx < 0:
        sys.exit("error: no pipa cmdline (fbcon=rotate:1 / root=UUID=) in boot.img")

    start = idx
    while start > 0 and data[start - 1] not in (0, 10, 13):
        start -= 1
    end = idx
    while end < len(data) and data[end] != 0:
        end += 1
    if end >= len(data):
        sys.exit("error: cmdline is not NUL-terminated")

    old = bytes(data[start:end])
    if extra_b in old:
        print(f"already present: {old.decode('ascii', 'replace')}")
        return data

    # Keep splash/quiet or not: extra is appended.
    pad = end - start  # usable bytes before NUL
    new = old + b" " + extra_b
    if len(new) > pad:
        # Overwrite splash/quiet to free space
        trimmed = old.replace(b" splash", b"").replace(b" quiet", b"")
        new = trimmed + b" " + extra_b
    if len(new) > pad:
        sys.exit(f"error: cmdline too long ({len(new)} > {pad}): {new!r}")

    data[start:end] = new.ljust(pad, b"\0")
    print("old:", old.decode("ascii", "replace"))
    print("new:", new.decode("ascii", "replace"))
    return data


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("boot_in")
    p.add_argument("boot_out")
    p.add_argument(
        "extra",
        nargs="?",
        default="systemd.unit=multi-user.target",
        help="appended to cmdline (default: systemd.unit=multi-user.target)",
    )
    args = p.parse_args()
    data = bytearray(open(args.boot_in, "rb").read())
    if data[:8] != b"ANDROID!":
        sys.exit("error: not an ANDROID! boot.img")
    data = patch(data, args.extra)
    open(args.boot_out, "wb").write(data)
    print("wrote", args.boot_out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
