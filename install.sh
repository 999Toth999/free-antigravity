#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# free-antigravity — use Antigravity (agy) with OpenCode Zen free models
#
# This script does EVERYTHING:
#   1. Detects OS and package manager
#   2. Installs Node.js >= 18 if missing
#   3. Installs the official OpenCode CLI if missing
#   4. Installs the official Antigravity CLI (agy) if missing
#   5. Installs free-antigravity-cli (npm) if missing
#   6. Installs the zen-free adapter (server.js) + models into ~/.free-antigravity
#   7. Starts the adapter and the agy proxy, verifies the full pipeline
#
# Usage: bash install.sh
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

BOLD="\033[1m"; DIMM="\033[2m"; GREEN="\033[32m"; YELLOW="\033[33m"; RED="\033[31m"; RESET="\033[0m"
info()  { printf "${GREEN}✔${RESET} %s\n" "$*"; }
warn()  { printf "${YELLOW}!${RESET} %s\n" "$*"; }
fail()  { printf "${RED}✘${RESET} %s\n" "$*"; exit 1; }
step()  { printf "\n${BOLD}==> %s${RESET}\n" "$*"; }

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG_DIR="$HOME/.free-antigravity"
ADAPTER_DIR="$CFG_DIR/zen-adapter"
ADAPTER_PORT="${ZEN_PORT:-4011}"
ADAPTER_URL="http://127.0.0.1:${ADAPTER_PORT}"

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
  Linux*)  PLATFORM="linux" ;;
  Darwin*) PLATFORM="macos" ;;
  MINGW*|MSYS*|CYGWIN*) warn "Windows detected — run this script inside Git Bash/WSL2 with a Unix environment." ;;
esac
: "${PLATFORM:=linux}"
info "OS: $OS ($PLATFORM, $ARCH)"

# ── helpers ────────────────────────────────────────────────────────────────
have() { command -v "$1" >/dev/null 2>&1; }
ver_ge() { # ver_ge "a.b.c" "x.y.z"
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]
}

ensure_node() {
  if have node && ver_ge "$(node -v | tr -d v)" "18.0.0"; then
    info "Node.js $(node -v) present ($(which node))"
    return
  fi
  step "Installing Node.js ≥ 18"
  if ! have npm && ! have node; then
    if [ "$PLATFORM" = "macos" ] && have brew; then
      brew install node
    elif [ "$PLATFORM" = "linux" ] && (have apt-get || have dnf || have yum || have pacman); then
      if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -y && sudo apt-get install -y nodejs npm
      else
        warn "No auto-install rule for your distro's package manager."
        warn "Install Node.js manually from https://nodejs.org then re-run."
        exit 1
      fi
    else
      warn "Install Node.js ≥ 18 manually from https://nodejs.org then re-run."
      exit 1
    fi
  fi
  if ! have node || ! ver_ge "$(node -v | tr -d v)" "18.0.0"; then
    fail "Node.js ≥ 18 still missing after install attempt."
  fi
  info "Node.js $(node -v) ready"
}

ensure_opencode() {
  if have opencode || [ -x "$HOME/.opencode/bin/opencode" ]; then
    OC="$HOME/.opencode/bin/opencode"
    info "OpenCode CLI present ($( [ -x "$OC" ] && echo "$OC" || echo "$(command -v opencode)" ))"
    return
  fi
  step "Installing OpenCode CLI (https://opencode.ai/install)"
  curl -fsSL https://opencode.ai/install | bash
  if [ ! -x "$HOME/.opencode/bin/opencode" ]; then fail "OpenCode install failed."; fi
  info "OpenCode installed at $HOME/.opencode/bin/opencode"
  # Ensure PATH for this session + persist
  export PATH="$HOME/.opencode/bin:$PATH"
  if ! grep -q '.opencode/bin' "$HOME/.bashrc" 2>/dev/null; then
    printf '\nexport PATH="$HOME/.opencode/bin:$PATH"\n' >> "$HOME/.bashrc"
  fi
  if [ "$PLATFORM" = "macos" ] && [ -f "$HOME/.zshrc" ] && ! grep -q '.opencode/bin' "$HOME/.zshrc"; then
    printf '\nexport PATH="$HOME/.opencode/bin:$PATH"\n' >> "$HOME/.zshrc"
  fi
}

