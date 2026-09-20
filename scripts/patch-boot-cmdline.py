#!/usr/bin/env python3
"""Append extra words to the kernel cmdline inside an Android boot.img.

The pipa boot.img cmdline field is only ~74 bytes (already filled by
root=UUID=... fbcon=rotate:1 splash quiet). Use the short SysV runlevel
token "3" (systemd multi-user / text), not systemd.unit=multi-user.target.

    python patch-boot-cmdline.py boot.img boot-text.img 3
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
    pad = end - start

    if extra_b in old.split():
        print("already present:", old.decode("ascii", "replace"))
        return data

    stripped = b" ".join(old.replace(b" splash", b"").replace(b" quiet", b"").split())
    candidates = [
        stripped + b" " + extra_b,
        b"root=PARTLABEL=linux fbcon=rotate:1 " + extra_b,
        b"root=PARTLABEL=linux fbcon=rotate:1 3",
    ]
    new = None
    for c in candidates:
        c = b" ".join(c.split())
        if len(c) <= pad:
            new = c
            break
    if new is None:
        sys.exit(f"error: cmdline too long (need <= {pad} bytes)")

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
        default="3",
        help="appended to cmdline (default: 3 = systemd multi-user / text)",
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
