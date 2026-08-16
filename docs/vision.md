# Vision: humans and agents on one call book

> How a distributed team (humans and AI agents together) shares a single
> work tracker without pretending the agents are people or treating them
> as disposable tooling.

## The problem

Agent teams break conventional trackers in four ways:

1. **Volume and ephemerality.** A person may run five agents today and
   forty tomorrow; sessions are killed freely. Per-seat SaaS licensing and
   manual account lifecycle don't survive contact with that.
2. **Attribution.** When an agent closes a task, "who did the work" must
   be recorded durably (for trust, for review, for learning which agents
   are good at what), even when the agent itself lived for twenty minutes.
3. **Locality.** Agents run where the work is: laptops, CI, ephemeral
   sandboxes, air-gapped environments. A tracker that requires a live
   connection for READING excludes half the fleet; reads and solo
   work must stay local-first. Writes are a different matter: see the
   claims principle below.
4. **Coordination.** Autonomous agents claim work. A claim must be
   exclusive (two agents must never both own one bead), visible
   fleet-wide the moment it lands, and attributable to the claimant.
   Human teams hold that invariant by convention; fleets need it
   enforced.

beads (`bd`) answers the data model: issues as versioned rows in Dolt,
git-like branch/diff/merge semantics, a local-first daemon, JSONL
projections for git-tracked visibility. callbook answers the rest: how
identities enroll, how instances connect, and how the whole thing deploys.

## Design principle: names are the durable identity

The identity industry today treats agent identity as a governance label on
top of shared credentials: actors are declarative strings, ephemeral
workers draw names from a pool, and nothing binds "who did the work" to
"who may connect." We adopt that layer because it works today, and we
record the position that it is a stopgap. **First-class identity for
agents (authenticated principals, not honor-system labels) is the way of
the future.**

Every callbook pattern is shaped so that when the ecosystem catches up,
migration is a re-pointing, not a re-architecture:

- **Actor names are chosen once and become token subjects later.** The
  *names* are the durable identity; only their proof changes.
- **Enrollment always terminates in a per-identity artifact**: a policy
  attachment, a named SQL account, or (later) a minted token, never in
  copying a shared secret by hand.
- **The convergence point is the credential-command contract bd already
  ships** (`BEADS_DOLT_CREDENTIAL_COMMAND`, token-as-username,
  fail-closed): when a token issuer exists, every enrolled identity starts
  presenting tokens and nothing else moves.

## Design principle: claims are locks

A claim is an exclusive lock acquisition: at most one actor holds a
bead. That is an invariant no replicated store grants coordination-free
(the CALM constraint; derivation in _kos/findings/ findings 003 and
004), and bd agrees: `bd update --claim` is atomic against one store,
and upstream's merge-slot is the same admission. So callbook splits
three planes deliberately, and refuses to let one masquerade as
another:

- **Identity plane** (this document): every actor writes under its own
  durable name, stamped by its spawner. Multi-author is an identity
  property, not a topology property.
