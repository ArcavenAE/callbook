# rig as runtime locus: one column, one mapping per runtime kind

*Operator proposal, 2026-08-16. Pre-hypothesis. Captured during the
finding-006 re-survey; the empirical grounding is there.*

> REVISED same day by finding-007: upstream rig means a STORE (a
> project database identified by its issue prefix, representable as a
> type=rig identity bead), and upstream is narrowing its multi-rig
> machinery. The rig COLUMN is therefore not the carrier. The mapping
> table below survives with a new carrier: the runtime locus rides
> the ACTOR string (locus/name grammar; the live client-env default
> and marvel's baseEnv stamping already do this) or issue metadata.
> This file stays as the generative record; finding-007 section Q2
> carries the evidence.

## The proposal

Use bd's `rig` column as the RUNTIME LOCUS of the acting agent: which
installation/fleet/environment the actor runs in. Pair it with the
actor (who) so the two columns compose the identity layers from orc
finding-123: human principal and fleet land in rig; harness invocation,
agent, and session land in the actor name.

Known mappings, one per runtime kind, with surrogates where no natural
id exists:

| Runtime kind | rig value shape (candidate) |
|---|---|
| marvel-managed agent | marvel_id + workspace (e.g. `marvel:<cluster>/<workspace>`) |
| human interactive session | human + directory runtime (e.g. `mp@<host>:<repo>`) |
| bare harness session (Claude Code, Codex, cron) | session surrogate (host + session id) |
| vsdd-factory run | factory instance + (second component, OPEN) |

## Why this fits upstream rather than fighting it

finding-006 confirmed rig is upstream's own installation unit:
cross-rig bead gates await on `<rig>:<bead-id>`, each rig carries one
merge-slot bead, and a `routes` table maps prefix to path. Nothing in
1.1.2 sets the column, so a deployment convention can occupy it today.

Constraint that follows: rig values should remain legal in upstream's
cross-rig address grammar (they appear left of `:` in await ids), and
should stay stable enough to route on. Whatever surrogate scheme we
pick, `<rig>:<bead-id>` must stay parseable and routable.

## Open questions

- Is rig per-bead (where the bead was born) or per-claim (where the
  current worker runs)? Upstream intent unknown; the merge-slot and
  gate usage suggest per-store/per-deployment, which argues for
  "where the claim's worker runs" being carried on the claim or the
  actor instead, and rig staying coarse. Needs the HEAD survey
  (finding-006 follow-up) before committing.
- The vsdd-factory second component: run id? workload id? epoch?
- Character set and length discipline for surrogates so values stay
  address-grammar-safe.
- Does the routes table expect rig prefixes to resolve to paths we
  control (i.e., should every rig value we mint have a route entry)?

## Cross-references

- finding-006 (empirical grounding; rig unset by any 1.1.2 surface).
- finding-005 (identity plane; B3 actor model).
- orc finding-123 (five identity layers; spawner stamps).
- orc `question-agent-service-directory` (marvel directory as the
  rig-to-reachability join, enrichment not prerequisite).