ensure_agy() {
  if have agy || [ -x "$HOME/.local/bin/agy" ] || [ -x "$HOME/.local/share/agy/bin/agy" ]; then
    info "Antigravity CLI present ($( command -v agy 2>/dev/null || echo "$HOME/.local/bin/agy" ))"
    return
  fi
  step "Installing official Antigravity CLI (https://antigravity.google/cli/install.sh)"
  curl -fsSL https://antigravity.google/cli/install.sh | bash
  if [ ! -x "$HOME/.local/bin/agy" ]; then fail "Antigravity CLI install failed."; fi
  info "Antigravity CLI installed at $HOME/.local/bin/agy"
}

ensure_free_antigravity_cli() {
  if have free-antigravity || have antigravity; then
    info "free-antigravity-cli present ($( command -v free-antigravity 2>/dev/null || command -v antigravity ))"
    return
  fi
  step "Installing free-antigravity-cli (npm install -g)"
  npm install -g free-antigravity-cli
  if ! have free-antigravity && ! have antigravity; then fail "free-antigravity-cli install failed."; fi
  info "free-antigravity-cli ready"
}

install_adapter() {
  step "Installing zen-free adapter + models"
  mkdir -p "$ADAPTER_DIR"
  cp -f "$SOURCE_DIR/server.js" "$ADAPTER_DIR/server.js"
  chmod +x "$ADAPTER_DIR/server.js"

  # Merge models into ~/.free-antigravity/models.json (keep existing models)
  mkdir -p "$CFG_DIR"
  if [ -f "$CFG_DIR/models.json" ]; then
    if have node; then
      node -e '
        const fs=require("fs"); const path=require("path");
        const main=process.argv[1], src=process.argv[2];
        let cur={models:[]};
        try{cur=JSON.parse(fs.readFileSync(main,"utf8"));}catch{}
        if(!Array.isArray(cur.models))cur.models=[];
        const want=JSON.parse(fs.readFileSync(src,"utf8")).models;
        const names=new Set(cur.models.map(m=>m.name));
        for(const m of want){ if(!names.has(m.name)){ cur.models.push(m); names.add(m.name); } }
        fs.writeFileSync(main, JSON.stringify(cur,null,2)+"\n","utf8");
      ' "$CFG_DIR/models.json" "$SOURCE_DIR/models.json"
      info "Merged zen-free models into $CFG_DIR/models.json"
    else
      cp -f "$SOURCE_DIR/models.json" "$CFG_DIR/models.json"
      info "models.json installed to $CFG_DIR/models.json"
    fi
  else
    cp -f "$SOURCE_DIR/models.json" "$CFG_DIR/models.json"
  fi
  info "Adapter installed at $ADAPTER_DIR/server.js"
}

# ── service helpers ────────────────────────────────────────────────────────
adapter_running() { curl -sf --max-time 2 "http://127.0.0.1:${ADAPTER_PORT}/healthz" >/dev/null 2>&1; }

start_adapter_bg() {
  if adapter_running; then info "zen-free adapter already running on :${ADAPTER_PORT}"; return 0; fi
  warn "No systemd detected — starting adapter in background (nohup)."
  warn "TIP: run 'bash $ADAPTER_DIR/start.sh' after every reboot, or set up a user service."
  nohup node "$ADAPTER_DIR/server.js" > "$ADAPTER_DIR/adapter.log" 2>&1 &
  disown 2>/dev/null || true
  sleep 2
  if adapter_running; then info "zen-free adapter started on :${ADAPTER_PORT}"; else fail "Adapter failed to start — see $ADAPTER_DIR/adapter.log"; fi
}

