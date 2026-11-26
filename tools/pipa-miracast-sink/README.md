# pipa-miracast-sink (draft)

**Draft starter repo** for receiving Windows **Win+K / Miracast** wireless display connections on Fedora (target: Xiaomi Pad 6 / pipa).

> Status: prototype scaffold. Miracast sink support is hardware/driver dependent and may require iteration on pipa.

## Goal

Make the Pad appear as a Wireless Display target so Windows can connect with **Win+K only** (no Windows-side install).

## How it works (MVP design)

This draft does **not** reimplement Miracast from scratch. It orchestrates existing Linux pieces:

1. `miracle-wifid` — Wi-Fi Direct / WFD management (MiracleCast)
2. `miracle-sinkctl` — sink control / RTSP negotiation
3. GStreamer — decode and display the incoming RTP/H.264 stream
4. GTK4 — small status/window UI

## Layout

```text
pipa-miracast-sink/
├── README.md
├── pyproject.toml
├── pipa_miracast_sink/
│   ├── __init__.py
│   ├── __main__.py
│   ├── app.py            # GTK4 UI
│   ├── config.py
│   ├── p2p_check.py      # P2P/tool checks
│   ├── rtsp_player.py    # GStreamer playback
│   └── sink_manager.py   # miracle-wifid/sinkctl orchestration
├── scripts/
│   └── run-dev.sh
└── systemd/
    └── pipa-miracast-sink.service
```

## Prerequisites (on Fedora Pad)

```bash
sudo dnf install \
  miraclecast \
  gstreamer1 gstreamer1-plugins-base gstreamer1-plugins-good \
  gstreamer1-plugins-bad-free gstreamer1-libav \
  python3-gobject gtk4 iw NetworkManager wpa_supplicant
```

> Check `miraclecast` availability on your Fedora/aarch64 release. If unavailable, build MiracleCast from source or evaluate [Mirai](https://github.com/leriart/Mirai).

## Spike test (do this first)

Before using this app, verify the Miracast stack manually:

```bash
# Check P2P capability
iw phy | grep -A20 "Supported interface modes" | grep -i P2P

# Terminal 1
sudo miracle-wifid --log-level debug

# Terminal 2
sudo miracle-sinkctl --log-level debug
```

Then on Windows: **Win+K** → look for the sink name. If the Pad never appears, the blocker is likely Wi-Fi P2P/driver/capability, not this app.

## Run the draft app

```bash
cd tools/pipa-miracast-sink
./scripts/run-dev.sh
```

Or:

```bash
PYTHONPATH=. python3 -m pipa_miracast_sink
```

## Known limitations / risks

- **Wi-Fi P2P on pipa (ath10k)** may be limited; this is the main unknown.
- **MiracleCast sinkctl integration** in this draft is skeleton-level; real event parsing/PTY or DBus control needs hardening.
- **Windows Miracast behavior** can be picky (caps, PIN, HDCP, firewall/network state).
- **HDCP-protected content** will not play.
- **Latency** is expected; suitable for desktop/docs, not gaming.

## Next steps

- [ ] Validate P2P support on pipa with `iw phy`
- [ ] Validate MiracleCast sink appears in Windows Win+K
- [ ] Replace sinkctl stdout parsing with robust PTY/DBus event handling
- [ ] Add proper GStreamer pipeline for Miracast RTP/H.264/AAC
- [ ] Add fullscreen/player window and reconnect handling
- [ ] Package as RPM/Flatpak or install script for the image
