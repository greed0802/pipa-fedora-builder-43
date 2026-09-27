# Sensors on pipa Fedora

Status after this change: **accelerometer, ambient light and proximity run on
the SLPI sensor DSP and are enabled by default in every image**, with a
deterministic suspend/resume flow instead of the old 10–15 s restart hack.
Auto-rotation and auto-brightness should work on both the stock COPR
`kernel-pipa` and the camera-patched `7.1.7-pipa-cam+` kernel — **no kernel
patches are involved** (unlike the camera).

Live-verified on the Pad (2026-09): accelerometer streams all four
orientations across suspend/resume cycles; ambient light streams lux values;
the iio-sensor-proxy SSC fix series (below) is required for delivery to
clients — the stock 3.9 COPR build claims sensors but never sends data.

On-pad one-shot check after flashing/rebooting (the doctor ships in the
image):

```bash
sudo pipa-sensor-doctor                # report for every stack layer
sudo pipa-sensor-doctor --suspend-test # full suspend cycle check
# rotation: run `monitor-sensor` and tilt the pad
```

(In a repo checkout the same script is `mkosi.extra/usr/local/bin/pipa-sensor-doctor`.)

## How the stack works

Pipa's IMU is a Bosch BMI3x0 (accel + gyro) plus an AK0991x magnetometer.
They hang off the **SLPI** (sensor DSP), not the Application CPU — there is no
I2C sensor driver in the kernel and no kernel patch can add one. The path is:

```
BMI3x0/AK0991x ── SLPI firmware (slpi.mbn, sensor "SensorPD")
                     │  FastRPC / QRTR (nameserver runs in-kernel on 7.1.x)
                     ▼
        /dev/fastrpc-sdsp          (kernel fastrpc, already in DTS/config)
                     │  hexagonfs: DSP reads sensors/config, registry, DSP libs
                     ▼
        hexagonrpcd-sdsp.service   (serves the DSP its filesystem view)
                     │  SSC protocol (QMI over QRTR)
                     ▼
        libssc ── iio-sensor-proxy (ssc-accel; ssc-light/ssc-compass from upstream rules)
                     ▼
        net.hadess.SensorProxy D-Bus → GNOME/KDE auto-rotation, auto-brightness
```

Kernel requirements — already satisfied by pipadb `kernel-pipa` ≥ 7.1
(`&slpi` enabled in `sm8250-xiaomi-pipa.dts`, `CONFIG_QCOM_FASTRPC=y`,
`CONFIG_QRTR=m`, in-kernel QRTR nameserver). Gyro and magnetometer are not
exposed by iio-sensor-proxy; nothing consumes them on a desktop today.

## What was broken

| # | Problem | Effect | Fix shipped here |
| - | ------- | ------ | ---------------- |
| 1 | COPR `pipa-sensors` udev rule never sets `IIO_SENSOR_PROXY_TYPE=ssc-accel`. Upstream `80-iio-sensor-proxy.rules` only auto-tags `ssc-light ssc-compass` on fastrpc devices — the accelerometer must be opted in per device (its open can block; see liuqin/ArchPad). | Accelerometer never claimed → **no auto-rotation at all**; only light/compass worked | `mkosi.extra/etc/udev/rules.d/81-libssc-xiaomi-pipa.rules` (shadows the package rule), tags `ssc-accel` + mount matrix + `SYSTEMD_WANTS` for the DSP tunnel |
| 2 | The SLPI SensorPD expects its calibration registry at the Android path `/mnt/vendor/persist/sensors/...` and writes scratch files there. Fedora has no such dir. | DSP rebuilds its registry every boot (slow first sample, `temp.json` write spam in the journal), calibration lost | `pipa-sensors-persist.service` + `pipa-prepare-sensor-persist`: recreate the path in the rootfs, seed it from the pre-generated registry in `xiaomi-pipa-firmware` (BMI3x0/AK0991x cal data), own it by the `fastrpc` user |
| 3 | `pipa-sensor-restart` RPM: after every resume blindly `sleep 2`, restart proxy → daemon → proxy. | 10–15 s downtime, races the DSP, "might not always work" | Deterministic systemd flow (below); the old hook is neutralized by an overlay stub |
| 4 | Proxy left polling while the SoC suspends → in-flight QMI reads hang the proxy / tear the DSP session. | Sensors dead after suspend until services restarted | `iio-sensor-proxy` is **conflict-stopped before sleep** (`Conflicts=suspend.target`), rebuilt after resume by `pipa-sensor-resume.service` |
| 5 | Proxy discovery can run before the SensorPD finished booting (first boot, right after resume). | Proxy starts "successfully" with no accelerometer; nothing re-probes | `ExecStartPre=/usr/local/bin/pipa-wait-ssc` gates the proxy on a real `ssccli` accelerometer sample (soft 20 s cap) |
| 6 | FastRPC tunnel unit had no firmware root pinned (hexagonrpcd < 0.5 has no DT autodetect). | Depends on COPR package version | `hexagonrpcd-sdsp.service.d/pipa.conf` pins `-R /usr/share/qcom/sm8250/Xiaomi/pipa` |

