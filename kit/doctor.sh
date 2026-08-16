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
  # Direct-mode runtime TLS works on any release >= 0.53.0, but 'bd init'
  # drops the TLS setting in every release up to 1.1.2 (upstream
  # gastownhall/beads#3895; fixed on main 2026-07-04, not yet released).
  if printf '%s' "$BD_VER" | grep -qE '\b(0\.[0-9.]+|1\.(0\.[0-9]+|1\.[0-2]))\b'; then
    warn "bd <= 1.1.2: 'bd init' cannot attach to a TLS tracker (runtime commands are fine); write the workspace config directly per docs/enrollment.md"
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

# read replicas (pattern 5 edge; docs/runbooks/read-replica.md)
REPLICA_ROOT="$HOME/.beads/replicas"
if [[ -d "$REPLICA_ROOT" ]] && compgen -G "$REPLICA_ROOT/*/.dolt" >/dev/null; then
  for d in "$REPLICA_ROOT"/*/; do
    [[ -d "$d/.dolt" ]] || continue
    proj="$(basename "$d")"
    # ask the ENGINE, not a config file: the variable must be effective
    eff="$( (cd "$d" && dolt sql -q "SELECT @@dolt_read_replica_remote" -r csv 2>/dev/null | tail -1) || true)"
    if [[ -z "$eff" || "$eff" == '""' || "$eff" == "NULL" ]]; then
      bad "replica $proj: dolt_read_replica_remote not effective (re-run kit/replica.sh)"
      continue
    fi
    # a read triggers the pull; an unreachable hub is a warn, because
    # serving last-known data is the designed offline behavior
    pull_err="$( (cd "$d" && dolt sql -q "SELECT 1" -r csv 2>&1 >/dev/null) || true)"
    if printf '%s' "$pull_err" | grep -q "replication disabled"; then
      warn "replica $proj: hub unreachable; serving last-known data (pull resumes when the hub returns)"
    else
      ok "replica $proj: pull-on-read effective against remote '$eff'"
    fi
  done
else
  ok "no read replicas configured (the fleet edge is optional; docs/runbooks/read-replica.md)"
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
