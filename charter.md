# callbook Charter

> Re-introduction document for callbook: work/task tracking for
> distributed agent+human teams, built on beads + Dolt. Restores context
> for a collaborator who was present but does not persist. Follows the
> kos process: Orient → Ideate → Question → Probe → Harvest → Promote.

Last updated: 2026-08-16 (agent-fleet reframe: findings 003-006 + write-plane ruling harvested into docs; F10 opened, B3 evidence added, F6 candidates noted)

---

## The Problem Statement

Teams of humans and AI agents need shared work tracking that survives
agent ephemerality, records attribution honestly, works offline, and
deploys anywhere from a laptop to a replicated cloud service. beads (bd)
provides the data model (issues as versioned rows in Dolt, git
semantics, local-first). What's missing is everything around it: how
identities enroll, how instances connect and federate, how the service
deploys per cloud, and an opinionated collaboration model that makes
the whole thing coherent for any project, not just the ecosystem beads
grew up in.

callbook packages that: vision docs, a local-instance kit, and
production deployment recipes extracted from a real, verified platform
deployment (genericized and scrubbed of its origin org).

## Design Values

1. **Local-first, cloud-optional.** The kit works with zero cloud
   access; enrollment is an upgrade, not a prerequisite.
2. **Names are the durable identity.** Actor names outlive sessions,
   credentials, and (eventually) the honor system. Chosen once, they
   become authenticated token subjects when first-class agent identity
   arrives.
3. **Enrollment terminates in a per-identity artifact.** Never in
   copying a shared secret by hand.
4. **TLS from day one** on anything beyond localhost.
5. **Extracted, not invented.** Recipes come from deployed, drilled
   infrastructure; untested translations are labeled as such.

## Non-Goals

- **Not a fork of beads** (today; see F5).
- **Not a hosted service.** Recipes and tooling; users run it.
- **Not a PM methodology.** callbook tracks calls; process is the
  team's business.

---

## Bedrock

*Established. Evidence-based or decided with rationale.*

### B1: The per-project Dolt service shape

One Helm release per project: Dolt sql-server StatefulSet (primary +
warm standby via cluster replication, required anti-affinity),
TCP-passthrough LB pinned to the acting primary, TLS required from day
one (cert-manager, dolt-served certs), optional remotesapi second
listener (federation + clone), optional workbench behind an
authenticating proxy, optional logical backups to a cloud remote.

Evidence: extracted from a deployed service verified end-to-end on a
live EKS cluster (TLS handshake on the public name, write-on-primary
visible on standby with zero lag, anti-affinity scheduling, metrics
scrape, clone + restore drills, failover drill). Design record:
`docs/design/dolt-service.md`.

### B2: Hybrid database-creation model

Declare known databases as IaC inventory (created if absent,
delete-protected); leave grants instance-wide so bd's golden path
(`CREATE DATABASE IF NOT EXISTS` at init) keeps working. Strict
IaC-only is empirically broken with current bd: its proxied-server
stack issues the CREATE unconditionally on every open and Dolt denies
it without global CREATE even when the database exists (verified on
2.2.2). Scope note (2026-07-30): the defect is proxied-stack-only;
bd's direct-server stack probes before creating (upstream ask
gastownhall/beads#5079). With proxied mode struck from the plan (G4),
callbook clients are direct-mode only and moving to the strict model
is an open follow-up; hybrid remains the shipped default for stock-bd
compatibility until that lands.

### B3: The actor model (names + pools + tiers)

Humans are actors under their own handles; each person's agents draw
durable names from a recorded name pool (`BEADS_ACTOR`), with `node_id`
per store; long-lived service agents get individually revocable named
accounts. Three standard account tiers per project (admin/rw/ro).
Full model: `docs/vision.md`, `docs/enrollment.md`.

Attribution verified live on stock bd 1.1.2 (finding-006, 2026-08-16):
with `BEADS_ACTOR` stamped by the spawner, create records the actor in
created_by and `--claim` writes it into assignee. The stamping is the
spawner's job (agents cannot self-derive identity on today's
harnesses).

---

## Frontier

*Actively open.*

### F1: What IS this repo (solution, recipe, or product)? [refined 2026-07-25]

Partially resolved by the founder's framing: **callbook is the project
name for the whole program**: beads + identity enrollment + team,
local, and federated instances + attaching beads to other projects
(vsdd-factory first) + tools for anyone to set any of this up
themselves, on any substrate, and grow it for their team. The repo is
that project's home. Still open: whether the deliverable form becomes
a versioned distribution ("the callbook stack") or stays docs+kit.
Revisit when someone other than us adopts it.

