#!/usr/bin/env bash
# callbook kit: verify the local beads instance and (if present) enrollment.
# Exit non-zero on any hard failure. See docs/local-instance.md.
set -euo pipefail

SERVER_HOST="${BEADS_DOLT_SERVER_HOST:-127.0.0.1}"
SERVER_PORT="${BEADS_DOLT_SERVER_PORT:-3307}"
ENROLL_DIR="$HOME/.beads/enrollments"

rc=0
ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; rc=1; }

echo "callbook doctor"

# binaries
if command -v bd >/dev/null 2>&1; then
  BD_VER="$(bd version 2>/dev/null | head -1 || true)"
  ok "bd present ($BD_VER)"
  # proxied-server TLS support landed after 1.1.0; warn on anything <= 1.1.0
  if printf '%s' "$BD_VER" | grep -qE '\b(0\.[0-9.]+|1\.(0\.[0-9]+|1\.0))\b'; then
    warn "bd <= 1.1.0 cannot negotiate TLS to a shared tracker (local-only is fine)"
  fi
else
  bad "bd not found (run kit/install.sh)"
fi

if command -v dolt >/dev/null 2>&1; then
  ok "dolt present ($(dolt version | head -1))"
else
  bad "dolt not found (run kit/install.sh)"
fi

# client env
if [[ "${BEADS_DOLT_AUTO_START:-}" == "false" ]]; then
  ok "client env loaded (BEADS_DOLT_AUTO_START=false)"
else
  warn "client env not loaded: non-interactive shells (git hooks!) may fall back to embedded mode; source ~/.beads/client-env.sh"
fi

# server reachability
if command -v nc >/dev/null 2>&1 && nc -z "$SERVER_HOST" "$SERVER_PORT" 2>/dev/null; then
  ok "local server reachable at $SERVER_HOST:$SERVER_PORT"
else
  bad "no listener at $SERVER_HOST:$SERVER_PORT (start the server; see kit/install.sh output)"
fi

# actor + node identity
if [[ -n "${BEADS_ACTOR:-}" ]]; then
  ok "actor: $BEADS_ACTOR"
else
  warn "BEADS_ACTOR not set: work will be attributed to your OS user; agents MUST set a pool name (docs/vision.md)"
fi

# enrollments (shared-tracker attachments)
if [[ -d "$ENROLL_DIR" ]] && compgen -G "$ENROLL_DIR/*.env" >/dev/null; then
  for f in "$ENROLL_DIR"/*.env; do
    proj="$(basename "$f" .env)"
    perms="$(stat -f '%Lp' "$f" 2>/dev/null || stat -c '%a' "$f" 2>/dev/null)"
    if [[ "$perms" != "600" ]]; then
      bad "enrollment $proj: $f is mode $perms (must be 600)"
    else
      ok "enrolled: $proj"
    fi
    # TLS verification against the enrolled endpoint
    host="$(grep -E '^export CALLBOOK_TRACKER_HOST=' "$f" | cut -d= -f2- || true)"
    if [[ -n "$host" ]] && command -v openssl >/dev/null 2>&1; then
      if echo | openssl s_client -starttls mysql -connect "${host}:3306" -verify_return_error >/dev/null 2>&1; then
        ok "enrolled $proj: TLS verifies against ${host}:3306"
      else
        warn "enrolled $proj: TLS handshake to ${host}:3306 failed (offline, or cert problem)"
      fi
    fi
  done
else
  ok "no shared-tracker enrollments (local-only mode, a fully supported posture)"
fi

exit $rc
