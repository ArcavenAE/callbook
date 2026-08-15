# finding-003: rapid agent-fleet multi-writer breaks the working-copy sync default (pattern 4); write authority must be partitioned or centralized

Date: 2026-08-15
Status: verified (against callbook's own measured claims in
docs/patterns.md and docs/runbooks/sync-conflicts.md, plus the dolt
replication model on Dolt 2.2.3)
Qualifies: docs/patterns.md §4 ("the pattern a distributed agent+human
team should reach for first"), docs/growth-path.md Step 3, and the
"Distributed team ... → 4. Working copies with a hub" row of the
Choosing table. None are wrong; all three assume a coordination regime
this workload does not have.

## The workload that forces this

The target deployment is: many autonomous agents writing to bd/dolt
concurrently on each of several machines; any agent may need the latest
state of any ticket; changes must propagate fast. Local propagation
(agents on the same machine seeing each other's writes) is the priority
and must be immediate; cross-machine propagation is secondary but still
wanted within a few minutes.

The load is machine-speed and unpartitioned at the bead level: agents
read the shared ticket queue and mutate whatever their work touches
(status, assignee, dependencies, close), on more than one machine at
once.

## What does NOT change: the local layer is already right

Pattern 2 (shared local server) answers the local half completely and
needs no change. One `dolt sql-server` per machine, every local agent a
SQL client of it, is a real ACID transactional server: many concurrent
connections, read-after-write consistency, every local write visible to
every other local agent on its next transaction, with zero sync
machinery. This is the measured Phase-0 shape.

One thing to hold firm: the granularity is one server per machine, not
one store per agent. The instinct to give each agent its own local
store is the wrong turn; it converts a solved concurrency problem
(shared transactional server) into an unsolved replication problem (N
stores per machine to reconcile). Keep agents as clients of a single
per-machine server.

## Why pattern 4 breaks for this workload

Pattern 4 (working copies + hub, git-like push/pull) is presented as
the first choice for a distributed team. Its correctness rests on a
coordination assumption that callbook already states plainly and that
this workload removes.

callbook's own measurements, from docs/patterns.md §4 and the
sync-conflicts runbook:

1. "Editing the SAME bead from two machines conflicts almost always,
   even on different fields, because both writes touch the row's
   `updated_at` cell." So the conflict surface is not "same field
   edited twice"; it is "same bead touched on two machines inside one
   sync window." At agent speed with a 30-to-60-second pull timer, that
   window is wide and the collision surface is large.

2. There is no automatic resolver. The recovery is a three-statement
   raw-dolt runbook, explicitly "the one sanctioned exception to never
   run raw dolt against a bd-managed store," because "no `bd dolt
   resolve` exists yet" and `bd doctor --fix` is unavailable in
   embedded mode. A human, or a hand-written script, resolves each
   collision.

3. The convention that keeps conflicts rare is a human-pace social
   protocol: "One active editor per bead. Claim it (assignee) before
   editing." And the escalation is explicit: "If this happens weekly
   ... you have a convention problem: two roles are sharing beads they
   should be splitting."

The workload violates the assumption directly. Claim-before-edit cannot
be enforced across many autonomous agents on multiple machines editing
a shared queue; the agents are precisely the "two roles sharing beads"
case, except it happens continuously rather than weekly, and there is
no role split to make because every agent can touch every ticket. The
"boring, run the runbook" resolution path becomes a continuous manual
tax that no fleet can carry.

## The mechanism, stated once

This is not a bd bug awaiting a patch. It is dolt's replication model.
Cross-machine sync is git-style push/pull: the pull is fast-forward, and
two machines writing the same branch diverge. dolt has no automatic
multi-master convergence in the replication path, and bd ships no
dolt-aware merge driver. The `updated_at`-cell collision makes even
non-overlapping field edits to one bead conflict. Multi-master
"any agent writes any bead on any machine and it converges" is the one
shape the transport does not provide.

dolt's cluster mode does not rescue this either: it is primary plus warm
standby for HA, and standbys reject writes. It is single-writer with
failover, not multi-active-writer. callbook's dolt-service.md already
builds on exactly this (primary + warm standby, "users and grants do not
replicate ... standbys reject writes").

## The fork: three replacement topologies

For an unpartitioned agent-fleet workload, pattern 4 as the default must
be replaced by one of:

A. Partition write authority by machine or site. Each machine is the
   sole writer of a disjoint slice of beads (by project label, by
   id-prefix, by assignment). Every machine read-replicates the others'
   slices, so any agent still sees the latest of all tickets. Because no
   two machines ever write the same bead, cross-machine merges are always
   clean fast-forwards of disjoint histories, and the conflict class in
   pattern 4 disappears. This preserves local-first authority, immediate
   local propagation, and few-minute cross-machine freshness at once. It
   maps onto grain callbook already has: bead project membership is
   carried by labels, and pattern 6 (the tiered pipeline) is already a
   store-per-domain design. The partition axis is a second application of
   the same instinct: a store, or a write-authority domain, per machine
   or site.

B. Central hub, thin clients (pattern 3), no local write authority. One
   server is the single source of truth; every agent everywhere is a
   direct SQL client; ACID handles all concurrency; there is no merge
   problem because there is one copy. The cost is that every write is a
   network hop and there is no local authority or offline mode. This
   contradicts the stated priority (local propagation first), and is
   correct only if the network to the hub is fast enough that "local"
   and "hub" latency converge and offline is not required.

C. Build a bd-aware automatic reconciliation layer. Last-writer-wins on
   `updated_at`, or field-level CRDT semantics on the bead row, so true
   multi-master converges without human resolution. This is the only
   path that makes the unrestricted "any agent, any bead, any machine"
   model work as written. It does not exist in bd or dolt today; it is
   upstream-scale engineering, not a config change, and it is the honest
   name for what pattern 4 silently assumes.

The position pattern 4 currently occupies (local write authority to a
shared bead namespace, git-like sync, coordination by human discipline)
is the one point in the space that cannot survive rapid autonomous
multi-writer. It is stable for human-pace teams with partitionable work,
which is the deployment callbook measured it on, and the docs should say
so rather than recommend it first for agent fleets.

## Recommendation

- Keep pattern 2 as the local layer, unchanged, one server per machine.
- Change the cross-machine default for agent-fleet workloads from
  pattern 4 to option A (partitioned write authority). Frame it as an
  extension of pattern 6's store-per-domain instinct onto the
  write-authority axis, not as a repudiation of the growth path.
- Reserve pattern 4 for human-pace, partitionable-work teams, and label
  its validity domain explicitly in patterns.md and growth-path.md.
- Name option C (a bd-aware merge/CRDT layer) as the only route to true
  unrestricted multi-master, and file the capability gap upstream under
  charter F6 rather than implying pattern 4 already covers it.

## To measure before building any of this

dolt commits serialize at write time; dolt is git-modeled, not a
high-write-throughput OLTP engine. The pattern-4 numbers in patterns.md
(push 0.32 s, pull 0.46 s) measure sync latency, not local write
contention throughput under many rapid agents. Before locking a topology,
probe local write throughput at the expected agent count and write rate
against a single per-machine server. bd's `--dolt-auto-commit batch`
mode is the first knob. If the local server bottlenecks on write
contention, that changes the answer independently of the cross-machine
question.

## Harvest implications

- New frontier node: question-cross-machine-write-topology (this repo).
  It reopens the cross-machine topology decision that growth-path Step 3
  and patterns.md §4 presented as settled.
- docs/patterns.md §4 and docs/growth-path.md Step 3 need a validity-domain
  caveat (human-pace, partitionable work) added at their heads. Left for a
  harvest pass so the direction rewrite is deliberate, not silent.
- charter F6 should gain the multi-master reconciliation gap (option C) as
  a named upstream ask alongside the existing federation-credential and
  probe-before-create items.

## Cross-references

- docs/patterns.md §2, §4, §6; docs/growth-path.md Steps 1-4;
  docs/runbooks/sync-conflicts.md; docs/design/dolt-service.md
  (cluster mode = single-writer + standby).
- orc F26 (bd on a Dolt server) and finding-044 (project membership is
  carried by labels, not by partitioning the store) in aae-orc/_kos.
- Upstream: bd has no `bd dolt resolve` / no embedded-mode merge driver
  (sync-conflicts runbook); track option C under charter F6.
