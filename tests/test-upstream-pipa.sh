#!/bin/sh
# Run a limited set of upstream host-only synthetic tests. No device access.
# Usage: sh tests/test-upstream-pipa.sh /path/to/UniXNU-pipa
set -eu
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 /path/to/UniXNU-pipa" >&2
    exit 2
fi
repo=$(cd "$1" && pwd)
expected=cdb3d62771e31d48d832853ee0c90964346d78da
actual=$(git -C "$repo" rev-parse HEAD)
if [ "$actual" != "$expected" ]; then
    echo "Unexpected upstream revision: $actual (expected $expected)" >&2
    exit 1
fi
# Ensure the test sources are the exact versions reviewed. This also catches
# uninitialized submodules, but does not authenticate the Git server or compiler.
for pair in \
    'drivers/PipaUfs:5c64c0125e0d1855729a2d0095c03514b9cc7030' \
    'drivers/PipaNovatekTouch:0025115b7125b53e582f7c6934bb27610d001647'; do
    path=${pair%%:*}; revision=${pair#*:}
    [ "$(git -C "$repo/$path" rev-parse HEAD 2>/dev/null || :)" = "$revision" ] || {
        echo "Missing or unexpected submodule: $path" >&2; exit 1;
    }
    [ -z "$(git -C "$repo/$path" status --porcelain --untracked-files=no)" ] || {
        echo "Modified submodule: $path" >&2; exit 1;
    }
done
[ -z "$(git -C "$repo" status --porcelain --untracked-files=no)" ] || {
    echo 'Upstream checkout has tracked modifications.' >&2; exit 1;
}
command -v cc >/dev/null && command -v c++ >/dev/null && command -v python3 >/dev/null || {
    echo 'Requires cc, c++, Python 3 and Git.' >&2; exit 1;
}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pipa-host-tests.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
cd "$repo"
for name in ButtonsTests TouchBoardTests NativeBatteryTests GpuPowerBoardTests GesturesTests; do
    cc -std=c11 -Wall -Wextra -Werror "package/$name.c" -o "$tmp/$name"
    "$tmp/$name"
done
for name in nvt-points nvt-protocol touch-core; do
    # GCC reports warnings in upstream sources that clang may not; no -Werror.
    cc -std=c11 "drivers/PipaNovatekTouch/Test/$name.c" \
        drivers/PipaNovatekTouch/NvtProtocol.c drivers/PipaNovatekTouch/NvtTouchCore.c \
        -lm -o "$tmp/$name"
    # No vendor firmware; upstream skips the firmware-specific cases.
    env -u NVT_FIRMWARE "$tmp/$name"
done
for name in RootDiagnostics RootPublication; do
    c++ -std=c++17 -Wall -Wextra -Werror "drivers/PipaUfs/tests/$name.cpp" -o "$tmp/$name"
    "$tmp/$name"
done
python3 drivers/PipaUfs/tests/check_legacy_descriptors.py --compiler c++ --output "$tmp/ufs"
echo 'Host tests only: no tablet, XNU boot, firmware or macOS compatibility tested.'
