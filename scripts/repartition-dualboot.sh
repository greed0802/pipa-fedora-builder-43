#!/usr/bin/env bash
# Shrink Android userdata and create a GPT partition named "fedora" for dualboot.
#
# Run this ON THE TABLET from a temporary Linux boot (see DUALBOOT.md).
# Shrinking userdata ALWAYS destroys Android's encrypted userdata. Back up first.
#
# Usage:
#   sudo ./scripts/repartition-dualboot.sh --android-size 80G              # dry-run
#   sudo ./scripts/repartition-dualboot.sh --android-size 80G --apply
#   sudo ./scripts/repartition-dualboot.sh --android-size 80G --name linux --apply

set -euo pipefail

android_size=""
part_name="fedora"
apply=0
disk_override=""

usage() {
    cat <<'EOF'
Shrink userdata and create a Linux root partition for pipa dualboot.

Usage:
  pipa-repartition-dualboot --android-size SIZE [options]

Options:
  --android-size SIZE  New size of userdata (e.g. 80G, 100GiB). Required.
  --name NAME          Name of the new Linux partition (default: fedora)
  --disk DEVICE        UFS disk (default: parent of userdata)
  --apply              Write the GPT. Without this flag, only print the plan.
  -h, --help           Show this help

Notes:
  * Only userdata is resized. Other Qualcomm partitions are left alone.
  * Android userdata encryption will not survive this. You must fastboot -w
    (or reflash a ROM) before Android will boot again.
  * A GPT backup is written to /root/pipa-gpt-backup.bin — copy it off the
    tablet before rebooting.
EOF
}

die() { echo "error: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --android-size) android_size="$2"; shift 2 ;;
        --name) part_name="$2"; shift 2 ;;
        --disk) disk_override="$2"; shift 2 ;;
        --apply) apply=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
done

[[ -n "$android_size" ]] || { usage >&2; exit 1; }
[[ "$part_name" =~ ^[A-Za-z0-9_-]+$ ]] || die "invalid partition name"
[[ "$(id -u)" -eq 0 ]] || die "run as root"

command -v sgdisk >/dev/null || die "sgdisk not found (dnf install gdisk)"
command -v lsblk >/dev/null || die "lsblk not found"

userdata_link="/dev/disk/by-partlabel/userdata"
[[ -e "$userdata_link" ]] || die "no partition labelled userdata"

userdata_dev="$(readlink -f "$userdata_link")"
disk="/dev/$(lsblk -no PKNAME "$userdata_dev")"
[[ -n "$disk_override" ]] && disk="$disk_override"
[[ -b "$disk" ]] || die "not a block device: $disk"

partnum="$(lsblk -no PARTN "$userdata_dev")"
[[ "$partnum" =~ ^[0-9]+$ ]] || die "could not get userdata partition number"

if [[ -e "/dev/disk/by-partlabel/${part_name}" ]]; then
    die "a partition named '${part_name}' already exists"
fi

case "$android_size" in
    *[0-9]) die "--android-size needs a unit (e.g. 80G)" ;;
esac

backup="/root/pipa-gpt-backup.bin"
typecode="$(sgdisk -i "$partnum" "$disk" | awk '/^Partition GUID code:/{print $4}')"
start="$(sgdisk -i "$partnum" "$disk" | awk '/^First sector:/{print $3}')"
[[ -n "$start" ]] || die "could not read userdata start sector"

echo "Disk:              $disk"
echo "userdata device:   $userdata_dev (partition $partnum)"
echo "userdata start:    $start"
echo "userdata type:     ${typecode:-unknown}"
echo "new userdata size: $android_size"
echo "new partition:     ${part_name} (rest of disk)"
echo "GPT backup:        $backup"
echo
sgdisk -p "$disk" || true
echo

if [[ "$apply" -eq 0 ]]; then
    cat <<EOF
Dry run. The apply step would:
  1. sgdisk --backup=$backup $disk
  2. Recreate userdata as partition $partnum at sector $start size $android_size
  3. Create a new partition named ${part_name} in the leftover space
Re-run with --apply to write the table. Do not reboot until you have copied
$backup off the tablet.
EOF
    exit 0
fi

echo "Writing GPT backup to $backup"
mkdir -p /root
sgdisk --backup="$backup" "$disk"

echo "Recreating userdata (start=$start size=$android_size)"
sgdisk --delete="$partnum" "$disk"
sgdisk --new="${partnum}:${start}:+${android_size}" --change-name="${partnum}:userdata" "$disk"
if [[ -n "$typecode" ]]; then
    sgdisk --typecode="${partnum}:${typecode}" "$disk" || true
fi

# 0 = first free partition number, default start, default (largest) end
sgdisk --new="0:0:0" --change-name="0:${part_name}" --typecode="0:8300" "$disk"

echo
echo "New partition table:"
sgdisk -p "$disk"
partprobe "$disk" 2>/dev/null || true

cat <<EOF

Repartition written.
NEXT STEPS (from your PC, tablet in fastboot):
  1. Copy $backup off the tablet if you have not already.
  2. Hold Volume Down + Power to enter fastboot.
  3. fastboot -w          # wipe Android userdata (required after shrink)
  4. Restore stock super + dtbo_a from a HyperOS fastboot ROM (see DUALBOOT.md)
  5. ./scripts/flash.sh dualboot --partition ${part_name}

If the tablet will not leave fastboot after a later slot switch, restore GPT:
  fastboot flash partition:1 gpt_both1.bin
  ... (gpt_both1..5 from the stock ROM images/ directory)
EOF
