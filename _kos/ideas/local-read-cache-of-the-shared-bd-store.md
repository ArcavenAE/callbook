# A local read cache of the shared bd store, with writes to the global server

*Operator idea, 2026-11-02. Pre-hypothesis. No probe and no design: this file
records the shape of the idea and what stays open.*

## The idea

Run a read cache of the shared bd store inside each cluster, for marvel seats.
Reads (`bd ready`, `bd show`, search) are served from the local copy, so a
seat does not cross the network, or depend on the global server being up, to
look at its work. Writes (claim, update, close) still go to the one global
read-write server, which stays the single place the store changes. A regular
sync keeps the local copy close to the global one.

The operator's words: "a local cache to marvel, while using global read-write,
and some regular sync". The same note also asks for bd to be integrated more
directly in director and used more opinionatedly for agent task tracking; that
is a separate thread and not part of this file.

## Why it comes up

Today every read and every write from a seat goes to one server. Two things
follow, both worth naming before designing anything: a read is a network call
whose latency and availability belong to the global server, and a seat that
only wants to look at the queue carries the same dependency as one that is
changing it. Splitting reads from writes lets the cheap, frequent operation
stay local and leaves the rare, authoritative one global.

## What already exists, as context

Not restated here; each is a place to start when the idea becomes a probe.

- Dolt can serve read-only: `dolt sql-server` accepts `--readonly` (and the
  `behavior.read_only` setting). Dolt documents cluster replication with
  read-only standbys, and remote-based read replicas that pull from a remote
  on read (dolthub.com docs, sql-reference/server/replication).
- bd 1.1.2 has a `--readonly` flag that blocks write operations, described in
  its own help as meant for worker sandboxes.

So both layers already have a notion of "this client or server may not write".
What nobody has settled is how a cache behaves when it lags or when the write
path is gone.

## Related ideas

- `conflict-free-versioned-db-substrate-landscape.md`: what each store family
  gives up between versioning, multi-writer convergence and queries. A read
  cache sits on the single-writer side of that trade, and says nothing about
  convergence of multiple writers.
- `claim-liveness-and-agent-reachability.md`: a claim is a write that other
  seats read to decide what is free. How stale a read may be before a seat
  acts on a claim that has already lapsed is the same question seen from the
  claim side.

## Open

These are the points the idea does not answer. None is decided here.

1. **Lag tolerance.** How far behind may a cache be before a read misleads?
   The answer probably differs by operation: browsing a queue tolerates more
   than deciding that nobody holds a claim.
2. **A write when the global server is unreachable.** Fail the write, queue it
   locally and replay it, or let the seat proceed and reconcile later? Each
   has a different effect on two seats that claim the same item while apart.
3. **How a seat knows its cache is stale.** Whether the cache carries an age or
   a version a seat can read, and whether a seat can ask for a fresh read when
   the age matters.
