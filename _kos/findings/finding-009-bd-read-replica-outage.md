# finding-009: a local read replica keeps bd fresh but does not keep it reading through a primary outage; the runbook's outage claim holds only for the dolt CLI

Date: 2026-11-02
Status: measured on scratch Dolt 2.2.3 servers with bd 1.1.2 (one host, loopback, scratch data, a sandbox that allowed only localhost and only scratch writes); Dolt docs and source read at v2.2.3 and v2.6.2. Nothing was pointed at a live server.
Asks: I-149. Extends `docs/runbooks/read-replica.md` (2026-08-16).

## Headline

A fleet machine that wants bd reads to be local, and to keep working while the one read-write server or the LAN is down, cannot get both from any setting measured here.

- A pull-on-read replica served by `dolt sql-server --readonly` gives local, fresh reads (a primary write was visible in 0.18 s) and refuses local writes. But while the primary is down, every bd read on it fails.
- The runbook's "reads survive a hub outage by default" is true only for the dolt CLI, where each `dolt sql` is a new process started after the hub went away. Through a running `sql-server`, which is what bd talks to, it is false.

Read-locality is cheap. Outage survival needs a different shape, and that shape is not yet measured.

## 1. What was measured

Scratch primary, then three kinds of local copy, each with bd 1.1.2 pointed at it over the MySQL protocol.

| case | result |
|---|---|
| pull-on-read replica on `sql-server`, primary up | bd sees a primary write in 0.17 s |
| same, primary stops (replica started while it was up, `dolt_skip_replication_errors` 0) | bd ready, list, show rc 1: `Error 1105 (HY000): replication error: rpc error: code = Unavailable`; plain SQL fails the same way |
| same, `dolt_skip_replication_errors` 1 set before the outage | plain SQL select rc 0 with stale rows; bd list rc 1 after about 3 minutes of client read timeouts, `begin read tx: invalid connection` |
| replica `sql-server` started while the primary is already down | serves last-known data to bd, rc 0, and does not pull within 30 s after the primary returns; it needs its own restart |
| primary restarts under a running replica started while the primary was up | pulls with no replica restart: 14.65 s (skip 0), 40.62 s (skip 1) |
| replica variables plus `sql-server --readonly` | primary write pulled in 0.18 s; a local SQL UPDATE and a bd sql insert both rc 1, `database server is set to read only mode`; with the primary down, reads fail as in row 2. Control: a writable replica accepted the same UPDATE |
| replica variables persisted in the database's own `.dolt/config.json` (as `kit/replica.sh` does), server started with `--data-dir` one level up | variables ignored: stale data, rc 0, no warning, 43 s, twice |
| plain clone served `--readonly` | ready, list, show, search, blocked rc 0; `bd stats` and `bd stale` rc 1, because bd creates `schema_migrations` on open, and that table is in `dolt_ignore`, so a clone does not have it |
| `bd --readonly` against the read-write primary | create, update --claim, comments add, close rc 1, `operation '<op>' is not allowed in read-only mode`; list rc 0 |
| bd create on a replica | rc 1, `issue_prefix config is missing`, because the primary's config table was uncommitted when cloned |

## 2. What the docs and code say

- **Remote-based replica.** It pulls at each transaction start. With `dolt_skip_replication_errors` at its default of 0, a failed pull fails the query. With 1, it warns and continues (dolt `sqle/dsess/session.go` at v2.2.3). The measurement agrees for plain SQL. bd still fails under skip 1, apparently because each transaction waits on the dead dial [inferred].
- **Cluster replication** (`cluster:` config, standbys). The primary pushes every SQL commit to standbys directly, asynchronously by default (`dolt_cluster_ack_writes_timeout_secs` 0, maximum 60). A standby rejects writes and serves reads. Servers never promote themselves, so failover is manual and "not guaranteed to be lossless". Lag shows only in `dolt_cluster.dolt_cluster_status`. A standby that is behind gives readers no error. The docs imply a standby keeps serving reads while the primary is down; that is not measured here.
- **remotesapi** (needed by any replica that pulls from the primary). It is a listener only: a config edit and a restart, with no data migration. `remotesapi.read_only` accepts clone, pull and fetch but not push. Clone and pull need `CLONE_ADMIN`. It reuses the `listener` TLS settings. On 2.2.3 the password check resolves the user as localhost (fixed in 2.3.0, #11534), so a user scoped to one peer host may fail to authenticate [inferred from code].
- **Version gap.** Latest release is 2.6.2 (2026-10-31); the primary here runs 2.2.3.
  - The storage feature version is 7 at both, so they open each other's data, with one exception: a 2.2.3 reader can misread a DESC index created by 2.3.3 or later (#11746).
  - 2.5.0 fixes unauthenticated cluster role demotion (#12090) and a remotesrv upload path traversal (#12089). Both bear on cluster mode and on a writable remotesapi.
  - Breaking changes: 2.4.0 (`INSERT ... ON DUPLICATE KEY UPDATE` needs UPDATE), 2.5.0 (multi-branch commits), 2.6.0 (`dolt_merge` walks the full graph).

## 3. Staleness signal

- `hashof('main')` against the origin tracking hash reads equal even while the replica is two commits behind, so it is not a check.
- The head date in `dolt_log` and `max(updated_at)` over the issues table do give the copy's age.
- On a running pull-on-read replica, a successful read is itself the freshness proof, because the read would have failed had the pull failed [inferred].
- On a copy that serves stale data, nothing in the exit code says so. Rows 4 and 7 in section 1 are the silent cases.

## 4. What this means for the kit

1. `docs/runbooks/read-replica.md` overstates outage survival. Its measured line came from the CLI path. It should say that a `sql-server` replica fails reads while the hub is down, and that only a server started during an outage serves stale data, and then never resumes pulling until it is restarted.
2. `kit/replica.sh` persists the variables where a `--data-dir` server will not read them. The kit should either set them at server level or have `kit/doctor.sh` check them through the server that bd uses. The doctor already asks the engine; it should ask the same server bd is configured for.
3. A replica must be served `--readonly`, or local writes land where nothing syncs them (row 6 control).
4. bd 1.1.2 has one server address for reads and writes. Splitting them needs a wrapper or the seat's own discipline: reads at the local copy, every write at the primary. `bd --readonly` on the local address blocks a write sent there by mistake.
5. A plain clone breaks `bd stats` and `bd stale` until `schema_migrations` exists in the copy. Pull-on-read replicas did not show this.

## 5. Shapes still open

| shape | local reads | fresh | reads through an outage | measured |
|---|---|---|---|---|
| A. pull-on-read replica, `--readonly` | yes | yes, at each read | no | yes |
| B. clone refreshed on a timer into a new directory, swapped behind a `--readonly` server (the readonly-view pattern) | yes | to the timer | yes, by construction [inferred] | no |
| C. cluster standby, after upgrading to 2.5.0 or later | yes | async push | yes, per docs | no |
| D. no local copy (today) | no | yes | no | yes |

B and C are the two candidates that meet the stated goal. Both need a scratch trial before a choice: B for the swap and the `schema_migrations` gap, C for standby reads during an outage, failover, and users and grants (the docs and the 2.2.3 code disagree on whether those replicate).
