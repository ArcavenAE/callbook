# finding-004: option A (partition) is struck by the product goal; the governing constraint is CALM, and the choice is coordinate-at-write vs CRDT, not substrate

Date: 2026-08-15
Status: verified (theory: CALM theorem, Hellerstein & Alvaro, CACM 2020;
applied to the callbook ticket workload)
Supersedes: finding-003's recommendation of option A. finding-003's
diagnosis (pattern 4's discipline model breaks for agent fleets) stands;
its remedy does not.

## What changed

finding-003 offered three replacements for the pattern-4 default and
recommended option A (partition write authority by machine/site). The
product goal rules option A out: the fundamental requirement is
massively distributed agents working on the SAME projects at the SAME
time. Partitioning write authority means a machine owns a disjoint bead
slice, which is precisely the thing the goal forbids. Option A is struck.

That leaves options B (central) and C (CRDT). This finding shows those
two are not arbitrary choices but the only two horns of a theorem, and
that the deciding input is not the substrate but the workload's
invariants.

## The governing constraint: CALM

CALM (Consistency As Logical Monotonicity; Hellerstein & Alvaro,
"Keeping CALM: When Distributed Consistency Is Easy," CACM 2020): a
distributed computation has a coordination-free, consistent
implementation if and only if it is monotonic. Monotonic operations only
ever add facts and never retract them (append a comment, create a bead,
accumulate state). The moment a workload needs a non-monotonic invariant
enforced globally and immediately, coordination is provably required.

Non-monotonic invariants a task tracker might want:
  - global uniqueness (a slug or human id unique at creation)
  - "at most one active claim per bead"
  - referential integrity across the bead set ("cannot close while
    children are open")
  - any check a later concurrent write can invalidate

No substrate escapes this. Not a prolly tree, not a CRDT, not Dolt. It
is a theorem about coordination, not a gap in the tooling. A better
storage engine cannot deliver coordination-free enforcement of a
non-monotonic invariant, because none can.

## The reframe this forces on callbook's own docs

callbook's pattern-4 convention "one active editor per bead, claim
before editing" was never a convention. It was a hidden coordination
protocol standing in for exactly the non-monotonic invariant (at most
one active editor) that CALM says cannot be had coordination-free. The
discipline was doing the coordination by hand. That is why it does not
scale to autonomous agents: the coordination requirement is real; only
its manual implementation was optional.

## The two horns

Horn 1: coordinate at write time. Any agent writes any bead; the store
linearizes concurrent writes and enforces invariants. "Massively
distributed agents on the same project" becomes massively distributed
CLIENTS of one logical store, which is what every large multi-user
service is. The store may itself be geo-distributed with strong
consistency (CockroachDB, YugabyteDB, Spanner, FoundationDB): every node
accepts every write to every row, the database coordinates internally
via consensus, and the application never partitions authority. Keeps
SQL, invariants, bd-shaped semantics. Cost: writes pay consensus /
round-trip latency, and it is not offline-tolerant. Contradicts the
stated local-first, offline priority; take it only if that priority is
negotiable.

Horn 2: give up enforced invariants and go CRDT. Every machine holds a
local writable replica, works offline, syncs, converges with no
coordination and no manual merge. The price is exactly what CALM
predicts: no enforced global invariants. Concurrent same-field edits
converge by rule (last-writer-wins silently supersedes one, or
multi-value keeps both for the application to reconcile); uniqueness and
referential integrity are not enforced across replicas; "exactly one
claim" is not enforceable. For a task tracker this is frequently
acceptable: beads are mostly additive, hash ids never collide, comments
are grow-only and never conflict, and simultaneous same-field writes are
rare and last-writer-wins-tolerable. Coordination-free substrates:
  - Document CRDT: Loro or Automerge (Rust). Keeps full history and
    time-travel, conflict-free. No SQL; model a bead as a CRDT map and
    build a query/read projection.
  - CRDT-SQL: cr-sqlite. SQL syntax over last-writer-wins-merged rows.
    Same CALM limits (no cross-replica constraints, latest state only,
    no value history), but relational queries are kept. The CRDT horn
    wearing a SQL face.

Both horns are a bd-successor store: bd is Dolt-coupled, and Dolt
implements horn-1 semantics (invariant-enforcing, conflict-on-divergence).

## The hybrid, and the deciding question

The horns are not all-or-nothing. The clean design when a few invariants
are genuinely required is: CRDT for the monotonic majority, plus a small
coordination primitive (a lock/lease service, a consensus quorum, or a
single authority) for only the non-monotonic operations. The whole
system does not pay coordination cost, only the operations that provably
require it. CALM is also the tool that tells you which operations those
are.

So the decision does not turn on the substrate. It turns on one
inventory: which bead operations must enforce an invariant globally and
immediately across all agents, versus which can converge after the fact.

  - If the answer is "almost none; agents append, comment, and update
    fields, and last-writer-wins on a rare same-field collision is
    acceptable," then Horn 2 (CRDT) is the answer, the massively
    distributed same-project dream is real and buildable, and
    Loro/Automerge or cr-sqlite is the store.
  - If the answer includes a hard invariant (unique id at creation, at
    most one claim, no-close-with-open-children), those specific
    operations need Horn 1 coordination, and the hybrid is the shape:
    CRDT plus a coordination sidecar for just those checks.

Producing that invariant inventory is the next action. It decides horn,
substrate, and whether a coordination sidecar is needed at all.

## Cross-references

- finding-003 (the pattern-4 break and the three original options).
- _kos/ideas/conflict-free-versioned-db-substrate-landscape.md (the
  substrate survey; both horn-2 substrates are catalogued there).
- question-cross-machine-write-topology (frontier node; updated to
  strike option A and carry the CALM framing).
- CALM: Hellerstein & Alvaro, "Keeping CALM: When Distributed
  Consistency Is Easy," Communications of the ACM 63(9), 2020,
  https://cacm.acm.org/research/keeping-calm/ (arXiv:1901.01930).
- Ties to orc F26: Dolt is horn-1; this is why concurrent bd dolt push
  has been serialized by hand.
