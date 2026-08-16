# finding-005: multi-agent multi-author is the identity plane, not the topology; the model is already designed (B3) and half-shipped in bd 1.1.2, and nothing in this deployment wires it

Date: 2026-08-16
Status: verified (live probes against the Phase-0 server, bd 1.1.2,
Dolt 2.2.3; reconciliation against callbook B3, the claim-liveness
idea, and orc finding-123)
Refines: finding-004 (supplies the first confirmed member of its
invariant inventory). Answers the operator requirement of 2026-08-16:
"agents or groups of agents need their own identity in dolt; they need
to claim work; today all identities resolve back to me, and that is
dead wrong."

## The conflation this finding removes

Three separable planes have been riding on the phrase "central write":

1. **Topology**: where writes land (one store per project vs replicated
   working copies).
2. **Authorship**: who is writing (one principal today vs a principal
   per agent, team, and human).
3. **Coordination**: claim exclusivity and liveness (who holds this
   bead, are they alive, who do I ask).

The operator's non-negotiable ("multi-agent, multi-author") lives on
planes 2 and 3. Today's deployment is BOTH central AND mono-identity.
The dead-wrong part is the mono-identity, and it is fixable with zero
change to topology. Nothing about many authors requires many write
masters: bd's own claim primitive is designed as many authors against
one shared store, and its exclusivity depends on that store being one
place.

## Probe results (2026-08-16, kinu, aae_orc database)

1. **Identity is erased at the dolt layer too.** Every commit in
   `dolt_log` is authored `beads <beads@local>`, the shared server
   account. Not even the human principal survives into dolt history;
   attribution today is one shared service identity for all writers.

2. **bd's claim is atomic and actor-addressed.** `bd update --claim`:
   "Atomically claim the issue (sets assignee to you, status to
   in_progress; idempotent if already claimed by you)." The "you" is
   the actor resolution chain (`--actor` flag, `$BEADS_ACTOR`, git
   user.name, `$USER`). Two consequences: (a) with a per-agent actor
   set, claims become attributable today with no schema change; (b)
   claim exclusivity is enforced by the transactional store. Atomic
   compare-and-set exists because there is one server to be atomic
   against.

3. **bd 1.1.2's schema already carries an agent identity and liveness
   surface, and this deployment uses none of it.** The issues table
   includes: `actor`, `agent_state`, `last_activity`, `role_bead`,
   `hook_bead`, `role_type`, `rig`, `work_type` (default `'mutex'`),
   `closed_by_session`, `sender`, plus gate/await machinery
   (`await_type`, `await_id`, `timeout_ns`, `waiters`). Measured across
   all 1133 issues: `actor`, `agent_state`, `last_activity`,
   `role_bead`, `rig`, `closed_by_session` are empty on every row, and
   `work_type` is unset on every row. The columns shipped; nothing
   here drives them.

