# Conflict-free versioned DB substrate landscape (2026 survey)

> Status: reference survey, 2026-08-15. Feeds finding-003 option C and
> question-cross-machine-write-topology. Web sweep across GitHub, GitLab,
> Codeberg, crates.io, and primary sources; URLs are checkable and dated
> where the project moved or pivoted. Direction, not a build decision.

## Why this survey exists

finding-003 named three ways to replace the pattern-4 default for
agent-fleet workloads. Option C was "build (or adopt) a substrate with
conflict-free multi-writer merge." This survey answers whether such a
substrate can be adopted off the shelf. The short answer: not one that
gives everything callbook needs at once, and knowing exactly which
property you give up is the useful result.

## The framing: three properties, largely disjoint

A ticket store for a distributed agent fleet wants three things. In the
2026 landscape they are delivered by different families, and no
off-the-shelf system delivers all three:

1. **Versioned / git-like**: branch, merge, diff, full retained history,
   time-travel.
2. **Conflict-free multi-writer**: concurrent writes from many machines
   converge automatically, no manual conflict resolution.
3. **Query interface**: SQL or graph, not just a document blob.

The load-bearing correction to the original question: a **prolly tree
gives conflict-free STRUCTURAL convergence** (same key-set produces the
same root hash regardless of write order, so sync/diff is cheap and
deterministic). That is not conflict-free SEMANTIC merge. Dolt uses
prolly trees and still produces conflicts because it does 3-way merge
with value conflicts. "Conflict-free" lives in the merge semantics
(CRDT), not the tree shape. So no prolly-tree database, by itself,
delivers property 2.

## What delivers which pair

| Family | Examples | 1 versioned | 2 conflict-free | 3 SQL/graph |
|---|---|:--:|:--:|:--:|
| Git-for-data (prolly tree) | Dolt, DoltgreSQL, Rust `prollytree`, Noms | yes | no (3-way, conflicts) | yes (SQL) / KV |
| RBSR / anti-entropy KV | iroh-docs, Willow/willow-rs, negentropy | no (latest-state) | yes (LWW/set-union) | no (KV) |
| Merkle-CRDT libraries | `merkle-search-tree`, `crdts::merkle_reg`, go-ds-crdt | causal DAG only | yes (with CRDT values) | no (KV/register) |
| CRDT-SQL | cr-sqlite | no (v1 latest-state) | yes | yes (SQL) |
| Document CRDT | Automerge, Loro, Yjs/yrs | yes (full history) | yes | no (document) |
| Versioned graph | TerminusDB, Fluree | yes | no (merge conflicts) | yes (graph) |

The only family that delivers 1 AND 2 together is the **document CRDTs**,
and every one of them lacks property 3. The only family that delivers
2 AND 3 together is **CRDT-SQL (cr-sqlite)**, which lacks property 1
today. Nothing delivers all three.

## Candidate shortlist for callbook option C, by priority

Rust unless noted. Pick by which property you refuse to give up.

- **Keep SQL + git history, accept partitioning (no new substrate).**
  Stay on Dolt and partition write authority (finding-003 option A). The
  survey reinforces this as the near-term answer: the "just swap the
  substrate" path has no clean landing that keeps all three properties.

- **Want genuinely conflict-free + full history, can drop SQL: Loro or
  Automerge.** Model a ticket as a CRDT map/document. Both converge
  conflict-free and retain full history with time-travel; Loro is
  explicitly version-control-framed (version DAG, git-style shallow
  snapshots), Automerge is the mature reference with hash-identified
  versions and `automerge-repo` for sync/storage. You build your own
  query/index layer or project to a read model. This is option C made
  concrete and the strongest "both properties" answer.
  - Loro: https://github.com/loro-dev/loro
  - Automerge: https://github.com/automerge/automerge ,
    https://github.com/automerge/automerge-repo

- **SQL is non-negotiable, can accept LWW (lose per-value history):
  cr-sqlite.** The one project that is SQL and conflict-free. v1
  converges to latest state and discards the losing write; the causal
  event log that would add history is v2/roadmap, unshipped. Watch it;
  do not depend on the history half yet.
  - https://github.com/vlcn-io/cr-sqlite

- **A KV LWW model suffices, want turnkey Rust P2P sync: iroh-docs.**
  Working multi-writer KV, BLAKE3 content addressing, per-author LWW
  registers, range-based set reconciliation, redb-backed. Keeps only
  latest state per (author,key). It is a secondary crate in the iroh
  org, so treat maintenance as steady-but-not-headline.
  - https://github.com/n0-computer/iroh-docs