- **Write plane**: per project, one coordinated store (the production
  recipe's instance). Any agent anywhere writes and claims there, as
  itself, over TLS. At-most-one-claim holds by construction; no merge
  class exists.
- **Read plane**: replicas wherever they help: polling fleets,
  dashboards, history tooling, offline reading, warm DR.
  Freshness-critical reads (is it still open, did my claim land) go to
  the write plane; everything else may lag seconds.

Working copies that push whole histories remain the right shape for
human-pace teams and for federation between sovereign teams; they are
not the fleet shape. The topology map is
[patterns.md](patterns.md); the fleet pattern is its pattern 5.

## The actor model

### Humans

A human is an actor under their own name or handle. Their machines each
carry a `node_id` (one per distinct bd store), so "Alice on her laptop"
and "Alice on the build box" are distinguishable stores backed by one
identity.

### A person's agent troupe

Each person maintains a **name pool**: a set of durable, memorable actor
names recorded in the project docs. Agents draw names from the pool:

- Each agent session carries `BEADS_ACTOR` set to its pool name, and
  the SPAWNER exports it (the launcher, orchestrator, or wrapper that
  starts the session): on today's harnesses an agent cannot derive
  its own identity, so stamping is the spawner's job, never
  self-report. Verified on stock bd 1.1.2: create records the actor
  in created_by, claim writes it into assignee (finding-006).
- Each distinct store sets its own `node_id`.
- Ephemeral agents are fresh sessions under a pool name. Kill freely;
  the name persists, the session doesn't.

This gives attribution and lease-safety without credential churn. The
agents share the person's project credential; the *names* carry identity.
When authenticated agent principals arrive (see phases below), each pool
name becomes a token subject and history stays coherent.

Pick names you can say out loud in standup. A pool is a cast list
(theater troupes, carnival performers, whatever register your project
enjoys), as long as names are stable and never reused across people.

### Long-lived service agents

CI runners and standing automations are not troupe members; they get
their own named account (e.g. `<project>_agent_ci`), individually
scoped and individually revocable. When one is compromised or retired,
you revoke *it*, not the team.

### Where an actor runs (direction)

bd's schema carries a `rig` column and a cross-rig address grammar
(`<rig>:<bead-id>`), upstream's own name for an installation. The
direction under evaluation: rig as the actor's runtime locus, with one
known mapping per runtime kind (an orchestrator id plus workspace, a
human plus directory, a session surrogate, a factory instance). The
actor answers WHO; the rig answers WHERE, which is the first hop of
"who do I check with." Constraints and open questions:
_kos/ideas/rig-as-runtime-locus.md.

## Enrollment phases

Enrollment means: an identity (human or agent) gains a *scoped,
revocable* path to a project's tracker. Four phases; each is useful
alone, and none requires the next.

### Phase 0: convention (now)

Documentation and discipline only: humans enroll by receiving a
per-project credential-read grant from wherever your credentials live
(cloud parameter store, Vault, a password manager); their agent troupe
shares that credential under pool names; service agents get named
accounts. Revocation is per-human (detach the grant) or per-service-agent
(drop the account).

### Phase 1: the local-instance kit

Everyone, including contributors who will never touch your cloud, gets
a local beads instance, and *enrollment attaches that instance to the
shared tracker*. This is [kit/](../kit/): install, doctor, enroll. The
kit works with zero cloud access; enrollment is an upgrade.

### Phase 2: ephemeral credential minting

A secrets engine (OpenBao/Vault database backend) minting short-TTL SQL
users against the shared instance: humans via OIDC login, in-cluster
agents via Kubernetes auth, external agents via cloud IAM auth. Leases
expire; revocation is automatic. Operational cares (orphan-lease sweeps,
post-failover lease self-healing, the grant set minted users need) are
recorded in [enrollment.md](enrollment.md).

### Phase 3: the gateway (convergence)

A gateway in front of the tracker verifies short-lived tokens presented
as SQL usernames (the bd client contract already exists), routes per
project, and owns schema. Actor names become authenticated subjects; the
Phase-0 honor system retires. Build trigger: external-team tenancy or a
per-actor-authentication requirement, not before.

## How work flows

- **`bd ready` is the callboard.** Agents pull unblocked work; humans
  triage and set dependencies. Ready/blocked semantics replace hand-kept
  status tables.
- **Epics → issues → tasks** map to roadmaps → plans → tasks in most
  planning vocabularies.
- **Branches for parallel work.** A fork or an experimental agent run
  gets its own database (or its own branch) on the shared instance;
  merge or discard like code.
- **Federation for sovereignty.** Two orgs collaborating keep their own
  trackers and sync as peers over the dolt remote protocol. Contributors
  without connectivity participate through the git channel
  (`refs/dolt/data`).
- **The tracker never owns your artifacts.** Project documents may cite
  bead IDs (they are stable and hash-suffixed); the tracker never stores
  your project's content. A project with callbook disabled loses task
  tracking, nothing else.

## What callbook is not

- **Not a fork of beads** (today). Stock `bd` + Dolt, deployed with
  opinions. Gaps get upstream issues first; a feature fork that tracks
  upstream and offers changes back is a recorded likely-future. bd is
  itself growing the multi-agent layer (rigs, cross-rig gates, an
  exclusive merge-slot, heartbeat wisps; finding-006); callbook rides
  that trajectory rather than parallel-building it.
- **Not a hosted service.** Recipes and tooling; you run it.
- **Not a project-management methodology.** It tracks calls: who,
  what, when, blocked-by. What your team does with that is your process.
