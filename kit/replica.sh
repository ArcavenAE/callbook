#!/usr/bin/env bash
# callbook kit: stand up a local READ replica of a project tracker
# (pattern 5 edge). Clones over remotesapi, persists Dolt read-replica
# variables (pull-on-read), optionally installs a keep-warm timer.
# Idempotent. Writes and claims stay on the write plane; the replica
# is read-only by convention. See docs/runbooks/read-replica.md.
#
# Usage: replica.sh <project> (--host <tracker-host> | --source <url>)
#                   [--db <name>] [--timer launchd|systemd] [--interval <sec>]
#
# Credentials: remotesapi authenticates with SQL accounts (ro tier
# suffices; it carries CLONE_ADMIN). Resolution order:
#   1. DOLT_REMOTE_USER / DOLT_REMOTE_PASSWORD already in the environment
#   2. the machine's enrollment file ~/.beads/enrollments/<project>.env
set -euo pipefail

say()  { printf '>> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

PROJECT="${1:-}"; shift || true
[[ -n "$PROJECT" ]] || fail "usage: replica.sh <project> (--host H | --source URL) [--db NAME] [--timer launchd|systemd] [--interval SEC]"

HOST=""; SOURCE=""; DB=""; TIMER=""; INTERVAL=300
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)     HOST="$2"; shift 2 ;;
    --source)   SOURCE="$2"; shift 2 ;;
    --db)       DB="$2"; shift 2 ;;
    --timer)    TIMER="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    *) fail "unknown option: $1" ;;
  esac
done

[[ -n "$HOST" || -n "$SOURCE" ]] || fail "one of --host or --source is required"
if [[ -n "$TIMER" ]]; then
  [[ "$TIMER" =~ ^(launchd|systemd)$ ]] || fail "--timer must be launchd or systemd"
fi
[[ "$INTERVAL" =~ ^[0-9]+$ ]] || fail "--interval must be seconds (integer)"

DB="${DB:-$PROJECT}"
SOURCE="${SOURCE:-https://$HOST:8000/$DB}"
REPLICA_ROOT="$HOME/.beads/replicas"
REPLICA_DIR="$REPLICA_ROOT/$PROJECT"
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. credentials (fail open to anonymous only if nothing is found) --------
ENROLL_FILE="$HOME/.beads/enrollments/$PROJECT.env"
if [[ -z "${DOLT_REMOTE_USER:-}" && -f "$ENROLL_FILE" ]]; then
  # shellcheck disable=SC1090  # per-machine file, not in the repo
  source "$ENROLL_FILE"
  if [[ -n "${BEADS_DOLT_SERVER_USER:-}" && -n "${BEADS_DOLT_PASSWORD:-}" ]]; then
    export DOLT_REMOTE_USER="$BEADS_DOLT_SERVER_USER"
    export DOLT_REMOTE_PASSWORD="$BEADS_DOLT_PASSWORD"
    say "using enrollment credentials ($DOLT_REMOTE_USER)"
  fi
fi
[[ -n "${DOLT_REMOTE_USER:-}" ]] || say "no remotesapi credential found; trying anonymous (fails against a production tracker)"

# --- 2. clone (idempotent) ---------------------------------------------------
mkdir -p "$REPLICA_ROOT"
if [[ -d "$REPLICA_DIR/.dolt" ]]; then
  say "replica exists: $REPLICA_DIR (leaving the clone as-is)"
else
  say "cloning $SOURCE -> $REPLICA_DIR"
  ( cd "$REPLICA_ROOT" && dolt clone "$SOURCE" "$PROJECT" ) \
    || fail "clone failed: check host, database name, and credentials (ro tier carries CLONE_ADMIN)"
fi

# --- 3. persist read-replica configuration (pull-on-read) --------------------
( cd "$REPLICA_DIR" && dolt sql -q \
  "SET @@persist.dolt_read_replica_remote = 'origin';
   SET @@persist.dolt_replicate_heads = 'main';" >/dev/null )
EFFECTIVE="$( (cd "$REPLICA_DIR" && dolt sql -q "SELECT @@dolt_read_replica_remote" -r csv 2>/dev/null | tail -1) || true)"
[[ "$EFFECTIVE" == "origin" ]] || fail "read-replica variable did not take (got: ${EFFECTIVE:-empty})"
say "pull-on-read effective (dolt_read_replica_remote=origin, heads=main)"

# --- 4. optional keep-warm timer ---------------------------------------------
case "$TIMER" in
  launchd)
    [[ "$(uname -s)" == "Darwin" ]] || fail "--timer launchd is macOS-only"
    LABEL="com.arcaven.callbook.beads-replica-$PROJECT"
    PLIST_DST="$HOME/Library/LaunchAgents/$LABEL.plist"
    sed -e "s|__LABEL__|$LABEL|g" \
        -e "s|__REPLICA_DIR__|$REPLICA_DIR|g" \
        -e "s|__DOLT__|$(command -v dolt)|g" \
        -e "s|__INTERVAL__|$INTERVAL|g" \
      "$KIT_DIR/launchd/com.arcaven.callbook.beads-replica.plist" > "$PLIST_DST"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
    say "launchd keep-warm timer installed (${INTERVAL}s): $LABEL"
    ;;
  systemd)
    command -v systemctl >/dev/null 2>&1 || fail "--timer systemd requires systemd"
    UNIT_DIR="$HOME/.config/systemd/user"
    mkdir -p "$UNIT_DIR"
    sed -e "s|__REPLICA_DIR__|$REPLICA_DIR|g" -e "s|__DOLT__|$(command -v dolt)|g" \
      "$KIT_DIR/systemd/beads-replica.service" > "$UNIT_DIR/beads-replica-$PROJECT.service"
    sed -e "s|__INTERVAL__|$INTERVAL|g" -e "s|__PROJECT__|$PROJECT|g" \
      "$KIT_DIR/systemd/beads-replica.timer" > "$UNIT_DIR/beads-replica-$PROJECT.timer"
    systemctl --user daemon-reload
    systemctl --user enable --now "beads-replica-$PROJECT.timer"
    say "systemd keep-warm timer installed (${INTERVAL}s): beads-replica-$PROJECT.timer"
    ;;
  "")
    say "no keep-warm timer requested; replicas pull on every read (add one only to bound DR staleness)"
    ;;
esac

say "done. Route bulk reads here; writes and claims stay on the write plane."
say "Verify with kit/doctor.sh. Runbook: docs/runbooks/read-replica.md"