- **Building a custom conflict-free core: `merkle-search-tree` (with
  CRDT values) or `crdts::merkle_reg`.** The former is the reference
  Rust MST (anti-entropy over a network, converges iff values are
  CRDTs); the latter is an in-process Merkle-DAG register where
  concurrent writes survive as multiple roots. Libraries, not databases.
  - https://github.com/domodwyer/merkle-search-tree
  - https://github.com/rust-crdt/rust-crdt (`crdts::merkle_reg`)

- **The "build it right" hybrid (option C, expensive).** RBSR for sync
  (negentropy or Willow) plus an append-only hash-keyed log for history
  plus CRDT value semantics. GuardianDB (OrbitDB-log-over-Willow, Rust,
  2026) is this pattern in the wild.
  - negentropy (Rust): https://github.com/rust-nostr/negentropy
  - Willow (active, Codeberg): https://codeberg.org/worm-blossom/willow_rs
  - GuardianDB: https://lib.rs/crates/guardian-db

## Traps worth naming

- **AT Protocol / Bluesky MST is single-writer by design.** One signing
  key per repository; divergence is a fork the key-holder resolves, not
  a CRDT merge. Citing Bluesky as proof that "MST gives multi-writer
  convergence" is a category error. Rust ports (atrium-repo,
  atproto-repo) inherit the single-writer model.
- **The Rust `prollytree` crate** (zhangfengcdt) does add git-like
  semantics, a KV + SQL-via-GlueSQL layer, and agent-memory features,
  but its merge is 3-way-with-resolvers, not CRDT, and it is a
  single-maintainer ~33-star project. Appealing surface, not a
  Dolt-scale substrate, and not conflict-free.
- **ElectricSQL, PowerSync, Turso/libSQL offline sync** are
  server-authoritative sync engines in 2026, not conflict-free P2P
  CRDT. ElectricSQL specifically pivoted to a read-path sync engine.

## Tie to callbook's own stack

This maps onto F26 (orc): Dolt gives git-like versioning but not
conflict-free multi-writer, which is exactly why concurrent
`bd dolt push` writes have been serialized by hand (the YubiKey pacing).
No SQL system in this survey removes that serialization while keeping
full history. The property callbook's option C wants (conflict-free SQL
convergence with retained history) exists today only at the
document-CRDT layer (Automerge/Loro, no SQL), or hypothetically in
cr-sqlite v2. Since bd is Dolt-coupled, adopting any conflict-free
substrate means a bd-successor store, not a bd config change. That cost
is why option A (partition on Dolt) remains the near-term recommendation
and option C is a deliberate, later fork.

## Sources

Prolly-tree family: Noms https://github.com/attic-labs/noms (archived
2021) · Dolt https://github.com/dolthub/dolt (storage
https://pkg.go.dev/github.com/dolthub/dolt/go/store/prolly/tree) ·
DoltgreSQL https://github.com/dolthub/doltgresql · prollytree
https://github.com/zhangfengcdt/prollytree · dialog-db
https://github.com/dialog-db/dialog-db · awesome-prolly-tree
https://github.com/2color/awesome-prolly-tree

Merkle Search Trees / Merkle-CRDT: Auvolat & Taïani 2019
https://inria.hal.science/hal-02303490 · merkle-search-tree
https://github.com/domodwyer/merkle-search-tree · rust-crdt
https://github.com/rust-crdt/rust-crdt · go-ds-crdt
https://github.com/ipfs/go-ds-crdt · Merkle-CRDTs paper
https://arxiv.org/abs/2004.00107 · Okra https://github.com/canvasxyz/okra
· Pijul https://nest.pijul.org/pijul/pijul · atproto repo spec
https://atproto.com/specs/repository · atrium https://github.com/atrium-rs/atrium

RBSR: Meyer 2022 https://arxiv.org/abs/2212.13567 · iroh-docs
https://github.com/n0-computer/iroh-docs · willow_rs
https://codeberg.org/worm-blossom/willow_rs · iroh-willow
https://github.com/n0-computer/iroh-willow · Earthstar
https://github.com/earthstar-project/earthstar · negentropy
https://github.com/rust-nostr/negentropy · Willow RBSR spec
https://willowprotocol.org/specs/rbsr/ · GuardianDB
https://lib.rs/crates/guardian-db

CRDT-SQL / versioned graph: cr-sqlite https://github.com/vlcn-io/cr-sqlite
· SQLSync https://github.com/orbitinghail/sqlsync · ElectricSQL
https://github.com/electric-sql/electric · Turso
https://github.com/tursodatabase/turso · Automerge
https://github.com/automerge/automerge · y-crdt
https://github.com/y-crdt/y-crdt · Loro https://github.com/loro-dev/loro
· TerminusDB https://github.com/terminusdb/terminusdb · Fluree
https://github.com/fluree/db
