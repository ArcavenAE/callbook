#!/usr/bin/env bash
# callbook kit: install bd + dolt and initialize the local shared server.
# Idempotent. macOS + Linux. See docs/local-instance.md.
#
# Usage: install.sh [--launchd | --systemd]
#   --launchd   also install a macOS LaunchAgent for an always-on server
#   --systemd   also install a systemd user unit (Linux)
set -euo pipefail

SERVER_DIR="${BEADS_LOCAL_SERVER_DIR:-$HOME/.beads/shared-server}"
SERVER_HOST="127.0.0.1"
SERVER_PORT="${BEADS_LOCAL_SERVER_PORT:-3307}"
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

say()  { printf '>> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

MODE="${1:-}"

# --- 1. binaries -------------------------------------------------------------
if ! command -v dolt >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    say "installing dolt via brew"
    brew install dolt
  else
    fail "dolt not found. Install it: https://docs.dolthub.com/introduction/installation"
  fi
fi

if ! command -v bd >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    say "installing beads via brew"
    brew install beads
  else
    fail "bd not found. Install beads: https://github.com/steveyegge/beads#installation"
  fi
fi

say "dolt $(dolt version | head -1 | awk '{print $NF}') / bd $(bd version 2>/dev/null | head -1 || echo '?')"

# --- 2. local shared server --------------------------------------------------
mkdir -p "$SERVER_DIR"/{data,logs}

CONFIG="$SERVER_DIR/config.yaml"
if [[ ! -f "$CONFIG" ]]; then
  say "writing $CONFIG (loopback-only listener on :$SERVER_PORT)"
  cat > "$CONFIG" <<EOF
log_level: info

behavior:
  read_only: false
  autocommit: true

listener:
  host: $SERVER_HOST
  port: $SERVER_PORT
  max_connections: 50

data_dir: $SERVER_DIR/data
EOF
else
  say "config exists: $CONFIG (leaving as-is)"
fi

# --- 3. client environment ---------------------------------------------------
CLIENT_ENV="$HOME/.beads/client-env.sh"
if [[ ! -f "$CLIENT_ENV" ]]; then
  say "writing $CLIENT_ENV"
  cat > "$CLIENT_ENV" <<EOF
# callbook kit: point every bd invocation at the local shared server.
# Sourced from your shell rc AND consumed by git hooks / non-interactive
# shells — keep it dependency-free.
export BEADS_DOLT_AUTO_START=false
export BEADS_DOLT_SERVER_HOST=$SERVER_HOST
export BEADS_DOLT_SERVER_PORT=$SERVER_PORT
EOF
else
  say "client env exists: $CLIENT_ENV (leaving as-is)"
fi

for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  if [[ -f "$rc" ]] && ! grep -q 'beads/client-env.sh' "$rc"; then
    say "adding client-env source line to $rc"
    # shellcheck disable=SC2016  # $HOME must land literally in the rc file
    printf '\n[ -f "$HOME/.beads/client-env.sh" ] && source "$HOME/.beads/client-env.sh"\n' >> "$rc"
  fi
done

# --- 4. optional always-on service --------------------------------------------
case "$MODE" in
  --launchd)
    [[ "$(uname -s)" == "Darwin" ]] || fail "--launchd is macOS-only"
    PLIST_SRC="$KIT_DIR/launchd/com.arcaven.callbook.beads-local.plist"
    PLIST_DST="$HOME/Library/LaunchAgents/com.arcaven.callbook.beads-local.plist"
    sed -e "s|__SERVER_DIR__|$SERVER_DIR|g" -e "s|__DOLT__|$(command -v dolt)|g" \
      "$PLIST_SRC" > "$PLIST_DST"
    launchctl bootstrap "gui/$(id -u)" "$PLIST_DST" 2>/dev/null \
      || launchctl kickstart -k "gui/$(id -u)/com.arcaven.callbook.beads-local"
    say "launchd service installed + started"
    ;;
  --systemd)
    command -v systemctl >/dev/null 2>&1 || fail "--systemd requires systemd"
    UNIT_DST="$HOME/.config/systemd/user/beads-local.service"
    mkdir -p "$(dirname "$UNIT_DST")"
    sed -e "s|__SERVER_DIR__|$SERVER_DIR|g" -e "s|__DOLT__|$(command -v dolt)|g" \
      "$KIT_DIR/systemd/beads-local.service" > "$UNIT_DST"
    systemctl --user daemon-reload
    systemctl --user enable --now beads-local.service
    say "systemd user service installed + started"
    ;;
  "")
    say "no service mode requested; start the server on demand with:"
    say "  dolt sql-server --config $CONFIG"
    ;;
  *)
    fail "unknown option: $MODE (expected --launchd or --systemd)"
    ;;
esac

# --- 5. smoke test -------------------------------------------------------------
if (command -v nc >/dev/null 2>&1 && nc -z "$SERVER_HOST" "$SERVER_PORT" 2>/dev/null); then
  SMOKE="$(mktemp -d)"
  say "server is up — running bd smoke test in $SMOKE"
  ( cd "$SMOKE" && \
    BEADS_DOLT_AUTO_START=false BEADS_DOLT_SERVER_HOST=$SERVER_HOST BEADS_DOLT_SERVER_PORT=$SERVER_PORT \
    bd init >/dev/null && bd create --title="kit smoke test" >/dev/null && \
    say "smoke test passed" ) || say "smoke test FAILED — run kit/doctor.sh"
  rm -rf "$SMOKE"
else
  say "server not running — skipped smoke test (start it, then run kit/doctor.sh)"
fi

say "done. Next: source $CLIENT_ENV (or open a new shell), then kit/doctor.sh"
