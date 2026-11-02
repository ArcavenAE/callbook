# finding-010: Dolt 2.6.2 works with bd 1.1.2, and a cluster standby keeps bd reads going through a primary outage, with three conditions

Date: 2026-11-02
Status: measured on scratch Dolt 2.6.2 and 2.2.3 servers with bd 1.1.2 (one host, loopback, scratch data, a sandbox that allowed only localhost and only scratch writes). Nothing was pointed at a live server. Follows finding-009 (the replica options) and answers issues #14 and #15.
Sources: the figures are in the comments on #14 and #15, and the readings comment on #15 (issuecomment-6588288780) carries the setup keys, status rows, counts and grant runs. The Dolt version and default facts (2.5.0 with #12089 and #12090, 2.3.3 with #11746, `dolt_cluster_ack_writes_timeout_secs` 0) are the docs and release-note reading in finding-009 section 2, not measurements.
Asks: the bdreplica-1 card (a Dolt cluster standby, once Dolt is at 2.5.0 or later, per finding-009 section 2). Extends `docs/runbooks/read-replica.md`.

## Headline

A cluster standby gives a fleet machine local bd reads that keep working while the primary is down, which a pull-on-read replica did not (finding-009). Three conditions apply before a real host changes:

- Replication is asynchronous, so the last write before an outage can be lost.
- The bd database user needs EXECUTE (or ALL) as well as select, insert, update and delete, and the 2.4.0 UPDATE requirement applies.
- Two cluster servers on one host need separate home directories.

Dolt 2.6.2 itself passed every bd command tried, on data written by 2.2.3.

## 1. Dolt 2.6.2 against bd 1.1.2 (issue #14)

Method: the 2.6.2 and 2.2.3 release tarballs, each checked against its published sha256, run on random loopback ports with a scratch home. Seed data (3 issues, a dependency, a comment, a claim, a close) was created under 2.2.3, then the same data directory was served by 2.6.2.

| check | result |
|---|---|
| bd ready, list, show, stats, status, stale, count, search, history on 2.6.2 over 2.2.3 data | rc 0 |
| bd create, update, update --claim, comments add, dep add, reopen, close, export on 2.6.2 | rc 0 |
| bd close of an issue with an open blocker | rc 1, bd's own rule ("blocked by open issues") |
| 2.4.0, `INSERT ... ON DUPLICATE KEY UPDATE` needs UPDATE | confirmed: a select-and-insert user got Error 1142; root passed; bd 1.1.2 contains 10 such statements |
| 2.5.0, multi-branch commits | commits on a second branch and on main from separate sessions succeeded; bd works on main only |
| 2.6.0, `dolt_merge` over the full graph | a merge of diverged branches returned "merge successful", no conflicts |
| a 2.2.3 server reading data last written by 2.6.2 (dolthub/dolt#11746 direction; finding-009 section 2) | bd ready, list, show, stale and create rc 0; no DESC index exists in bd's schema as created here, so the misread was not exercised |

Every reader host upgrades together: #11746 (finding-009 section 2) describes a 2.2.3 reader misreading a DESC index made by 2.3.3 or later, and this run could not exercise it.

## 2. Cluster standby (issue #15)

Setup: a primary (127.0.0.1, remotesapi on its own port) and a standby, each with its own data directory and its own home directory, configured as in the Dolt replication page (each server lists the other as `standby_remotes`; `bootstrap_role` primary and standby, epoch 1).

| question | result |
|---|---|
| a standby follows the primary | the database appeared on the standby with no setup there; `dolt_cluster.dolt_cluster_status` on the primary: one row, replication_lag_millis 0, current_error NULL |
| bd reads from the standby | ready, list, show, stats, stale, count all rc 0 |
| bd write to the standby | rc 1, "Database scratchdb is read-only" |
| lag | 0 ms idle; 254 ms right after a burst of 30 bd creates; 0 within 2 s |
| users and grants | a user and grant created on the primary connected to the standby within 3 s (the replication page lists them as not replicated; on 2.6.2 here they were) |
| primary stopped (SIGKILL) | bd ready, list, show, stats, stale, count on the standby: rc 0, each under 1 s; a write to the standby rc 1 |
| the last write before the kill | absent on the standby (asynchronous; `dolt_cluster_ack_writes_timeout_secs` defaults to 0, per finding-009 section 2), and absent on both servers afterwards |
| manual failover | on the standby, `call dolt_assume_cluster_role('primary', 2);` took effect at once; bd wrote to it |
| the old primary returns with its old role (primary, epoch 1) | within 6 s it reported standby at epoch 2, held the post-failover write, and rejected writes; counts matched on both servers (35 and 35) after 30 more writes |
| `bd stats` and `bd stale` on a standby | rc 0 (finding-009 saw them fail on a read-only plain clone; that shape is different) |

Not separated: whether the last pre-kill write never reached the old primary's disk, or was overwritten when the old primary rejoined.

## 3. Conditions

1. **Privileges.** With select, insert, update and delete only, bd create, update and close returned rc 1: the denied statements were `CALL DOLT_ADD` and `CALL DOLT_COMMIT`, and a create left its row inserted before the commit failed. With EXECUTE added, all three returned rc 0, as did ALL PRIVILEGES. The UPDATE requirement from section 1 applies as well.
2. **One home per server.** The cluster role is persisted in the home-level Dolt config (`sqlserver.cluster.dolt_cluster_role` in `$HOME/.dolt/config_global.json`). Two cluster servers sharing one home both reported `detected_broken_config`, even alone. A separate home per server fixed it.
3. **The remotesapi listener.** It bound all interfaces, not only loopback, in this run. A real host needs it restricted; TLS and authentication on remotesapi were not exercised.

## 4. What this means for the kit

1. A standby meets the stated goal (local reads that survive a primary outage) where shape A of finding-009 did not. Shape C of finding-009 section 5 is now measured on one host.
2. The asynchronous loss window is the cost. A write the caller needs to survive a primary loss needs `dolt_cluster_ack_writes_timeout_secs` above 0 (the setting is from finding-009 section 2), which was not measured here.
3. The bd user's grants belong in the kit's setup text: select, insert, update, delete and execute at least.
4. Upgrade every reader host together, to 2.5.0 or later (dolthub/dolt#12090 and #12089 bear on cluster mode and on a writable remotesapi; finding-009 section 2).
5. `docs/runbooks/read-replica.md` and `kit/replica.sh` still need the corrections from finding-009 section 4 (issue #16).

## 5. Not measured

A standby on another host, TLS and authentication on remotesapi, a long outage, acknowledged writes, `DROP DATABASE` (documented as not replicated), the real data size, and the real bd user's grants.
