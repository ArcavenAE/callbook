# finding-006: bd 1.1.2 agent-surface re-survey; attribution works today via one env var, liveness columns are dormant, and upstream is building the multi-agent layer under our feet

Date: 2026-08-16
Status: verified (live probes against the Phase-0 server, bd 1.1.2
Homebrew, aae_orc database; ephemeral probe wisps used and closed, no
JSONL export pollution)
Executes: the re-survey called for by finding-005 item 2. Operator
authorized 2026-08-16.

## Headline empirics

Probe: three `--ephemeral` wisps created with
`BEADS_ACTOR="probe/kinu/agent-surface-resurvey"` exported, one claimed,
all three closed with reasons.

1. **Attribution works today.** With the actor stamped, `bd create`
   wrote the actor into `created_by`, and `bd update --claim` wrote it
   into `assignee` (verified on `aae-orc-wisp-w04`: assignee =
   `probe/kinu/agent-surface-resurvey`, status in_progress). The whole
   "every identity resolves to the human" defect reduces to exporting
   one environment variable at each spawn point. No schema change, no
   upstream ask, no new tooling.
2. **The liveness columns are dormant at 1.1.2.** Even with the actor
   stamped, `actor`, `agent_state`, `last_activity`, `rig`, and
   `closed_by_session` stayed empty through create, claim, and close.
   The columns shipped ahead of the CLI paths that populate them (or
   those paths live in tooling above bd).
3. **Wisps are a parallel store.** Ephemeral issues live in their own
   table family (`wisps`, `wisp_comments`, `wisp_dependencies`,
   `wisp_events`, `wisp_labels`) with their own id namespace
   (`aae-orc-wisp-*`), and are excluded from JSONL export. The
   ephemeral plane is structural, not a flag.

## Upstream machinery discovered (1.1.2 surface)

The July-era analyses (claim-liveness idea's "not available" list,
parts of orc finding-123) are stale. bd 1.1.2 already ships:

- **rig as the installation unit.** `bd gate`'s bead type awaits on
  `<rig>:<bead-id>` ("waits for cross-rig bead to close");
  `bd merge-slot` docs state "each rig has one merge slot bead."
  Upstream's own vocabulary treats a rig as a deployment/store
  instance with cross-rig addressing. No 1.1.2 config key or flag
  sets rig; the column and the address format shipped ahead of the
  assignment surface.
- **Gates**: async wait conditions blocking workflow steps; types
  human, timer, gh:run, gh:pr, bead (cross-rig). `bd gate
  add-waiter/check/create/discover/list`.
- **merge-slot**: an exclusive-access primitive per rig
  (status=in_progress means held; `metadata.holder` names the holder;
  `metadata.waiters` is a priority queue). Upstream's own serialized
  coordination point, aligned with finding-004's CALM analysis.
- **swarm**: parallel work coordination over an epic's dependency DAG.
- **mol/formula**: work templates (protos) instantiated as persistent
  molecules (`pour`) or ephemeral wisps (`wisp`), plus bond/squash/
  burn/distill.
- **Wisp types include `heartbeat` and `ping`**: the liveness layer is
  designed as ephemeral heartbeat beads, exactly the lease shape the
  claim-liveness idea proposed as its smallest probe.
- **Event beads**: `bd create --type=event` with `--event-category`
  (examples given upstream: `patrol.muted`, `agent.started`) and
  `--event-actor` documented as an "Entity URI", implying an upstream
  actor-addressing scheme.
- **Agent beads**: `--no-history` is documented "for permanent agent
  beads"; agents themselves are representable as beads.
- **bd audit**: append-only `.beads/interactions.jsonl` for "why did
  the agent do that" and dataset generation. **bd onboard**: agent
  instructions snippet. **bd context**: effective identity, including
  a `role:` field (contributor/maintainer, GH#2950 warning class).
- **routes table**: `prefix -> path` mapping (empty locally),
  presumably how cross-rig references resolve.

Reading: upstream bd is becoming the substrate of a multi-agent
orchestration stack, with rigs, agent beads, heartbeat wisps, gates,
and an exclusive-slot primitive. callbook should ride this trajectory,
not parallel-build it.

## Consequences for the finding-005 wiring list

1. Item 1 (stamp `BEADS_ACTOR` at every spawn point) is CONFIRMED
   CHEAP and sufficient for attribution. Do it first.
2. Item 3 (local lease convention) should NOT be built yet. The
   heartbeat/ping wisp types and agent_state/last_activity columns
   say upstream has the design; the 1.1.2 CLI just does not populate
   them. Follow-up: survey newer bd releases and HEAD for what drives
   `agent_state`/`last_activity`/`rig` before building anything local;
   file an upstream ask (charter F6 pattern) only if HEAD still lacks
   it.
3. Item 5 (dolt commit authorship) stands: all dolt commits remain
   `beads <beads@local>` regardless of actor stamping.
4. rig is unset by any 1.1.2 surface, so a deployment convention can
   occupy it today, provided it stays compatible with upstream's
   cross-rig addressing (`<rig>:<bead-id>` and the routes table).
   The proposal is captured in
   `_kos/ideas/rig-as-runtime-locus.md`.

## Probe hygiene note

The `beads.role not configured (GH#2950)` warning fired on every write
(known instance, captured in orc finding-036's class; not re-silenced
here). It prints ahead of `--json` output on the same stream, which
broke id parsing in the first scripted attempt; scripts consuming
`bd --json` should strip leading non-JSON lines or set the role config.

## Cross-references

- finding-005 (the wiring list this executes), finding-004 (CALM;
  merge-slot is upstream's own coordination-point admission),
  `_kos/ideas/claim-liveness-and-agent-reachability.md` (lease shape,
  now superseded in mechanism by upstream heartbeat wisps pending the
  HEAD survey), `_kos/ideas/rig-as-runtime-locus.md`.
- orc finding-123 (spawner stamps; events.actor dormant), charter B3
  (actor model), F6 (upstream-ask pattern).