### F7: Project attachment playbooks (vsdd-factory first)

The un-ported §4 of the origin proposal: how an existing project
adopts callbook for its work-management plane. One project = one bd
workspace; roadmaps → epics, plans → issues, tasks → tasks; artifacts
may cite bead IDs but the tracker never stores project content; a
project with callbook disabled loses task tracking, nothing else.
vsdd-factory is the first case (deliberately complementary to its
derived-index traceability decision, upstream #671); teaming across
forks = shared database or federation. Needs: a docs/attaching.md
playbook + the vsdd-factory pilot.

### F8: Substrates beyond Kubernetes and the growth path [growth-path drafted 2026-08-01]

Named scope not yet in deploy/: plain-VM/EC2 recipe (systemd +
dolt sql-server + certbot/ACME TLS), DigitalOcean, Cloudflare
(genuinely open: no obvious TCP-passthrough for 3306; Tunnel or
Spectrum territory). The growth-path doc, the recipe/template heart
of the project, now exists as a draft: `docs/growth-path.md`
(steps 0-4, honesty-labeled), with the topology map in
`docs/patterns.md` (seven patterns incl. the agent-fleet write plane
and the tiered-rigor capstone, Mermaid diagrams) and
`docs/runbooks/sync-conflicts.md` (the measured same-bead conflict
resolution). Backing measurements: orchestrator finding-106.
Substrate recipes remain open.

### F9: Operational layers (marvel-managed vs standalone vs parts)

Founder idea (2026-07-25): the moving parts (dolt instances, enrollment
artifacts, federation peering) should be operable at three levels:
marvel-managed (tracker as a control-plane resource, reconciled
failover), callbook-standalone (launchd/systemd local services, the
as-built shape in `docs/reference/`), and individual parts by hand.
Independence rule holds: callbook never requires marvel. Full capture +
sub-questions: orc `_kos/ideas/callbook-operational-layers.md`.
Crystallization trigger: first marvel-managed team wanting a tracker at
bring-up, or the first fumbled manual failover.

### F2: Kit maturity

`kit/*.sh` are extracted-and-generalized first versions, not yet
soak-tested on a fresh machine. Needs: fresh-macOS and fresh-Linux
runs, bd version awareness (the init-TLS release gap, finding-001;
the old "proxied-TLS gate" framing is retired), a `--uninstall`, and
the smoke test exercising a direct-mode enrollment against a real
tracker. The enroll flow needs the admin-first-attach dance
documented inline once the upstream gap moves.

Two additions from an independent fresh-machine attempt (a second
laptop cloning an orchestrator wired to a `kit`-shaped server, aae-orc
finding-089):

- **`doctor` should assert the *effective* port, not the configured
  one.** bd derives a port by hashing the project path when
  `BEADS_DOLT_SERVER_PORT` is unset (as-built gotcha #1), so a machine
  can be pointed at a port nothing serves. Worse, bd's auto-start then
  creates its own empty server there, which rejects the configured user
  and surfaces as an **authentication** error. The natural diagnosis is
  credentials; the actual cause is the pointer. `doctor` is the right
  place to catch it because it already knows both values.
- **A host-specific connection pointer must not be a shared artifact.**
  The failure above only happened because the connection settings were
  committed to a repo and cloned to a second machine. Anything the kit
  writes that names a host, port, or user belongs outside version
  control, and `install.sh`/`doctor` should say so rather than leaving
  it to convention.
- **`bd init` walk-up adoption** (finding-008, 2026-08-16): run
  outside a git repository, bd init walks past the intended project
  root and adopts the first ancestor `.beads/` it finds (the
  user-level dir on the probe machine), rewriting its metadata.
  Prevention is git init before bd init; doctor should flag a
  user-level `~/.beads/metadata.json` that names an unexpected
  server. Same sharp-edge class as the host-specific pointer above.

### F3: Per-cloud verification

AWS is drilled; GCP/AKS notes are honest translations, untested. The
logical-backup remote is `aws://`-shaped; the GCP/Azure story
(S3-compatible endpoint vs snapshots+git-channel) is the weakest
corner. One verified deployment each would promote them.

### F4: Ephemeral credentials and the gateway (Phases 2–3)

OpenBao/Vault short-TTL minting (pilot shape + operational cares
recorded in `docs/enrollment.md`), then the token-verifying gateway
where actor names become authenticated subjects. Build triggers are
explicit: don't start Phase 2 without accepting a new operated
service; don't start Phase 3 before external-team tenancy or a hard
per-actor-auth requirement.

### F5: Fork beads?

Likely future: a maintained fork tracking upstream, adding what we
need (federation credential forwarding, probe-before-create in the
proxied stack, restricted-tier enrollment), offered back as PRs.
Trigger: when the upstream-issue path stalls on something load-bearing.
Until then: stock bd, pinned versions, issues filed.

### F6: Upstream gaps (tracked) [contribution vehicle live 2026-07-26]

(a) federation sync always presents root to remotesapi instead of peer
credentials; (b) proxied-server stack should probe before
`CREATE DATABASE` (the direct-server stack already does), which is also
what unlocks restricted-tier enrollment: filed as
gastownhall/beads#5079; (c) rw-tier first-attach of an existing
database needs `dolt_remote()` coverage. File upstream, link issue
numbers here.

Added 2026-07-30 (finding-001): (d) `bd init --server --external`
drops the TLS setting in every release up to 1.1.2
(gastownhall/beads#3895; fix #3679 merged 2026-07-04 but releases are
cut from a stale base, so it has not shipped); (e) direct server mode
has no custom-CA or client-certificate surface (system-roots
verification only; both exist in the proxied external stack): filed
2026-07-31 as gastownhall/beads#5200 (custom CA) + #5201 (client
certificates), each carrying a PR offer; (f) TLS
and auth for remote servers were undiscoverable from the CLI: fixed on
main 2026-07-31 (#5144 merged, closing #5011) but shipped in no
release, and the merged help states metadata.json carries no password
or tls key on purpose, a stance #5178's `bd dolt set tls` half must
re-argue or drop; (g) an environment variable silently overrides an
explicit `--server-port` flag at init (resolution-order inversion):
filed as gastownhall/beads#5177 with fix PR #5178 (flag promotion +
settable presence-aware tls key; now conflicts with merged #5144, see
(f)); (h) a proxied-server workspace cannot be bulk-seeded
(import/export/federation refused, `bd migrate issues` panics):
gastownhall/beads#5180 + #5179; import-leg PR #5181 withdrawn
2026-07-31 for rework (comment timestamps/ids lost on first import,
duplicate comment rows on re-import, export leg missing; rework list
in orc finding-092).
Not on callbook's path (G4) but tracked because it gates anyone
arriving via that mode. (i) `bd import` miscounts on the **direct** path: existing rows are
reported as `created` (`importIssuesCore` sets
`Created: len(importedIDs)` and never sets `Unchanged`), so a converged
re-import reads as a fresh one and disagrees with `--dry-run` on the
same input. This one IS on callbook's path: direct mode is the primary
enrollment path and `bd import` is the seeding tool, so a seed that
silently reports every row as new is a bad signal at exactly the moment
an operator is checking whether a seed took. Reproduced independently
on a second machine AND by the 2026-07-31 audit (orc finding-092);
filed 2026-07-31 as gastownhall/beads#5199. Pairs with
aae-orc finding-081 (`import --dry-run` never consults the db): the real
run and the dry run compute their counts independently, which is the
underlying weakness.

Survey outcomes (finding-007, 2026-08-16): (j) is ANSWERED, not
filed: the dormant agent columns are reserved base-schema surface,
and liveness deliberately lives in an ephemeral node-local leases
table at HEAD (lease + heartbeat + reclaim), returning in a tested
release after the accidental v1.2.1 (never install that tag; v1.2.2
is v1.1.2 renumbered and safe). (k) STANDS: no actor-to-dolt-author
plumbing anywhere at HEAD; file after one quarantined clone-side
grep confirms it, best timed after the lease release lands.
Adoption candidate rather than a filing: `claim.pools` (pool
pseudo-assignees with anti-steal) maps onto B3 name pools and team
claims; evaluate for enrollment docs at a tested release. New
candidate (l) from finding-008: `bd init` outside a git repo walks
up and adopts the first ancestor `.beads/` it finds, rewriting its
metadata (contaminated the user-level dir during the probe;
quarantined, production unharmed); prevention is git init first;
candidate upstream report plus a kit/doctor check (see F2).

The (e) drafts were FILED 2026-07-31 (#5200, #5201) after the audit
(orc finding-092) passed their gate and container-clean transcripts
replaced the leaky macOS captures; the brief at
`docs/briefs/beads-tls-upstream-filings-drafts.md` records the arc.
The (f) residual (no CLI flag; deliberate no-tls-key-in-metadata
stance) is carried on PR #5178.

2026-08-02 the maintainer swept the whole PR stack in one consolidated
review round; 2026-08-03 we absorbed every fix that was ours to carry:
#5087 refreshed onto moved main (a semantic weave with upstream's new
provider-option and locked-preparation plumbing), #5085 gained the two
requested seam fixes (credential-to-URL binding, mutex over fallback
callbacks), #5214 gained its short-ciphertext sentinel fix, and
#5207/#5214 were refreshed onto the corrected #5085. All heads
MERGEABLE; CI awaits maintainer workflow approval. #5178 and the
landing order remain maintainer-side. Full record: finding-002.

Contribution vehicle: **ArcavenAE/beads** (fork of gastownhall/beads,
tier-2 shape: origin=fork, upstream=gastownhall). Intent is
contribute-back: issues with repro first, PRs where we can carry the
fix. This is NOT the F5 feature-fork; F5's trigger is unchanged.
Work-queue anchor: aae-orc-9h3f.

### F10: Agent-fleet write topology and the identity plane [write plane ruled 2026-08-16]

The operator goal (massively distributed agents working the same
projects at the same time, each under its own identity) reframed the
distributed default. Findings 003 through 006 carry the arc: pattern
4's discipline model breaks at machine speed (003); the CALM
constraint makes claim exclusivity coordination-bound, so the choice
is coordinate-at-write vs CRDT-without-invariants, never partition
(004; 2026 substrate survey in
`_kos/ideas/conflict-free-versioned-db-substrate-landscape.md`:
nothing off-the-shelf is versioned AND conflict-free AND SQL);
multi-author is the identity plane, not the topology, and
at-most-one-claim is the first confirmed invariant (005); attribution
works today on stock bd 1.1.2 by stamping `BEADS_ACTOR` at spawn,
while the liveness columns are dormant and upstream is visibly
building the multi-agent layer: rigs, cross-rig gates, an exclusive
merge-slot, heartbeat wisps (006).

RULED 2026-08-16 (operator): the write plane is the coordinated
per-project store (B1's service); no standing requirement needs
distributed writes. Docs harvested same day: patterns.md pattern 5
(+ renumber), growth-path step-1 actor rule + step-3 pace fork,
vision claims-are-locks principle, README fleet mode + opinion 6,
local-instance fleet role, sync-conflicts scope.

Fan-out executed 2026-08-16 (five parallel forks): the read-replica
recipe SHIPPED, loopback-verified (`docs/runbooks/read-replica.md`,
`kit/replica.sh`, doctor checks; hub-down serves last-known data by
default); throughput MEASURED (finding-008: ~18 mutating ops/s per
instance, ceiling is the process-per-op client not dolt, claims
exactly-once under an 8-way race, ~500 agents per instance at one
write per 30s); liveness ANSWERED (finding-007: upstream ships
lease + heartbeat + reclaim at HEAD; adopt at a tested release,
build nothing local, never install v1.2.1); rig ANSWERED
(finding-007: rig means store; runtime locus rides the actor string
or metadata; idea revised in place); actor stamping LIVE (client-env
derived default for interactive shells; marvel stamps per-agent in
baseEnv, merged as marvel PR #196).

Still open: TLS-production-hub verification of the replica recipe;
the tested upstream release carrying the lease line (watch; never
v1.2.1); name-pool ratification (proposal drafted, pending the
human); the pattern-5 drill (aae-orc-khl5v). Node:
`_kos/nodes/frontier/question-cross-machine-write-topology.yaml`.

---

## Graveyard

*Ruled out. Kept for the reasoning.*

### G1: Shared network storage for multi-pod Dolt

EFS/Filestore/Azure Files multi-attach. Dolt is single-writer per data
directory; two sql-servers cannot share one. Replication is Dolt's
job, not the filesystem's.

### G2: Wildcard DNS for tracker names

`*.company-zone` swallows every undefined label on the zone. Explicit
per-project records or a dedicated subzone.

### G3: TLS-terminating / SNI-routing load balancers

MySQL TLS is negotiated in-protocol (STARTTLS-style); HTTP LBs and SNI
routing don't apply. TCP passthrough + dolt-served certificates is the
only shape that works.

### G4: bd proxied-server mode as the client path (struck 2026-07-30)

The recipe originally standardized on bd's proxied-server mode on the
belief that it was the only TLS-capable client. finding-001 disproved
that premise: direct server mode has negotiated TLS since v0.53.0 and
works on released builds. What proxied mode actually is: an
experimental per-workspace proxy for local multi-agent workspaces,
whose external-server sliver we were using for TLS alone. Ruled out
because every flag is EXPERIMENTAL upstream, it exists only in
post-1.1.0 HEAD builds, its open stack requires global CREATE
(gastownhall/beads#5079), and a workspace opened that way cannot be
bulk-seeded (#5180, #5179). Reopen only if upstream stabilizes the
mode by documented decision AND it offers something direct mode
cannot (today that is only client certificates, tracked as F6 (e)
for direct mode instead).

---

## Session Log

| Session | Date | Outcomes |
|---------|------|----------|
| Fan-out execution (5 Opus forks) | 2026-08-16 | The F10 work queue executed in parallel. HEAD survey (finding-007): upstream ships the whole liveness layer at HEAD (claim TTL lease, bd heartbeat, bd reclaim reaper; node-local leases validate the central write plane); rig means store, so the runtime-locus carrier moves to the actor string (idea revised); v1.2.1 is an accidental untested release, never install; F6 (j) answered, (k) stands, claim.pools noted as B3 adoption candidate. Throughput probe (finding-008): ~18 mutating ops/s per instance, process-per-op client is the ceiling, claims exactly-once under 8-way race, bd-init walk-up gotcha captured as F6 (l) + F2 doctor candidate. Replica recipe shipped loopback-verified (2abf226: read-replica runbook + kit/replica.sh + doctor checks; hub-down serves last-known data). Actor stamping live: client-env derived default (mp/host/tty grammar, preset wins) + name-pool proposal awaiting ratification; marvel baseEnv stamps marvel/workspace/session, merged as marvel PR #196 (84ec78c). patterns.md pattern 5 gains measured numbers + the liveness direction. Board: usohe/8cfh6/fa3rr/a4nq3 closed; fxfkw open pending pool ratification; khl5v drill unblocks when fxfkw closes. |
| Agent-fleet reframe + docs harvest | 2026-08-15..16 | Operator goal (massively distributed agents, same projects, same time, own identities) reframed the distributed default. findings 003-006: pattern-4 discipline breaks at machine speed; CALM rules the choice (coordinate vs CRDT; partition struck by the goal); multi-author is the identity plane, at-most-one-claim the first confirmed invariant; bd 1.1.2 re-survey (attribution live via spawner-stamped BEADS_ACTOR: created_by + assignee verified on the running store; agent_state/last_activity/rig dormant; upstream building rigs, cross-rig gates, merge-slot, heartbeat wisps; wisps are a parallel table family excluded from JSONL export). 2026 substrate survey: no off-the-shelf store is versioned AND conflict-free AND SQL (document CRDTs closest, no SQL; cr-sqlite drops history). Write plane RULED central per project (operator, 2026-08-16). Docs harvest: patterns.md pattern 5 + validity domain on 4 + renumber (federation 6, capstone 7) + write-plane vocabulary; growth-path step-1 actor rule + step-3 pace fork; vision fourth problem (coordination) + claims-are-locks principle + spawner-stamps + rig direction; README fleet mode + opinion 6; local-instance fleet role; sync-conflicts scope note; B3 evidence; F6 candidates (j)(k); F10 opened. Ideas: conflict-free-versioned-db-substrate-landscape, rig-as-runtime-locus. Node: question-cross-machine-write-topology (4 findings edged). |
| Review-sweep response | 2026-08-03 | Maintainer's 2026-08-02 consolidated review of the PR stack verified claim-by-claim, then absorbed in one day: #5087 merged onto moved main (our create-policy options folded into upstream's new ProviderOption mechanism, probe-first moved under the migration lock via WithLockedPreparation, lock-order test updated); #5085 gained verifyPeerRemoteURL (fail closed on diverged or missing remote before installing credentials) and federationEnvMutex over the fallback callbacks, with three regressions; #5214 short ciphertext now classifies through CredentialKeyMismatchError; #5207 and #5214 refreshed onto corrected #5085 (#5207's whole review covered by the seam fix alone). All heads MERGEABLE; fork-PR CI awaits maintainer approval. ICU CGO test recipe captured (icu4c@78 include/lib paths); upstream review could not run these tests locally, ours did. finding-002; F6 updated; bd 9h3f noted. |
| Growth path + patterns drafts | 2026-08-01 | docs/growth-path.md (steps 0-4), docs/patterns.md (six topologies incl. tiered-rigor capstone, Mermaid), docs/runbooks/sync-conflicts.md. Grounded in orc finding-106 (working-copy topology measured: auto-push built in, updated_at conflict class, SuperUser-to-push constraint, seeding + bootstrap mechanics). Capstone citations pending research. F8 updated. |
| Scaffold | 2026-07-25 | Repo created. README, vision, enrollment, local-instance, dolt-service design record; Helm chart extracted + scrubbed (namePrefix parameterized, org label → callbook.arcaven.com, Datadog optional, storage-class neutral); kit v0 (install/doctor/enroll + launchd/systemd); compose recipe; AWS/GCP/Azure cloud notes. B1–B3 set, F1–F6 opened, G1–G3 ruled. Origin: generic extraction of a deployed per-project Dolt platform service + its beads-enrollment proposal. bd: aae-orc-z2t8. |
| Contribution audit | 2026-07-31 | Every assertion in our 8 beads issues + 5 PRs re-tested empirically (14-agent verify + adversarial-refute workflow at orc; 113 assertions; orc finding-092). Substance held everywhere; flaws were evidence hygiene (transcript folds on #5080/#5084 carried the script pasted twice; dirty-tree counts on #5179/#5181) and overgeneralization sentences (#5177 host/user, #5085 body, #5086 comment mechanics). Corrections posted: real container-captured transcripts into #5080/#5084 bodies + comments, #5177 sentence + mechanism correction, #5179 count fix, #5086 staleness note. New upstream facts: #5144 merged/#5011 closed (F6 (f) updated), post-#4909 real-import miscount discovered, `bd init --external` auto-start gap, `federation sync` positional arg ignored. Drafts gate passed; bd queue updated under aae-orc-9h3f. |
| Direct-mode TLS verification | 2026-07-30 | finding-001: the "bd server mode cannot speak TLS" premise behind the proxied-mode default was disproven (dummy-password discrimination against a deployed TLS-required instance; runtime TLS works on released 1.1.0/1.1.2, only `bd init` drops TLS, upstream #3895/#3679 unreleased). Design doc client-compat rewritten, B2 scope note (CREATE defect is proxied-only, #5079), F2 reframed, F6 gains (d)-(g), enroll.sh writes direct-mode vars first, doctor.sh warning retargeted. Upstream filing drafts staged in the orchestrator, gated on engagement review. |
| Public-readiness pass | 2026-07-26 | Brand sweep: every em dash removed repo-wide (155 lines touched; gates now enforce absence via byte-escape grep). Public furniture: CONTRIBUTING.md, SECURITY.md, CI (harden-runner + checkout SHA-pinned; shellcheck, helm lint, two template renders, style/leak gate). just check mirrors CI and caught its own gaps (default render needed issuerRef; org-token grep self-matched; both fixed). Repo metadata: description de-dashed, 9 topics set (ai-agents, issue-tracking, task-management, dolt, kubernetes, helm, local-first, self-hosted, beads). Full-history scrub verified (only authorship matches). Still private; flip is a one-command decision. |
| Fresh-machine deltas + direct-path import defect | 2026-07-30 | Independent second-machine attempt against a kit-shaped server, arrived at from the orchestrator side (aae-orc finding-089, with the mode arc in aae-orc finding-088). Confirms finding-001 + G4 from a separate direction: the same false TLS premise had also been written into the orchestrator's Phase-1 plan, and building the proxied path is what disproved it there too. Additive here: **F2** gains two kit items (`doctor` must assert the *effective* port, since bd path-hashes one when unset and its auto-start then manufactures an empty server that fails as an *auth* error; and a host-specific connection pointer must not be a shared/committed artifact, which is what carried the bad port to the second machine). **F6** gains (i): `bd import` miscounts on the **direct** path, reporting existing rows as `created` and disagreeing with `--dry-run` on the same input. Unlike (h) this one is on-path, since direct mode is primary and import is the seeding tool. **F6(h)** corrected: our PR #5181 was withdrawn as needing rework, not in flight. |
