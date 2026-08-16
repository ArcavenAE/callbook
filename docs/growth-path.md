# The Growth Path: solo laptop to distributed team, one step at a time

> Status: DRAFT (2026-08-01; revised 2026-08-16). Steps 0 through 2
> are extracted from deployed, drilled infrastructure. Step 3 is
> measured end to end on a live staging bring-up plus an instrumented
> local probe; its multi-machine rehearsal is in progress. Step 4 is
> design. Honesty labels per this repo's convention: anything not
> verified on a live deployment says so.
>
> Revision note (2026-08-16): step 1 gains the actor-stamping rule,
> and step 3 splits by pace: working copies for human-pace teams, the
> central write plane with edge read replicas for agent fleets.
> Derivation: _kos/findings/ findings 003 through 006.

Every team starts as one person. This document is the recipe spine of
callbook: each step is a working state, each transition is small, and
nothing you build at one step is thrown away at the next. Companion
map of the topologies: [patterns.md](patterns.md).

## Step 0: solo, embedded (five minutes)

```sh
bd init --prefix myproject
bd create --title "first bead"
```

One machine, no server, no credentials. Offline by construction.
Stay here as long as you are alone on one machine.

**Backup from day one**, because the laptop will eventually die:

```sh
bd dolt remote add origin git+ssh://git@github.com/you/yourrepo.git
bd dolt push
```

Your project's git remote doubles as the store's remote (Dolt data
rides under `refs/dolt/data`, invisible to normal git use). If your
pushes are hardware-key gated and taps get expensive, that is the
first signal you are outgrowing step 0.

## Step 1: many agents, one machine (shared local server)

The trigger: concurrent sessions. A human plus several agents writing
at once wants SQL concurrency, not embedded file locking.

The kit in this repo does the conversion:

```sh
kit/install.sh          # server + launchd/systemd unit + keychain cred
kit/doctor.sh           # verifies the effective state, not the intended one
```

What changes: a `dolt sql-server` on localhost owns the store; every
session connects to it; a periodic JSONL export gives you a
git-trackable projection for viewers and an air-gap layer.

Three hard-won rules from real deployments:

1. **Never commit a host-specific pointer.** Connection settings that
   name a host, port, or user belong outside version control. A
   committed localhost pointer sends every other machine hunting for
   a server that is not there, and bd's auto-start then fabricates an
   empty database whose failure surfaces as an AUTHENTICATION error,
   sending the next debugger down the wrong road entirely.
2. **Set `BEADS_DOLT_AUTO_START=false` on shared-server machines.**
   Auto-start has no correct behavior when a managed server is
   supposed to exist: honest "connection refused" beats a plausible
   empty database.
3. **The spawner stamps a durable actor name into every session.**
   Export `BEADS_ACTOR` from the process that launches each agent
   (name pools per [vision.md](vision.md)); agents do not
   self-report. With the name stamped, `bd create` records it in
   created_by and `bd update --claim` writes it into assignee on
   stock bd 1.1.2 (finding-006). Skip this and every session
   resolves to one human, which is exactly the attribution hole an
   agent fleet cannot afford.

## Step 2: the always-on hub (cloud or closet)

The trigger: a second machine, a teammate, a dashboard, or an agent
that lives in the cloud. You need a store that is up when your laptop
is not.

Recipes in this repo, smallest first:

- `deploy/compose/`: single node, TLS, workbench. A small team's
  closet server. (Extracted; drilled at small scale.)
- `deploy/helm/dolt/`: Kubernetes with primary plus warm standby,
  TLS-required NLB, a remotesapi listener for clone/pull/push, and
  logical backups. (Extracted from a deployed service, failover
  drilled.)

Account tiers from day one: admin, read-write, read-only, with
credentials in a real credential store (cloud parameter store, OS
keychain), delivered to each machine out-of-band, never committed.

