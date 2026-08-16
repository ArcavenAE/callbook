# finding-007: bd HEAD survey; the liveness layer shipped upstream (leases + heartbeat + reclaim), rig means store not runtime, and the dormant columns are reserved surface

Date: 2026-08-16
Status: verified (targeted source reads of gastownhall/beads at main,
2026-08-16; release notes v1.2.1/v1.2.2; no clone taken, raw reads via
gh api). Executes aae-orc-usohe, the re-survey called for by
finding-006.
Canonical upstream: gastownhall/beads (steveyegge/beads redirects
there; ArcavenAE/beads forks it). Latest release v1.2.2 (2026-08-15).

## Headline

Upstream already built the liveness mechanism finding-005/006 deferred:
a claim now takes a TTL lease, `bd heartbeat` keeps it alive, and
`bd reclaim` is the reaper that reverts dead workers' issues to ready.
It shipped by accident in v1.2.1 (untested, pulled), is absent from
v1.2.2 (a recovery release: v1.1.2 code renumbered), and will return
"in a properly tested future release." Callbook should adopt this
mechanism, not build a parallel lease convention.

Separately, the survey corrects the rig direction: upstream rig means
a STORE (a project database, identified by its issue prefix), not a
worker's runtime locus. The rig-as-runtime-locus idea needs revision.

## Q1: what writes the dormant columns

`agent_state`, `last_activity`, `rig`, `actor`, `event_kind`,
`await_*`, `role_bead`, `hook_bead`, `work_type` are all in the BASE
schema (internal/storage/schema/migrations/0001_create_issues.up.sql
at HEAD, lines 32-50). No bd CLI path at HEAD writes `agent_state`,
`last_activity`, or `rig` on issues (verified: no references in
cmd/bd/swarm.go, issueops/claim.go, issueops/close.go, types.go issue
struct). They are reserved surface for the orchestration layer above
bd (Gas Town), which represents rigs and roles as identity beads:
migration 0053_repair_rig_wisps.up.sql calls them "rig identity
beads ... durable issue state: keep type=rig hidden from ready work."

Exceptions that ARE wired at HEAD:
- `closed_by_session`: written by every close
  (issueops/close.go:340, `closed_by_session = ?` with a session
  string parameter; types.go:54 comments it as the Claude Code
  session).
- `work_type`: validated claim semantics, not dead surface. types.go
  1083-1095 ("Decision 006"): `mutex` (one worker, exclusive,
  default) vs `open_competition` (many submit, buyer picks).
- `last_activity` exists separately as a molecule-level aggregate
  (types.go:1830 MoleculeLastActivity), not a per-issue write.

Implication: finding-006's "dormant at 1.1.2" was right and remains
true at HEAD for the issues-table columns; the liveness design moved
elsewhere (Q3) instead of populating them.

## Q2: rig semantics

Per-STORE, not per-worker, not per-claim:
- types.go:120: `PrefixOverride ... // Completely replace config
  prefix (for cross-rig creation)`: a rig is addressed by its issue
  prefix; creating "in another rig" means using that store's prefix.
- docs/cli-reference/gate.md: bead gates await
  `<rig>:<bead-id>` ("other-project:op-abc123"): rig = the other
  project.
- Migration 0053: rigs exist as durable identity beads (type=rig) in
  the store.
- The routes table (migration 0012_create_routes) maps prefix to
  path: which repository a bead lands in
  (docs/multi-agent/routing.md), a multi-repo routing concern.
- Nothing in config or CLI at HEAD sets an issues.rig value.

Machinery in flux, trending narrower: docs/workflows/gates.md states
cross-rig bead gates "cannot be checked because multi-rig routing was
removed; resolve these gates manually."

Consequence for _kos/ideas/rig-as-runtime-locus.md: the proposal to
carry runtime locus (orchestrator workspace, host, session, factory
instance) in the rig column collides with upstream's store-identity
semantics and with machinery upstream is actively reshaping. The
runtime-locus mapping remains valuable, but its carrier should be the
ACTOR string (structured, e.g. locus/name) or issue metadata, with
rig left to mean the store. Revise the idea accordingly.

## Q3: the liveness layer (leases, heartbeat, reclaim)

Shipped at HEAD, absent from any tested release:

