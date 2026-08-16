# Runbook: a local read replica of a project tracker

> Scope: the edge half of pattern 5 in [patterns.md](../patterns.md).
> A fleet machine serves its agents bulk reads locally while every
> write and claim goes to the project's write plane.
>
> Honesty label: the replica mechanism (clone over remotesapi,
> persisted read-replica vars, pull-on-read, serve-stale-when-hub-down)
> is verified on a loopback pair (Dolt 2.2.3, 2026-08-16; transcript
> lines quoted below). Running it against a TLS-required production
> tracker reuses the same remotesapi surface the production recipe
> already verified from the internet, but the combined path is an
> untested translation until drilled; so is serving the replica
> through its own sql-server (same engine config, no wire client on
> the verification machine).

## The mechanism

A Dolt read replica is a clone that pulls from its remote at
transaction start. Two persisted system variables in the replica's
directory do all the work:

```sh
dolt sql -q "SET @@persist.dolt_read_replica_remote = 'origin';
             SET @@persist.dolt_replicate_heads = 'main';"
```

After that, every read transaction fetches `main` from the hub first.
There is no timer to tune for correctness: a read is as fresh as the
hub's last dolt commit at the moment the read begins. Verified on the
loopback pair: a row committed on the hub after the clone appeared in
a plain `SELECT` at the replica with zero manual pulls.

Two consequences worth holding on to:

- **Freshness is bounded by the hub's dolt-commit cadence, not by any
  replica setting.** Replicas pull committed heads. A bd-backed hub
  commits per write operation (`bd: create ...`, `bd: comment ...`),
  so replicas see bd writes promptly. A hub whose SQL clients never
  produce dolt commits never propagates anything.
- **The replica needs no always-on process.** Pull-on-read works from
  CLI transactions and from a replica-local `dolt sql-server` alike
  (the vars persist in the replica directory). An optional keep-warm
  timer exists only to bound staleness for the DR copy when nobody is
  reading; it is not part of the correctness story.

## Standing one up

Prerequisites: the project's tracker exposes remotesapi (the
production recipe's second listener, port 8000), and this machine has
a credential for it. remotesapi authenticates with SQL accounts; the
ro tier suffices, since it carries `CLONE_ADMIN`. If the machine is
enrolled (`kit/enroll.sh <project> --tier ro`), the kit reuses that
enrollment.

```sh
kit/replica.sh <project> --host dolt-<project>.trackers.example.com
# or, explicit URL and database:
kit/replica.sh <project> --source https://<host>:8000/<db>
# optional keep-warm timer (macOS / Linux):
kit/replica.sh <project> --host <host> --timer launchd --interval 300
```

The script clones into `~/.beads/replicas/<project>/`, persists the
two variables, and (with `--timer`) installs a periodic
`dolt sql -q "SELECT 1"` job, which exercises exactly the pull path
agents use. Idempotent: re-running refreshes configuration and leaves
the clone alone.

Manual equivalent, for one-off or air-gapped setups:

```sh
mkdir -p ~/.beads/replicas && cd ~/.beads/replicas
DOLT_REMOTE_USER=<project>_ro DOLT_REMOTE_PASSWORD=... \
  dolt clone "https://<host>:8000/<db>" <project>
cd <project>
dolt sql -q "SET @@persist.dolt_read_replica_remote = 'origin';
             SET @@persist.dolt_replicate_heads = 'main';"
```

## The routing rule

The replica exists so the write plane spends its budget on writes.
Route accordingly, and wire the rule into agent instructions:

| Operation | Where |
|---|---|
| Writes, claims, closes | write plane (the tracker), always |
| "Did my claim land", "is this bead still open" before acting | write plane |
| `bd ready` polling, list views, dashboards | replica |
| History, blame, diff, analytics over `dolt_log` | replica |
| Warm DR source | the replica itself |

Freshness-critical reads are precisely the ones feeding a decision
that a concurrent write could invalidate; those belong on the write
plane with the writes. Everything else tolerates seconds of lag.

## Failure modes

- **Hub unreachable.** The replica logs one error line and serves
  last-known data with a zero exit. Measured on the loopback pair:

  ```
  level=error msg="invalid replication configuration, replication
  disabled: failed to load replica database from remote 'origin' ...
  connect: connection refused"
  +----+---------------------------+
  | id | v                         |
  ...
  exit: 0
  ```

  Reads survive a hub outage by default; nothing to configure. Pull
  resumes when the hub returns. Writes do NOT fail over to the
  replica, ever; a fleet machine that loses the write plane queues or
  waits (pattern 5, rule 4).
- **Replica written by mistake.** Treat the replica as read-only.
  Nothing syncs a replica-side write anywhere, and local edits sit in
  the working set masking replicated values. Untested translation:
  the exact collision behavior of a dirty working set under
  pull-on-read has not been drilled; keep replicas clean.
- **Staleness while idle.** Pull happens on read, so an unread
  replica ages. If the replica doubles as the machine's warm DR copy,
  add the keep-warm timer to bound how far behind a restore point can
  be.

## Verify

`kit/doctor.sh` checks each directory under `~/.beads/replicas/`:
that the read-replica variables are EFFECTIVE (asked of the engine,
not read from a config file), and that a live read pulls, warning
instead of failing when the hub is unreachable, since serving
last-known data is the designed behavior.

## Teardown

```sh
# remove the keep-warm job if installed
launchctl bootout "gui/$(id -u)/com.arcaven.callbook.beads-replica-<project>" 2>/dev/null
systemctl --user disable --now beads-replica-<project>.timer 2>/dev/null
rm -f ~/Library/LaunchAgents/com.arcaven.callbook.beads-replica-<project>.plist
rm -f ~/.config/systemd/user/beads-replica-<project>.{service,timer}
# the clone itself
rm -rf ~/.beads/replicas/<project>
```

Nothing on the hub side ever knew the replica existed; there is
nothing to deregister.
