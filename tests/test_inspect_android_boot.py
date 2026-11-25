import importlib.util
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'inspect-android-boot.py'
spec = importlib.util.spec_from_file_location('boot_inspector', SCRIPT)
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)


def image(version):
    page = 2048 if version <= 2 else 4096
    raw = bytearray(page * 6)
    raw[:8] = b'ANDROID!'
    def put(at, value):
        struct.pack_into('<I', raw, at, value)
    put(40, version)
    if version <= 2:
        put(8, 100)
        put(16, 200)
        put(24, 50)
        put(36, page)
        if version >= 1:
            put(1632, 30)
            struct.pack_into('<Q', raw, 1636, page * 4)
            put(1644, 1648 if version == 1 else 1660)
        if version == 2:
            put(1648, 20)
    else:
        put(8, 100)
        put(12, 200)
        put(20, 1580 if version == 3 else 1584)
        if version == 4:
            put(1580, 40)
    return raw


class InspectorTests(unittest.TestCase):
    def test_all_versions(self):
        for version in range(5):
            with self.subTest(version=version):
                data = image(version)
                result = boot.inspect(data[:1660], len(data))
                self.assertEqual(result['header_version'], version)
                names = [r['name'] for r in result['regions']]
                self.assertEqual(names[:2], ['kernel', 'ramdisk'])
                self.assertEqual('recovery_dtbo' in names, version in (1, 2))
                self.assertEqual('dtb' in names, version == 2)
                self.assertEqual('boot_signature' in names, version == 4)

    def test_invalid_inputs(self):
        with self.assertRaises(boot.InvalidImage):
            boot.inspect(b'bad', 3)
        data = image(0)
        struct.pack_into('<I', data, 36, 3000)
        with self.assertRaises(boot.InvalidImage):
            boot.inspect(data[:1660], len(data))
        data = image(4)
        struct.pack_into('<I', data, 8, 0xffffffff)
        with self.assertRaises(boot.InvalidImage):
            boot.inspect(data[:1660], len(data))
        data = image(1)
        struct.pack_into('<Q', data, 1636, 2048)
        with self.assertRaises(boot.InvalidImage):
            boot.inspect(data[:1660], len(data))
        data = image(3)
        struct.pack_into('<I', data, 20, 1579)
        with self.assertRaises(boot.InvalidImage):
            boot.inspect(data[:1660], len(data))
        data = image(4)
        struct.pack_into('<I', data, 40, 5)
        with self.assertRaises(boot.InvalidImage):
            boot.inspect(data[:1660], len(data))

    def test_cli_read_only(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'boot.img'
            data = image(4)
            path.write_bytes(data)
            proc = subprocess.run([sys.executable, str(SCRIPT), str(path)], capture_output=True, text=True)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            self.assertEqual(path.read_bytes(), data)
            self.assertIn('Structural checks only', proc.stdout)
            fifo = Path(temp) / 'pipe'
            os.mkfifo(fifo)
            proc = subprocess.run([sys.executable, str(SCRIPT), str(fifo)], capture_output=True, text=True, timeout=3)
            self.assertNotEqual(proc.returncode, 0)
            self.assertIn('only regular files', proc.stderr)


if __name__ == '__main__':
    unittest.main()