The hub gives you pattern 3 immediately (everyone connects as a
direct TLS client) and is the prerequisite for step 3. If your whole
team is always-online, you can simply stop here. Agent fleets stop
here for the WRITE plane permanently: fleet writes and claims stay on
the hub at any scale, and step 3's fleet form adds read replicas only
(pattern 5 in [patterns.md](patterns.md)).

**Order of bring-up matters** (measured the hard way): DNS delegation
for certificate issuance FIRST, then the service, then the SQL
accounts. The account step dials the hub's public name with verified
TLS, so nothing downstream of DNS can precede DNS. If your service
scaffolding sits in different control planes (DNS in one place,
cluster in another), no dependency graph will order this for you;
write it in the runbook and check it by hand:
the certificate challenge record must resolve before the service
applies, and the service must serve TLS before accounts apply.

## Step 3: working copies (the distributed team shape)

The trigger: offline work, resilience, or agent isolation; any of the
three. Each machine keeps its own local store (step 0 or step 1
form), and syncs with the hub like git.

Split by pace before adopting this step (2026-08-16). The
working-copy shape below is for HUMAN-pace teams: it relies on the
claim-before-edit convention, which autonomous fleets cannot hold
(finding-003), and claim exclusivity itself needs one coordination
point (finding-004). An agent fleet's step 3 is pattern 5 instead:
keep every write and claim on the hub, run a read replica per site
for polling, dashboards, history tooling, and DR, and stamp actors at
spawn. The rest of this step describes the human-pace shape.

Enrollment of a new machine is deliberately boring:

```sh
git clone <project>          # brings .beads/config.yaml with sync.remote
export DOLT_REMOTE_USER=...  # out-of-band credentials
export DOLT_REMOTE_PASSWORD=...
bd bootstrap --yes           # clones the store from the hub
```

Seeding the hub with an EXISTING store (the reverse direction, done
once by the team's founder):

```sh
# on the hub: create the empty database first (remotesapi cannot)
# then, from the machine that owns the story so far:
bd dolt remote add origin https://<hub>:8000/<dbname>
bd dolt push --force         # unrelated root histories; force is correct HERE ONLY
```

Day-to-day, per machine:

```sh
bd config set dolt.auto-commit on
bd config set dolt.auto-push true     # literally "true"; "on" silently fails
# pull side: session-start hook + a 30-60s timer running: bd dolt pull
```

Rules that keep it smooth (the measured sharp edge is same-bead
cross-machine edits; see [runbooks/sync-conflicts.md](runbooks/sync-conflicts.md)):

- one active editor per bead; claim before editing
- comments for discussion (never conflict), field edits for state
- pull before long edits; push before walking away
- writers hold SuperUser on the hub (a current upstream constraint):
  size your trust boundary accordingly, and keep read-only machines
  on the read-only tier

Verification before you rely on it, in this order: dummy-credential
TLS probe against the hub (auth-level denial proves the path), clone
round-trip from a second machine, a deliberate two-writer conflict
plus its resolution, then a restore test of the hub's backups. A
backup you have not restored is a hope, not a backup.

## Step 4: more teams (federation) and more rigor (tiers)

Two different triggers, two different answers:

- **Another team or an external collaborator** wants to exchange
  beads with you while keeping their own authority: that is
  federation (pattern 6). Designed upstream, young; watch this repo's
  charter F6 for the gaps that matter.
- **Your own throughput** makes one rigor policy wrong for both your
  prototypes and your production: that is the tiered pipeline
  (pattern 7), several pattern-4 hubs (or pattern-5 write planes,
  for fleet tiers) with different account policies and conventions,
  connected by promotion agents.

Both reuse everything below them. Nothing on this path is discarded;
each step is the previous step plus one capability.

## The whole path at a glance

| Step | State | Trigger to move on |
|---|---|---|
| 0 | solo, embedded, git-remote backup | concurrent sessions |
| 1 | shared local server | second machine / teammate / cloud agent |
| 2 | always-on hub, tier accounts | offline, resilience, isolation |
| 3 | human pace: working copies + hub; fleets: central writes + edge read replicas | another team, or rigor pressure |
| 4 | federation and/or tiers | (you are running an organization now) |
