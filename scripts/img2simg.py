#!/usr/bin/env python3
"""Convert a raw disk image to Android sparse format without loading it into RAM.

Windows fastboot often throws std::bad_alloc on multi-GiB raw ext4 (root.img)
even with -S, because it still maps the whole file. Flash the .simg instead:

    python img2simg.py root.img root.simg
    fastboot flash linux root.simg
"""

from __future__ import annotations

import argparse
import os
import struct
import sys

MAGIC = 0xED26FF3A
CHUNK_RAW = 0xCAC1
CHUNK_DONT_CARE = 0xCAC3
HEADER = struct.Struct("<IHHHHIIII")  # 28 bytes
CHUNK = struct.Struct("<HHII")  # 12 bytes
BLK = 4096


def is_zero(buf: bytes) -> bool:
    return not any(buf)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("raw")
    p.add_argument("sparse")
    args = p.parse_args()

    raw_size = os.path.getsize(args.raw)
    if raw_size % BLK:
        sys.exit(f"error: {args.raw} size {raw_size} is not a multiple of {BLK}")

    total_blks = raw_size // BLK
    # First pass: count chunks (consecutive zero vs data runs)
    chunks: list[tuple[int, int]] = []  # (type, nblocks)
    with open(args.raw, "rb") as src:
        run_type: int | None = None
        run_len = 0
        while True:
            buf = src.read(BLK)
            if not buf:
                break
            t = CHUNK_DONT_CARE if is_zero(buf) else CHUNK_RAW
            if t == run_type:
                run_len += 1
            else:
                if run_type is not None:
                    chunks.append((run_type, run_len))
                run_type, run_len = t, 1
        if run_type is not None:
            chunks.append((run_type, run_len))

    with open(args.raw, "rb") as src, open(args.sparse, "wb") as dst:
        dst.write(
            HEADER.pack(
                MAGIC, 1, 0, HEADER.size, CHUNK.size, BLK, total_blks, len(chunks), 0
            )
        )
        for ctype, nblks in chunks:
            data_len = nblks * BLK if ctype == CHUNK_RAW else 0
            dst.write(CHUNK.pack(ctype, 0, nblks, CHUNK.size + data_len))
            if ctype == CHUNK_RAW:
                left = data_len
                while left:
                    buf = src.read(min(left, 1024 * 1024))
                    if not buf:
                        sys.exit("error: short read")
                    dst.write(buf)
                    left -= len(buf)
            else:
                src.seek(nblks * BLK, os.SEEK_CUR)

    out_size = os.path.getsize(args.sparse)
    print(
        f"wrote {args.sparse} ({out_size / (1024 ** 3):.2f} GiB sparse, "
        f"{raw_size / (1024 ** 3):.2f} GiB raw, {len(chunks)} chunks)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
