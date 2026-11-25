#!/usr/bin/env python3
"""Read-only, best-effort Linux inventory for macOS compatibility research."""
import os
import platform
import shutil
import subprocess
from pathlib import Path


def section(title):
    print('\n=== ' + title + ' ===')


def read(path):
    try:
        return Path(path).read_bytes().replace(b'\0', b' ').decode('utf-8', 'replace').strip()
    except (OSError, ValueError):
        return ''


def command(args):
    if not shutil.which(args[0]):
        print(f'{args[0]}: not installed')
        return
    try:
        result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, timeout=15, check=False)
        print(result.stdout.strip() or '(no output)')
        if result.returncode:
            print(f'{args[0]} exited {result.returncode}: {result.stderr.strip()}')
    except (OSError, subprocess.TimeoutExpired) as exc:
        print(f'{args[0]} unavailable: {exc}')


def driver(path):
    link = Path(path) / 'driver'
    try:
        return link.resolve(strict=True).name
    except OSError:
        return 'unknown/unbound'


def entries(path):
    try:
        return sorted(Path(path).iterdir(), key=lambda p: p.name)
    except OSError:
        return []


def device_info(node):
    dev = node / 'device'
    try:
        target = dev.resolve(strict=True)
    except OSError:
        return 'device path unavailable'
    parts = [f'driver={driver(target)}']
    for key in ('modalias', 'vendor', 'device', 'class'):
        value = read(target / key)
        if value:
            parts.append(f'{key}={value}')
    compatible = read(target / 'of_node' / 'compatible')
    if compatible:
        parts.append(f'compatible={compatible}')
    return ', '.join(parts)


section('Platform and boot context')
print('Kernel:', platform.platform())
for label, path in (
    ('Model', '/sys/firmware/devicetree/base/model'),
    ('Compatible', '/sys/firmware/devicetree/base/compatible'),
    ('OS', '/etc/os-release'),
):
    value = read(path)
    if label == 'OS' and value:
        value = next((line for line in value.splitlines() if line.startswith('PRETTY_NAME=')), '')
    print(f'{label}: {value or "unavailable"}')
print('EFI runtime:', 'detected' if Path('/sys/firmware/efi').exists() else 'not detected in this boot')
print('Bootloader, secure boot state and macOS boot compatibility: not determined')

section('Storage layout (no filesystem UUIDs or serials)')
command(['lsblk', '-o', 'NAME,TYPE,SIZE,FSTYPE,PARTLABEL'])
print('Storage controller drivers:')
for node in entries('/sys/class/scsi_host'):
    print(f'  {node.name}: {device_info(node)}')
print('Linux visibility does not establish a macOS UFS driver or identify a safe target.')

section('Graphics and display')
for node in entries('/sys/class/drm'):
    if node.name == 'version':
        continue
    print(f'{node.name}: {device_info(node)}')
    for field in ('status', 'modes'):
        value = read(node / field)
        if value:
            print(f'  {field}: {value.replace(chr(10), ", ")}')

section('Audio')
for node in entries('/sys/class/sound'):
    if node.name.startswith('card'):
        print(f'{node.name}: {device_info(node)}')
command(['cat', '/proc/asound/cards'])

section('Wi-Fi and Bluetooth (no MAC addresses)')
for node in entries('/sys/class/net'):
    if node.name != 'lo':
        print(f'net {node.name}: {device_info(node)}')
for node in entries('/sys/class/bluetooth'):
    if ':' not in node.name:
        print(f'bluetooth {node.name}: {device_info(node)}')

section('Input and sensors')
for cls in ('input', 'iio', 'power_supply', 'thermal'):
    root = Path('/sys/class') / cls
    nodes = entries(root)
    # inputN names are enough; eventN is a duplicate view of the same devices.
    if cls == 'input':
        nodes = [n for n in nodes if n.name.startswith('input')]
    if not nodes:
        print(f'{cls}: none visible')
    for node in nodes:
        name = read(node / 'name') or read(node / 'device' / 'name')
        kind = read(node / 'type') if cls in ('power_supply', 'thermal') else ''
        print(f'{cls} {node.name}: {name or kind or "unnamed"}; {device_info(node)}')

section('Relevant device-tree compatible strings')
# Print only node paths and compatibles for likely platform components, not raw DT
# properties (which can contain serial numbers, calibration or addresses).
root = Path('/sys/firmware/devicetree/base')
terms = ('ufs', 'gpu', 'adreno', 'display', 'dsi', 'panel', 'sound', 'audio',
         'codec', 'wifi', 'wlan', 'bluetooth', 'touch', 'sensor', 'camera',
         'usb', 'battery', 'charger', 'pmic', 'qcom,sm8250')
count = 0
if root.exists():
    for base, dirs, files in os.walk(root, onerror=lambda error: None):
        dirs.sort()
        if 'compatible' not in files:
            continue
        compatible = read(Path(base) / 'compatible')
        if compatible and any(t in (base + ' ' + compatible).lower() for t in terms):
            print(f'{os.path.relpath(base, root)}: {compatible}')
            count += 1
if not count:
    print('No matching readable device-tree nodes.')

section('Other buses')
command(['lspci', '-nnk'])
print('USB device descriptions (no serials):')
for node in entries('/sys/bus/usb/devices'):
    vendor, product = read(node / 'idVendor'), read(node / 'idProduct')
    if vendor and product:
        print(f'{node.name}: {vendor}:{product} {read(node / "manufacturer")} {read(node / "product")}')

section('Interpretation and privacy')
print('All results describe Linux, not functional macOS drivers. Missing information')
print('may reflect permissions, disabled hardware or unavailable utilities. No')
print('macOS bootloader, kernel support, GPU acceleration or device driver is verified.')
print('No partition was selected or modified. Review output before sharing: device')
print('names, partition labels, attached USB descriptions and model may be sensitive.')