## The suspend/resume flow (replaces pipa-sensor-restart)

```
suspend:   suspend.target starts
             └─ iio-sensor-proxy  stopped  (Conflicts=suspend.target, Before=)
             └─ hexagonrpcd-sdsp  keeps running (tunnel survives on pipa)
resume:    suspend.target reached only AFTER systemd-suspend.service returns
             └─ pipa-sensor-resume.service (WantedBy/After=suspend.target)
                  ├─ start hexagonrpcd-sdsp (fresh FastRPC session, ≤10 s wait)
                  ├─ re-run pipa-prepare-sensor-persist (idempotent)
                  ├─ wait for a real ssccli accelerometer sample (≤15 s)
                  └─ start iio-sensor-proxy   → SensorProxy back in ~2-5 s
```

Note the systemd semantics that make this work: `Restart=` is **not**
triggered when a unit is stopped by a `Conflicts=` dependency — that is why
the naive "pmOS-style Conflicts hack" alone leaves the proxy dead after
resume, and why an explicit resume unit is part of the flow.

GNOME/KDE re-claim the accelerometer when the SensorProxy D-Bus name
re-appears; if rotation is dead right after a resume, toggle rotation once or
`systemctl restart iio-sensor-proxy` and re-check before filing a bug.

## Files shipped (all under `mkosi.extra/`, landed in the image at build)

| Path | Role |
| ---- | ---- |
| `scripts/patch-sensors-on-pad.sh` | apply all of the below onto a running install (no image rebuild) |
| `etc/udev/rules.d/81-libssc-xiaomi-pipa.rules` | shadows the COPR rule; `ssc-accel` + mount matrix + `SYSTEMD_WANTS=hexagonrpcd-sdsp` |
| `usr/lib/systemd/system/pipa-sensors-persist.service` | oneshot: persist layout + registry seed |
| `usr/lib/systemd/system/pipa-sensor-resume.service` | post-resume rebuild (WantedBy=suspend.target) |
| `usr/lib/systemd/system/hexagonrpcd-sdsp.service.d/pipa.conf` | persist ordering + `-R` firmware root |
| `usr/lib/systemd/system/iio-sensor-proxy.service.d/pipa.conf` | tunnel ordering, `PartOf`, suspend conflicts, `pipa-wait-ssc` gate, timeouts |
| `usr/lib/tmpfiles.d/pipa-sensors.conf` | persist dir skeleton |
| `usr/local/bin/pipa-prepare-sensor-persist` | registry seeding (idempotent) |
| `usr/local/bin/pipa-wait-ssc` | ExecStartPre gate on a real accel sample |
| `usr/local/bin/pipa-sensor-resume` | resume sequence |
| `usr/lib/systemd/system-sleep/pipa-sensor-restart` | neutralizes the RPM's sleep hook (delete this file to restore it) |
| `usr/local/bin/pipa-sensor-doctor` | layer-by-layer diagnostics, optional `--suspend-test` |

