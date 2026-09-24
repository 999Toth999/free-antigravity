#!/usr/bin/env bash
# Starts the free-antigravity zen-free adapter (and the agy proxy if missing).
# Used by install.sh as a fallback when systemd is unavailable.
set -euo pipefail
CFG_DIR="$HOME/.free-antigravity"
ADAPTER_DIR="$CFG_DIR/zen-adapter"
ADAPTER_PORT="${ZEN_PORT:-4011}"

is_up() { curl -sf --max-time 2 "http://127.0.0.1:${1}/healthz" >/dev/null 2>&1 || curl -sf --max-time 2 "http://127.0.0.1:${1}/health" >/dev/null 2>&1; }

cd "$ADAPTER_DIR"
if is_up "$ADAPTER_PORT"; then
  echo "[ok] zen-free adapter already running on :$ADAPTER_PORT"
else
  echo "[..] starting zen-free adapter on :$ADAPTER_PORT"
  nohup node server.js > adapter.log 2>&1 &
  disown 2>/dev/null || true
  sleep 2
  is_up "$ADAPTER_PORT" && echo "[ok] zen-free adapter up (log: $ADAPTER_DIR/adapter.log)" || { echo "[!!] adapter failed — see $ADAPTER_DIR/adapter.log"; exit 1; }
fi

if is_up 50998; then
  echo "[ok] agy proxy already running on :50998"
else
  echo "[..] starting agy proxy on :50998 (started on demand — run 'free-antigravity' with the proxy)"
  echo "[..] hint: the proxy auto-starts when you launch 'free-antigravity'; this wrapper only ensures the adapter."
fi

echo
echo "Ready. Launch with:"
echo "    free-antigravity"
echo "Then select a 'Zen Free: ...' model."