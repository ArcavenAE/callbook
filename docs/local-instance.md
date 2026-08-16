# The local instance

> Runbook for the Phase-1 kit: a local beads instance on every
> contributor's machine (including contributors who will never touch
> your cloud), with enrollment as an optional upgrade.

## Why a local shared server (and not embedded-per-project)

bd can run an embedded Dolt per project, but a single local
`dolt sql-server` shared by all your projects is the shape that scales
with real use:

- One daemon, one data directory (`~/.beads/shared-server/`), loopback
  only.
- Multiple concurrent sessions (several agents + you) write safely
  through one server instead of racing on embedded stores.
- The same connection model as the cloud tracker. Moving a project from
  local to shared later is a config change, not a migration of kind.

bd's storage engine is Dolt everywhere, including locally; SQLite
remains only in bd's legacy and ephemeral paths. Functionally this is
the "local instance" role.

## Install

```sh
kit/install.sh
```

Idempotent; macOS + Linux. It will:

1. Install `bd` and `dolt` if missing (brew on macOS, release binaries
   on Linux).
2. Initialize `~/.beads/shared-server/` and a loopback-only
   `dolt sql-server` config.
3. Write client env (`~/.beads/client-env.sh`, sourced from your shell
   rc) so every bd invocation finds the server.
4. Run a smoke `bd init` + create/close in a throwaway directory.

By default the server is started on demand. For always-on setups:

```sh
kit/install.sh --launchd    # macOS LaunchAgent
kit/install.sh --systemd    # Linux user unit
```

## Verify

```sh
kit/doctor.sh
```

Checks: bd version (init-TLS release gap), dolt version, server
reachability, TLS verification when enrolled, enrollment state,
`node_id` set, actor configured. Non-zero exit on any hard failure.

## Enroll (optional)

Attach your local instance to a project's shared tracker:

```sh
kit/enroll.sh <project> [--tier rw|ro] [--role agent] [--federation]
```

See [enrollment.md](enrollment.md) for what this does and the
credential-store plumbing (`CALLBOOK_CRED_COMMAND`).

## Disconnected operation

Spelled out, because it is a first-class mode and not a degraded one:

- **Fully offline work.** The local instance is authoritative; nothing
  phones home. Ever.
- **Working copies of a shared database.**
  `dolt clone https://<tracker-host>:8000/<db>` over remotesapi (the ro
  tier suffices; it carries `CLONE_ADMIN`); work offline; `dolt pull` /
  `dolt push` or `bd federation sync` on reconnect. Conflicts pause for
  manual resolution by default (`--strategy theirs|ours` to
  auto-resolve). This is the human-pace shape; an agent fleet keeps
  writes and claims on the shared tracker and runs the local instance
  as a read replica instead (pattern 5 in patterns.md).
- **Air-gap-tolerant channels.** The git channel (`refs/dolt/data` via
  `bd dolt push/pull`) and file/S3 dolt remotes need no reachable
  server at all.
- **Recovery.** If you run the backup store from the production recipe,
  it doubles as a bootstrap source: `dolt clone` from the backup remote
  on any credentialed host.

## The local instance in an agent fleet

When this machine hosts autonomous agents working shared projects,
the local instance's role shifts. It stays authoritative for
local-only projects. For enrolled projects it serves as read replica
and cache (agent polling, dashboards, history tooling, warm DR),
while every write and claim goes to the project's tracker under the
agent's own actor name, stamped by the spawner (`BEADS_ACTOR`).
Freshness-critical reads (is this bead still open, did my claim land)
go to the tracker; everything else may lag seconds. Derivation:
_kos/findings/ findings 003 through 006.

## Failure modes we hit so you don't

Recorded from live testing of this exact setup:

- **Per-machine bootstrap is real.** The first attach of a machine to an
  existing shared database needs the admin tier today (upstream gap;
  see enrollment.md). Plan the first attach; after that, rw is enough.
- **Env-var precedence matters.** bd's server-discovery env vars must be
  set before hooks and non-interactive shells run; put them in the
  client env file the installer writes, not in your interactive rc
  only. Git hooks run in non-interactive shells and will silently fall
  back to embedded mode if they can't see the server config.
- **Two ecosystems share the `.beads/` directory convention.** bd
  (beads) and third-party viewers may expect different filenames
  (`issues.jsonl` vs `beads.jsonl`); a stale file with the preferred
  name silently shadows fresh data. If a viewer looks wrong, check for
  shadow files before debugging the tool.
- **Don't `git stash` with tracker writes in flight** in any repo that
  git-tracks a JSONL projection: the stash captures the projection but
  not the database, and popping it time-travels the projection
  backwards. Re-export after pop rather than hand-resolving.