install_systemd_service() {
  # If a manual adapter already occupies the port, stop it so systemd can bind.
  if adapter_running; then
    # find the PID(s) listening on the adapter port and kill them
    for pid in $( (ss -tlnp 2>/dev/null | grep "127.0.0.1:${ADAPTER_PORT}" | grep -oP 'pid=\K[0-9]+' || true) | sort -u ); do
      warn "port :${ADAPTER_PORT} in use by pid ${pid} — stopping so systemd can take over"
      kill "$pid" 2>/dev/null || true
    done
    sleep 1
    for pid in $( (ss -tlnp 2>/dev/null | grep "127.0.0.1:${ADAPTER_PORT}" | grep -oP 'pid=\K[0-9]+' || true) | sort -u ); do
      [ "${pid:-x}" = "x" ] || kill -9 "$pid" 2>/dev/null || true
    done
  fi
  local unit="$HOME/.config/systemd/user/free-antigravity-adapter.service"
  mkdir -p "$(dirname "$unit")"
  cat > "$unit" <<EOF
[Unit]
Description=free-antigravity zen-free adapter (OpenCode Zen free tier proxy)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/env node $ADAPTER_DIR/server.js
Restart=on-failure
RestartSec=3
Environment=ZEN_PORT=$ADAPTER_PORT

[Install]
WantedBy=default.target
EOF
  if command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload >/dev/null 2>&1; then
    systemctl --user enable --now free-antigravity-adapter.service >/dev/null 2>&1 || true
    if systemctl --user is-active free-antigravity-adapter.service >/dev/null 2>&1; then
      info "systemd user service active (auto-starts on login)"
      return 0
    fi
  fi
  return 1
}

start_proxy() {
  # free-antigravity-cli starts its own proxy when launching agy; we just verify.
  if curl -sf --max-time 2 "http://127.0.0.1:50998/health" >/dev/null 2>&1; then
    info "agy proxy already running on :50998"
  else
    warn "agy proxy on :50998 not started yet (it starts automatically when you run 'free-antigravity')."
  fi
}

# ═══════════════════════════════════════════════════════════════════════════
#  main
# ═══════════════════════════════════════════════════════════════════════════
step "free-antigravity installer v1.0"
ensure_node
ensure_opencode
ensure_agy
ensure_free_antigravity_cli
install_adapter

step "Starting services"
if ! install_systemd_service; then start_adapter_bg; fi
start_proxy

step "Verification"
# give systemd a moment if it just (re)started
for _i in 1 2 3 4 5 6; do
  curl -sf --max-time 2 "http://127.0.0.1:${ADAPTER_PORT}/healthz" >/dev/null 2>&1 && break
  sleep 1
done
if curl -sf --max-time 3 "http://127.0.0.1:${ADAPTER_PORT}/healthz" >/dev/null 2>&1; then
  info "zen-free adapter: OK on :${ADAPTER_PORT}"
else
  warn "zen-free adapter: NOT reachable — run 'bash $ADAPTER_DIR/start.sh'"
fi

step "Done!"
if [ "$PLATFORM" = "linux" ]; then
  cat <<EOF

  To start Antigravity with the OpenCode Zen free models:

      export PATH="\$HOME/.opencode/bin:\$PATH"
      free-antigravity

  Then pick a model in the selector:
      - "Zen Free: big-pickle (opencode)"        (best)
      - "Zen Free: Mimo V2.5 (opencode)"
      - "Zen Free: Nemotron 3.5 Lightning (opencode)"

  Or test the adapter directly:

      curl $ADAPTER_URL/v1/chat/completions \\
        -H "Content-Type: application/json" \\
        -d '{"model":"big-pickle","messages":[{"role":"user","content":"hi"}],"stream":true}'

  NOTE: The official Antigravity CLI requires a Google sign-in (it uses the
  desktop app auth). The zen-free models route through the local adapter and
  do NOT need a paid key.
EOF
else
  cat <<EOF

  To start Antigravity with the OpenCode Zen free models run:
      free-antigravity
  Then select a "Zen Free: ..." model in the selector.

  Test the adapter:
      curl $ADAPTER_URL/v1/chat/completions \\
        -H "Content-Type: application/json" \\
        -d '{"model":"big-pickle","messages":[{"role":"user","content":"hi"}],"stream":true}'
EOF
fi