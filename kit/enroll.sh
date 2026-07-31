#!/usr/bin/env bash
# callbook kit: attach this machine's local beads instance to a project's
# shared tracker. Fails closed; never writes credentials into git-tracked
# files. See docs/enrollment.md.
#
# Usage: enroll.sh <project> [--host <tracker-host>] [--tier rw|ro|admin]
#                  [--actor <pool-name>] [--federation]
#
# Credential fetch is pluggable: set CALLBOOK_CRED_COMMAND to any command
# that prints the account password to stdout. The strings {project} and
# {account} are substituted. Examples:
#   AWS SSM :  CALLBOOK_CRED_COMMAND='aws ssm get-parameter --with-decryption --query Parameter.Value --output text --name /dolt/{project}/users/{account}'
#   Vault   :  CALLBOOK_CRED_COMMAND='vault kv get -field=password secret/dolt/{project}/{account}'
#   1Passwd :  CALLBOOK_CRED_COMMAND='op read op://team/dolt-{project}-{account}/password'
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
say()  { printf '>> %s\n' "$*"; }

PROJECT="${1:-}"; shift || true
[[ -n "$PROJECT" ]] || fail "usage: enroll.sh <project> [--host H] [--tier rw|ro|admin] [--actor NAME] [--federation]"

TIER="rw"; HOST=""; ACTOR="${BEADS_ACTOR:-}"; FEDERATION=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier)  TIER="$2"; shift 2 ;;
    --host)  HOST="$2"; shift 2 ;;
    --actor) ACTOR="$2"; shift 2 ;;
    --federation) FEDERATION=true; shift ;;
    *) fail "unknown option: $1" ;;
  esac
done

[[ "$TIER" =~ ^(rw|ro|admin)$ ]] || fail "--tier must be rw, ro, or admin"
[[ -n "$HOST" ]] || fail "--host is required (e.g. dolt-$PROJECT.trackers.example.com)"
[[ -n "${CALLBOOK_CRED_COMMAND:-}" ]] || fail "CALLBOOK_CRED_COMMAND is not set (see header of this script)"

ACCOUNT="${PROJECT}_${TIER}"

# 1. fetch the credential (fail closed; no fallback to prompts or defaults)
CRED_CMD="${CALLBOOK_CRED_COMMAND//\{project\}/$PROJECT}"
CRED_CMD="${CRED_CMD//\{account\}/$ACCOUNT}"
say "fetching credential for $ACCOUNT"
PASSWORD="$(eval "$CRED_CMD")" || fail "credential fetch failed (command: $CRED_CMD)"
[[ -n "$PASSWORD" ]] || fail "credential fetch returned empty output"

# 2. verify TLS + auth before writing anything
if command -v mysql >/dev/null 2>&1; then
  say "verifying TLS connection as $ACCOUNT@$HOST"
  MYSQL_PWD="$PASSWORD" mysql -h "$HOST" -P 3306 -u "$ACCOUNT" --ssl-mode=REQUIRED -e "SELECT 1" >/dev/null \
    || fail "connection check failed: wrong credential, no network, or TLS problem"
else
  say "mysql client not found; skipping connection pre-check"
fi

# 3. write per-machine connection config (0600, outside any repo)
ENROLL_DIR="$HOME/.beads/enrollments"
mkdir -p "$ENROLL_DIR"
ENV_FILE="$ENROLL_DIR/$PROJECT.env"
umask 177
cat > "$ENV_FILE" <<EOF
# callbook enrollment: $PROJECT ($TIER tier). Source before bd commands
# in this project, or wire into direnv. NOT for git-tracked files.
export CALLBOOK_TRACKER_HOST=$HOST
# Direct server mode (primary path; works on any released bd >= 0.53.0).
# Caveat: 'bd init' drops the TLS setting in releases up to 1.1.2
# (upstream gastownhall/beads#3895); write the workspace config directly
# per docs/enrollment.md. Runtime commands honor these variables.
export BEADS_DOLT_SERVER_MODE=1
export BEADS_DOLT_SERVER_HOST=$HOST
export BEADS_DOLT_SERVER_PORT=3306
export BEADS_DOLT_SERVER_USER=$ACCOUNT
export BEADS_DOLT_SERVER_TLS=1
export BEADS_DOLT_PASSWORD=$PASSWORD
# Proxied-server mode (EXPERIMENTAL upstream; needs a post-1.1.0 HEAD
# build; today's only client-certificate path). Same endpoint/account.
export BEADS_PROXIED_SERVER_EXTERNAL_HOST=$HOST
export BEADS_PROXIED_SERVER_EXTERNAL_PORT=3306
export BEADS_PROXIED_SERVER_EXTERNAL_USER=$ACCOUNT
export BEADS_PROXIED_SERVER_EXTERNAL_PASSWORD=$PASSWORD
export BEADS_PROXIED_SERVER_EXTERNAL_TLS=1
EOF
umask 022
say "wrote $ENV_FILE (mode 600)"

# 4. federation peer instead of / in addition to direct SQL
if $FEDERATION; then
  say "federation mode: add the peer from your workspace with:"
  say "  bd federation add-peer ${HOST}:8000/<database>"
  say "(sync transport is the dolt remote protocol on :8000, not SQL)"
fi

# 5. actor identity
if [[ -n "$ACTOR" ]]; then
  say "actor: $ACTOR; ensure this name is in the project's name pool (docs/vision.md)"
  grep -q "BEADS_ACTOR" "$ENV_FILE" || echo "export BEADS_ACTOR=$ACTOR" >> "$ENV_FILE"
else
  say "no --actor given; humans default to their OS user, agents MUST set a pool name"
fi

say "enrolled. First attach of a NEW database from this machine may need --tier admin"
say "(known upstream gap: docs/enrollment.md). Verify with kit/doctor.sh."
