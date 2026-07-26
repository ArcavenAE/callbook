# Reference: the local shared server, as actually built

> The founding local instance: a launchd-managed `dolt sql-server` that
> has been running a multi-project bd workload (several concurrent agent
> sessions, tap-free writes) since 2026-05. This is the shape
> `kit/install.sh` generalizes. Where the kit currently differs, the
> delta is listed at the end.

## Topology

One loopback-only dolt sql-server for the whole machine; every project's
bd points at it. One database per project (`<project>` with hyphens →
underscores), plus bd's `beads_global`.

```
~/.beads/shared-server/
├── config.yaml          # listener 127.0.0.1:3307, data_dir, cfg_dir
├── bin/
│   ├── start.sh         # exec dolt sql-server --config ... (launchd target)
│   └── client-env.sh    # client env: host/port + password from OS keychain
├── .doltcfg/            # dolt-managed privilege file (server-side auth)
├── <project_db>/        # one dolt database directory per project
├── beads_global/
└── logs/                # stdout.log, stderr.log, bootstrap.log
```

## Server side

**config.yaml:**

```yaml
log_level: info
log_format: text
behavior:
  read_only: false
  autocommit: true
listener:
  host: 127.0.0.1
  port: 3307            # NOT 3306: leaves room for local MySQL, and
                        # makes accidental non-loopback exposure obvious
  max_connections: 100
data_dir: ~/.beads/shared-server
cfg_dir: ~/.beads/shared-server/.doltcfg
```

**start.sh** is a two-line wrapper (`exec dolt sql-server --config ...`)
so launchd has a stable program target. Server-side auth lives in the
dolt-managed privilege file under `.doltcfg/`: a named `beads` user
with a generated password, created once at bootstrap. The server never
reads the OS keychain; only clients do.

**launchd** (`~/Library/LaunchAgents/com.<org>.beads-dolt-server.plist`):
`RunAtLoad` + `KeepAlive` (restart on crash), `ThrottleInterval: 10`,
stdout/stderr to the logs dir, explicit `PATH` in
`EnvironmentVariables` (launchd jobs don't inherit your shell PATH;
dolt must be findable).

## Client side

**client-env.sh**, sourced from the shell rc:

```sh
export BEADS_DOLT_AUTO_START=false
export BEADS_DOLT_SERVER_HOST=127.0.0.1
export BEADS_DOLT_SERVER_PORT=3307
if BEADS_DOLT_PASSWORD=$(security find-generic-password -s beads-dolt -a beads -w 2>/dev/null); then
    export BEADS_DOLT_PASSWORD
else
    unset BEADS_DOLT_PASSWORD
fi
```

The password lives in the macOS Keychain (service `beads-dolt`, account
`beads`), never in a file. The Linux analogue is `secret-tool lookup`
(libsecret). Fail-open to unset (rather than a broken empty export) so
a missing keychain entry produces a clean auth error, not a mystery.

**Per-project `.beads/metadata.json`** (written by `bd init` under the
env above):

```json
{
  "backend": "dolt",
  "dolt_mode": "server",
  "dolt_server_host": "127.0.0.1",
  "dolt_server_port": 3307,
  "dolt_server_user": "beads",
  "dolt_database": "<project_db>",
  "global_dolt_database": "beads_global"
}
```

## Bootstrap gotchas (all hit in practice)

1. **The env vars are load-bearing.** Without
   `BEADS_DOLT_AUTO_START=false` + explicit host/port, bd hashes the
   project path to derive a per-project port and tries to auto-start
   its own server; it will not find yours.
2. **bd's `--external` flag is runtime-only**: it is not persisted to
   `metadata.json`; the env vars (and the resulting metadata) are what
   stick.
3. **`bd init` probes the *git* remote** for `refs/dolt/data` and
   refuses if it finds one (it assumes the dolt-remote-via-git
   pattern). If your repo previously used that pattern, temporarily
   rename the git remote during init.
4. **Pre-create `beads_global`** and grant your bd user on it; bd
   wants it to exist even in external-server mode.
5. **bd's auto-backup wants `SUPER`** on the server user.
6. **Git hooks run in non-interactive shells.** Anything bd-invoking in
   a hook must source the client env itself (one line at the top of the
   hook, outside any tool-managed marker block so reinstalls don't eat
   it). Interactive-rc-only wiring silently falls back to embedded mode
   inside hooks.

## Companion pieces

- **JSONL archival**: a script exports each project's issues to its
  repo-tracked `.beads/issues.jsonl` (projection, not source of truth)
  and commits; a second LaunchAgent fires a staleness reminder
  (every 6h, notify if the last archive is >48h old). Cloud remotes are
  not involved; the git channel is the offsite copy.
- **Trade-offs accepted**: moving from embedded-per-project to the
  shared server removed the dolt-remote-on-git-host path (init refuses
  it; gotcha 3) and DR-via-`git clone`; the JSONL archival path plus
  the standard backup drills replace them. Gained: tap-free writes
  under hardware-token signing, safe concurrent multi-session writes.

## Delta vs `kit/install.sh` (v0)

The kit currently stands up the simpler shape: root user, no keychain,
port 3307 loopback. Not yet generalized from the as-built: the named
`beads` user + OS-keychain password (macOS `security` / Linux
`secret-tool`), `beads_global` pre-create, and the archival
reminder agent. Tracked as charter F2 (kit maturity).