4. **bd 1.1.2 ships agent-coordination subcommands**: `bd gate`
   ("async coordination gates"), `bd merge-slot` ("merge-slot gates
   for serialized conflict resolution"), `bd swarm` ("swarm management
   for structured epics"), `bd mol` (work templates). Upstream is
   visibly building multi-agent coordination primitives, including a
   serialization primitive, inside bd itself.

Implication of 3+4: the July-era analyses (the claim-liveness idea's
"not available: per-actor identity, lease semantics" list, and parts
of orc finding-123) are stale against 1.1.2. A re-survey of bd's
agent-native surface is warranted before designing any lease
convention: upstream may already carry part of it (`agent_state` +
`last_activity` look like exactly the liveness fields, and swarm/gate
may already populate them).

## The design already on the books

Nothing in the requirement is greenfield:

- **callbook B3 (bedrock) is the actor model**: humans as actors under
  their own handles; each person's agents draw durable names from a
  recorded name pool (`BEADS_ACTOR`); `node_id` per store; long-lived
  service agents get individually revocable named accounts; three
  account tiers per project. Design value 2 makes names the durable
  identity, and charter F4 is the staged path by which actor names
  later become authenticated token subjects (short-TTL minting, then a
  token-verifying gateway). Authentication is roadmapped; attribution
  is available now.
- **The claim-liveness idea** (this repo,
  `_kos/ideas/claim-liveness-and-agent-reachability.md`) already
  separates attribution / reachability / liveness, binds the address
  to the claim rather than to any orchestrator (marvel is enrichment,
  never prerequisite, per SOUL §2), and names the passive lease as the
  smallest probe with escalation staying a human act (ADR-007).
- **orc finding-123** (survey under `aae-orc-mq76`) already picked the
  attribution mechanism: derive from the harness, do not ask; on
  Claude Code the agent cannot self-derive identity, so THE SPAWNER
  STAMPS IT. It also measured the failure shape now reconfirmed here:
  bd's events table carried an `actor` column on all 5,598 rows while
  nothing ever set the variable. The gap was an unused field then, and
  it is a larger set of unused fields now.

## The three operator failures, mapped

| Failure | Plane | Mechanism | Status |
|---|---|---|---|
| "Agents don't know which of them has pulled the work" | attribution | spawner stamps `BEADS_ACTOR` with a pool name; `--claim` then writes an attributable assignee | available today; wiring absent |
| "Which stopped working on it" | liveness | `agent_state`/`last_activity` if bd populates them (re-survey), else lease-as-note + checker per the idea file; sweeper proposes, human releases | partially shipped upstream (verify); convention fallback ready |
| "Who to check with if the work didn't get done" | reachability | address on the claim (idea file shape 2); when marvel manages the agent, its directory enriches the answer; team claims name the team, so the contact is the team's supervisor | designed; not built |

Granularity per B3: session-ephemeral agents are pool names (attribution
tier); teams and long-lived service agents are individually revocable
named accounts (authentication tier); humans are handles. "Groups of
agents need their own identity" is the team account plus a team actor
name, and a team-held claim makes the supervisor the check-with contact.

## What is actually missing: deployment wiring

1. **Stamp the actor at every spawn point.** Marvel runtime adapters,
   workflow fan-outs, cron/scheduled runs, and interactive sessions
   (client-env) each set `BEADS_ACTOR` to a pool name before any bd
   write. Per finding-123, the spawner stamps; agents do not
   self-report. This one change makes claims attributable fleet-wide.
2. **Re-survey bd 1.1.2's agent surface** (`agent_state`,
   `last_activity`, `work_type`, `role_bead`, `rig`, swarm/gate/
   merge-slot) before building any local lease convention; adopt
   upstream's machinery where it already works, file the gaps under
   charter F6 where it does not.
3. **Lease/liveness increment** if the re-survey finds the columns
   dormant even upstream: TTL note on claim + checker that reports
   expiry (report, never auto-unclaim), per the idea file's smallest
   probe.
4. **Account tiers on the write plane** per B3: named revocable
   accounts for teams and service agents, so the dolt layer stops
   authenticating everyone as one shared user.
5. **Dolt commit attribution** (candidate upstream ask): plumb the bd
   actor into dolt commit authorship so `dolt_log`/blame stop reading
   `beads@local` for every writer. Hedged: verify whether bd already
   exposes this before filing.

## Consequence for the topology question

At-most-one-claim is the first confirmed member of finding-004's
invariant inventory, and it is confirmed from inside bd's own design:
`--claim` is atomic against the shared store. Whatever the eventual
read topology (edge replicas for dashboards, history tooling, DR), the
CLAIM PATH runs through a coordinated store, or exclusivity is lost in
sync windows and two agents own one bead at machine speed. Multi-author
is fully satisfied on either topology; exclusive claims forbid
uncoordinated multi-master. Identity does not decide the topology
question, but the claim primitive narrows it: the coordination point
exists in every workable answer.

## Cross-references

- callbook: charter B3, design value 2, F4 (auth phases), F6 (upstream
  asks), `_kos/ideas/claim-liveness-and-agent-reachability.md`,
  finding-004 (invariant inventory), finding-003 (pattern-4 break).
- orc: finding-123 (harness-invocation identity survey; spawner
  stamps), `question-harness-invocation-agent-identity`,
  `question-agent-service-directory` (marvel directory as enrichment),
  `aae-orc-mq76`.
- bd upstream: 1.1.2 schema + gate/merge-slot/swarm/mol subcommands
  (probe of 2026-08-16); re-survey before filing.
