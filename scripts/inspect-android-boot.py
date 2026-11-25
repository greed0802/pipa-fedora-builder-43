#!/usr/bin/env python3
"""Inspect the layout of an Android boot image, without modifying it.

This is a structural check, not a signature verifier or device compatibility test.
Only regular image files are accepted; block devices and vendor_boot are excluded.
"""
import argparse
import json
import os
import stat
import struct
import sys


class InvalidImage(ValueError):
    pass


def u32(buf, offset):
    if offset + 4 > len(buf):
        raise InvalidImage('truncated header')
    return struct.unpack_from('<I', buf, offset)[0]


def u64(buf, offset):
    if offset + 8 > len(buf):
        raise InvalidImage('truncated header')
    return struct.unpack_from('<Q', buf, offset)[0]


def align(value, page):
    return (value + page - 1) // page * page


def inspect(header, size):
    if len(header) < 48 or header[:8] != b'ANDROID!':
        raise InvalidImage('missing or truncated ANDROID! boot header')
    version = u32(header, 40)
    if version > 4:
        raise InvalidImage(f'unsupported boot header version {version}')
    minimum = (1632, 1648, 1660, 1580, 1584)[version]
    if len(header) < minimum:
        raise InvalidImage(f'truncated v{version} header (need {minimum} bytes)')
    if version <= 2:
        page = u32(header, 36)
        if page < minimum or page > 65536 or page & (page - 1):
            raise InvalidImage('legacy page size must be a power of two between header size and 65536')
        declared = u32(header, 1644) if version >= 1 else minimum
        if declared < minimum or declared > page:
            raise InvalidImage('invalid legacy header_size')
        kernel, ramdisk, second = u32(header, 8), u32(header, 16), u32(header, 24)
    else:
        page = 4096
        declared = u32(header, 20)
        if declared < minimum or declared > page:
            raise InvalidImage('invalid v3/v4 header_size')
        kernel, ramdisk, second = u32(header, 8), u32(header, 12), 0
    if size < page:
        raise InvalidImage('file does not contain a complete header page')
    if kernel == 0:
        raise InvalidImage('kernel is empty; cannot validate a bootable kernel')

    regions = []
    def region(name, offset, length):
        if length:
            if offset < page or offset > size or length > size - offset:
                raise InvalidImage(f'{name} exceeds file bounds')
            regions.append({'name': name, 'offset': offset, 'size': length})

    pos = page
    region('kernel', pos, kernel)
    pos += align(kernel, page)
    region('ramdisk', pos, ramdisk)
    pos += align(ramdisk, page)
    if version <= 2:
        region('second', pos, second)
        pos += align(second, page)
        if version >= 1:
            recovery_size = u32(header, 1632)
            recovery_offset = u64(header, 1636)
            if recovery_size:
                if recovery_offset < pos or recovery_offset % page:
                    raise InvalidImage('recovery_dtbo offset overlaps earlier regions or is not page-aligned')
                region('recovery_dtbo', recovery_offset, recovery_size)
                pos = recovery_offset + align(recovery_size, page)
        if version == 2:
            region('dtb', pos, u32(header, 1648))
    elif version == 4:
        region('boot_signature', pos, u32(header, 1580))
    return {'header_version': version, 'header_size': declared, 'page_size': page,
            'file_size': size, 'regions': regions,
            'note': 'Structural checks only; no signatures, hardware compatibility or bootability verified.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image', help='existing regular Android boot image file')
    args = parser.parse_args()
    try:
        # Nonblocking open prevents hanging on a FIFO before fstat rejects it.
        fd = os.open(args.image, os.O_RDONLY | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as image:
            info = os.fstat(image.fileno())
            if not stat.S_ISREG(info.st_mode):
                raise InvalidImage('only regular files are accepted, not devices or pipes')
            result = inspect(image.read(1660), info.st_size)
        print(json.dumps(result, indent=2))
    except (OSError, InvalidImage) as exc:
        print(f'error: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