- Migration 0054_add_lease_columns.up.sql ("Dead-worker recovery,
  Gas Station v1.1, wy-5r9j"): "A claim was previously permanent: a
  worker that died mid-task stranded its issue in_progress forever."
  Adds lease_expires_at, heartbeat_at, and row_lock, the last because
  "Dolt has no real row locking and merges concurrent writes
  cell-by-cell"; every mutating path rewrites row_lock so races
  become serialization conflicts that withRetryTx replays,
  "the difference between exactly-once and a lost close."
- Migration 0055_move_leases_to_table.up.sql moves leases OFF the
  versioned issues table into an ephemeral dolt_ignored `leases`
  table (issue_id, holder, granted_at, lease_expires_at,
  heartbeat_at): "every claim and every heartbeat was an issues-row
  UPDATE -> a Dolt commit. At fleet scale that coordination chatter
  was the dominant source of unbounded reachable history and of the
  constant write traffic that starves large catch-up merges." Claims
  mint exactly one commit (status/assignee, history-worthy);
  heartbeats mint none. "Leases are deliberately node-local:
  dolt_ignored tables do not replicate ... only enforceable on the
  replica that granted them. Cross-machine claim VISIBILITY still
  rides status/assignee on issues."
- issueops/lease.go: DefaultLeaseTTL = 5 minutes, per-claim override
  (WithLeaseTTL).
- cmd/bd/heartbeat.go: `bd heartbeat` refreshes lease_expires_at and
  stamps heartbeat_at; only the current owner may heartbeat.
- cmd/bd/reclaim.go: `bd reclaim` is the reaper: finds in_progress
  issues whose lease expired more than --older-than ago (grace window
  for GC pauses/clock skew), clears assignee, reverts to open,
  records a recovery event (types.go EventLeaseReclaimed). Upstream's
  own operating guidance: "Run it from a supervisor on a timer with a
  window of roughly 2x the claim TTL." Scope: "every stale lease THIS
  replica granted," with label/assignee filters that never widen.
- issueops/claim.go additionally ships `claim.pools` config: pool
  pseudo-assignees (example: "fable-crew") claimable by any actor
  through the same CAS, while issues assigned to a real actor keep
  anti-steal protection. A team-claim / name-pool primitive.

Heartbeat wisps (WispTypeHeartbeat, "liveness pings") coexist as an
ephemeral event type, but the lease table is the enforcement
mechanism.

Convergent validation worth naming: upstream hit the same walls
findings 003 through 005 derived. Claims serialize at a store
(row_lock exists because Dolt cell-merges); lease enforcement is
grant-node-local (working-copy topologies fragment it); fleet-scale
commit chatter starves merges (the throughput concern behind
aae-orc-8cfh6). The central write plane (callbook pattern 5) is the
topology on which this design works whole: one instance grants and
enforces every lease.

## Q4: dolt commit authorship

No actor-to-dolt-author plumbing found. Claims commit via
ClaimCommitMessage(issueID, actor) (message text carries the actor),
but no path surveyed passes an author to the Dolt commit
(issue_claimer.go, issue_operations.go, issue_operations_tx.go,
issueops/commit_pending.go: zero author references). Commits remain
authored as the server user (observed as `beads <beads@local>` in
finding-006). F6 candidate (k) stands; re-verify with one repo-wide
grep before filing (gh code search returns nothing for this repo, so
verification needs a quarantined clone via ae, or the GitHub UI).

## Q5: releases newer than 1.1.2

- v1.2.1 (2026-08-11): published BY ACCIDENT, untested; migrated
  schema v53 to v65; do not run it (a single run migrates the
  database and strands tested binaries behind a schema-mismatch
  error; docs/RECOVERY-1.2.1.md in the repo covers rollback).
- v1.2.2 (2026-08-15, Latest): recovery release. v1.1.2 code
  renumbered so every channel moves onto tested code. The 1.2.x
  features (work leases, events journal, sync federation, HTTP API
  server, provenance events) are NOT in it; they "will return in a
  properly tested future release." go.mod retracts v1.2.0/v1.2.1.
- Our fleet is on 1.1.2 (schema v53). Upgrading to v1.2.2 is safe and
  changes nothing functionally. Never install v1.2.1.
- Also visible at HEAD, returning later: an HTTP API server
  (internal/httpapi/), provenance events (migration 0063), an events
  journal (0064), storage classes (0060).

## Recommendations

(a) Liveness: ADOPT UPSTREAM, build nothing local. The lease +
heartbeat + reclaim design is complete at HEAD and matches the
claim-liveness idea's own smallest-probe shape. Callbook work now is
docs-level: write the supervisor reclaim timer (2x TTL) and heartbeat
cadence into pattern 5, note DefaultLeaseTTL=5m and per-claim
override, and gate fleet adoption on the next tested upstream release
(watch for the lease line's return; never 1.2.1). If a fleet pilot
needs leases sooner, that is a pinned-build decision to take
deliberately (charter F5 territory), not a default.

(b) rig: REVISE the idea. rig = store/project (prefix-scoped,
representable as a type=rig identity bead), and upstream is narrowing
multi-rig machinery. Carry runtime locus in the actor string or issue
metadata; leave the rig column to upstream's semantics. The
locus-mapping table in the idea survives with a different carrier.

(c) Upstream filings: DROP (j): answered by this survey (columns are
reserved surface; liveness intentionally lives in the leases table,
not those columns). KEEP (k) (actor into dolt commit authorship) as a
small enhancement ask, filed after one clone-side grep confirms no
existing surface, and best timed after the lease release lands so it
rides the same agent-attribution wave. New item worth tracking
instead of (j): `claim.pools` maps directly onto callbook B3 name
pools and team claims; evaluate adopting it in enrollment docs when
the feature reaches a tested release.

## Evidence index (all at github.com/gastownhall/beads, ref main)

- internal/storage/schema/migrations/0001_create_issues.up.sql
  (base-schema reserved columns)
- internal/storage/schema/migrations/0053_repair_rig_wisps.up.sql
  (rig identity beads)
- internal/storage/schema/migrations/0054_add_lease_columns.up.sql
  (lease rationale, row_lock)
- internal/storage/schema/migrations/0055_move_leases_to_table.up.sql
  (ephemeral leases table, fleet-scale chatter rationale)
- internal/storage/issueops/lease.go (DefaultLeaseTTL, WithLeaseTTL,
  freshRowLock)
- internal/storage/issueops/claim.go (CAS claim, claim.pools,
  anti-steal)
- internal/storage/issueops/close.go (closed_by_session write)
- internal/types/types.go (LeaseExpiresAt/HeartbeatAt/
  LeaseGrantedNode, WorkType Decision 006, EventLeaseReclaimed,
  WispTypeHeartbeat, MoleculeLastActivity, PrefixOverride cross-rig)
- cmd/bd/heartbeat.go, cmd/bd/reclaim.go (operator surface)
- docs/cli-reference/gate.md, docs/workflows/gates.md (cross-rig
  await grammar; multi-rig routing removed)
- docs/multi-agent/{index,coordination,routing}.md (assignee-string
  coordination model, routing = which repo)
- Releases: v1.2.1 caution, v1.2.2 recovery notes (2026-08-15)