`build.sh` enables `pipa-sensors-persist`, `hexagonrpcd-sdsp`,
`iio-sensor-proxy` and `pipa-sensor-resume`; the udev rule additionally binds
the tunnel to the device, so a missing DSP never keeps units running.
`mkosi.conf` adds `pipa-sensors` (pulls `hexagonrpc`, `iio-sensor-proxy`,
`xiaomi-pipa-firmware`) and `libssc` (`ssccli`). No `qrtr` userspace package
is needed: pipa's 7.1.x kernel runs the QRTR nameserver in-kernel.

Existing installs do **not** need an image rebuild — this is pure userspace:

```bash
# on the Pad (branch with this change: add -b arena/01a0d30f-pipa-fedora-builder-43)
git clone https://github.com/greed0802/pipa-fedora-builder-43
cd pipa-fedora-builder-43
sudo ./scripts/patch-sensors-on-pad.sh
```

The script installs `pipa-sensors` + `libssc` from the COPRs, copies the
`mkosi.extra/` overlay onto the live rootfs, enables the services and runs
the doctor. No kernel, boot image or reboot involved; safe to re-run.

## Provenance

Same playbook as `kernel-camera/`: do not reinvent, adopt the working
pipa-family implementations.

| Piece | Origin |
| ----- | ------ |
| persist registry prep + resume hook design | [thespider2/pipa-pkgs](https://github.com/thespider2/pipa-pkgs) `pipa-sensors` 1.2 (EndeavourOS pipa) |
| `ssc-accel` per-device udev opt-in + tunnel/`sns_reg_version` mapping | [ArchPad](https://github.com/Sachinmc73/archpad-pipa) `archpad-pipa-device` + `hexagonrpc` patches |
| suspend lifecycle (`Conflicts=suspend.target` + resume unit), iio-sensor-proxy fix series | [yzddmr6/xiaomipad-6pro-mainline](https://github.com/yzddmr6/xiaomipad-6pro-mainline) `device/sensors/` (Pad 6 Pro / liuqin), [terrapkg](https://github.com/terrapkg/packages) `0004-bring-hexagonrpcd-back-after-resume.patch` |
| iio-sensor-proxy SSC patches (vendored, see above) | [thespider2/pipa-pkgs](https://github.com/thespider2/pipa-pkgs) `common/iio-sensor-proxy` 0002–0005 |
| sensor calibration registry (BMI3x0, AK0991x) | `xiaomi-pipa-firmware` (already installed) |
| ssccli probe gate | ArchPad `archpad-wait-ssc` |

## If something is still wrong

```bash
sudo pipa-sensor-doctor --suspend-test   # full suspend cycle check
journalctl -b -u hexagonrpcd-sdsp -u iio-sensor-proxy -t pipa-sensor-resume -t pipa-wait-ssc
monitor-sensor            # live D-Bus readings while tilting / covering the ALS
```

* Rotation wrong by 90/180°, not dead → change `ACCEL_MOUNT_MATRIX` in
  `81-libssc-xiaomi-pipa.rules` (candidates: `-1,0,0;0,-1,0;0,0,-1`,
  `-1,0,0;0,-1,0;0,0,1`), then `sudo udevadm control --reload && sudo
  udevadm trigger /dev/fastrpc-sdsp && sudo systemctl restart iio-sensor-proxy`.
* `monitor-sensor` shows "Accelerometer appeared" but orientation never
  changes → unpatched iio-sensor-proxy 3.9 claims but never *delivers*: the
  probe `close()` during discovery breaks the later open and the close
  signal-handler kills measurement delivery. Confirmed live on the Pad and
  fixed by the vendored series — build it:
  `sudo ./scripts/build-install-iio-sensor-proxy.sh` (see section above).
* Journal line `Mount matrix provided by firmware is all 0, falling back to
  identity matrix!` (from libssc, twice at start) is noise: the proxy's SSC
  driver reads the matrix from the udev property (our rule), not from the
  firmware attribute.
* `hexagonrpcd-sdsp` restart-loops → the DSP refuses the filesystem view;
  check the journal for `temp.json`/registry errors, verify
  `/usr/share/qcom/sm8250/Xiaomi/pipa/sensors/registry` exists
  (`xiaomi-pipa-firmware` installed).
* Accel ready (`ssccli` works) but `HasAccelerometer=false` → a proxy that
  predates the tunnel never re-scans; `sudo systemctl restart iio-sensor-proxy`.
  The gate prevents this for starts after the tunnel is up.
* `hexagonrpcd` journal: `Tried to open .../temp.json for writing` repeatedly →
  cosmetic: the DSP wants to refresh its scratch file but hexagonfs serves the
  mapped registry read-only. Harmless (accelerometer still works); ArchPad
  suppresses the spam in their hexagonrpc fork — see the COPR backlog.

## Known limitations

* Gyroscope and magnetometer are not exposed (iio-sensor-proxy limitation, not
  a pipa one); compass apps will not work. pipa has **no proximity hardware**
  at all (registry = BMI3x0 + AK0991x only), so `monitor-sensor` showing
  proximity (and compass) appear/disappear is normal churn, not a fault.
* Unpatched iio-sensor-proxy 3.9 claims sensors but delivers no measurements
  (fixed by the vendored series above — the stock COPR build is affected).
* If the desktop was started while no SensorProxy existed and never re-claims,
  rotation stays dead until it is restarted — same edge case the liuqin tree
  works around with a post-graphical re-announce. Not needed on pipa today.
* First resume after flashing can still be slow if the SLPI does a cold
  registry rebuild; subsequent ones are fast.

## The iio-sensor-proxy SSC fix series (shipped)

Live testing on the Pad proved the DSP + tunnel fine (`ssccli` gets samples)
while the unpatched 3.9 proxy never delivers measurements to clients: the
probe `close()` during discovery breaks the later `open()`, and the close
signal-handler path kills measurement delivery — ArchPad, the Pad 6 Pro
mainline tree and EndeavourOS pipa all carry fixes for exactly this.

`userspace-sensors/iio-sensor-proxy/` vendors the series against upstream
3.9, and `scripts/build-install-iio-sensor-proxy.sh` builds it **on the Pad**
into `iio-sensor-proxy-3.9-2.pipa` (meson + rpmbuild, ~2 minutes) and
installs it over the COPR build. Revert:

```bash
sudo dnf distro-sync iio-sensor-proxy --repo=pocketblue:common
```

Long term this belongs in the COPR build (backlog item 2 below); the local
RPM just makes the Pad testable today. A future COPR build with a higher
release supersedes it naturally.

## COPR backlog (upstreamable)

1. `pipa-sensors`: fix the udev rule (tag `ssc-accel` only — pipa has no proximity hardware — scope the
   matrix to `fastrpc-sdsp`) and ship the persist prep + units — then this
   overlay can shrink to nothing. Sources: pipa-pkgs `pipa-sensors` 1.2.
2. `iio-sensor-proxy` 3.9: add the patch series from pipa-pkgs/xiaomipad-6pro
   (`skip-close-in-discover`, `retry-open-after-resume`, `fix-close-signal-handler`,
   null-GError guards, coldplug preclaimed clients). Belt-and-braces on top of
   the systemd flow.
3. `hexagonrpc`: apply ArchPad's `sns_reg_version` mapping + json write-spam
   suppression (both already carry upstream test coverage in the liuqin tree).
4. `pipa-metapkg`: drop `pipa-sensor-restart` once this flow is validated.
