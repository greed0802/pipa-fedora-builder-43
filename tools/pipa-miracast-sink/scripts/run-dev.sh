#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

echo "[pipa-miracast-sink] Draft dev launcher"
echo "[pipa-miracast-sink] Checking key tools..."
for tool in miracle-wifid miracle-sinkctl gst-launch-1.0 iw; do
  if command -v "$tool" >/dev/null 2>&1; then
    echo "  ok: $tool"
  else
    echo "  missing: $tool"
  fi
done

echo "[pipa-miracast-sink] Starting GUI..."
exec python3 -m pipa_miracast_sink
