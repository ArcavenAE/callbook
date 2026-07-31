# callbook Charter

> Re-introduction document for callbook: work/task tracking for
> distributed agent+human teams, built on beads + Dolt. Restores context
> for a collaborator who was present but does not persist. Follows the
> kos process: Orient → Ideate → Question → Probe → Harvest → Promote.

Last updated: 2026-07-30 (proxied mode struck from the plan: G4 opened, kit/docs/charter swept; F6 gains filed issue numbers #5177/#5178 + seeding cluster (h))

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

### F8: Substrates beyond Kubernetes and the growth path

Named scope not yet in deploy/: plain-VM/EC2 recipe (systemd +
dolt sql-server + certbot/ACME TLS), DigitalOcean, Cloudflare
(genuinely open: no obvious TCP-passthrough for 3306; Tunnel or
Spectrum territory), and a first-class growth-path doc
(solo-local → team compose → cloud → federated). That growth-path doc is
the recipe/template heart of the project, currently only implicit across
docs.

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
verification only; both exist in the proxied external stack); (f) TLS
and auth for remote servers are undiscoverable from the CLI
(gastownhall/beads#5011, docs PR #5144 open); (g) an environment
variable silently overrides an explicit `--server-port` flag at init
(resolution-order inversion): filed as gastownhall/beads#5177 with
fix PR #5178 (flag promotion + settable presence-aware tls key);
(h) a proxied-server workspace cannot be bulk-seeded
(import/export/federation refused, `bd migrate issues` panics):
gastownhall/beads#5180 + #5179; our import-leg PR #5181 was
withdrawn 2026-07-31 as not fully formed and needing rework.
Not on callbook's path (G4) but tracked because it gates anyone
arriving via that mode. (i) `bd import` miscounts on the **direct** path: existing rows are
reported as `created` (`importIssuesCore` sets
`Created: len(importedIDs)` and never sets `Unchanged`), so a converged
re-import reads as a fresh one and disagrees with `--dry-run` on the
same input. This one IS on callbook's path: direct mode is the primary
enrollment path and `bd import` is the seeding tool, so a seed that
silently reports every row as new is a bad signal at exactly the moment
an operator is checking whether a seed took. Reproduced independently
on a second machine; queued for upstream filing. Pairs with
aae-orc finding-081 (`import --dry-run` never consults the db): the real
run and the dry run compute their counts independently, which is the
underlying weakness.

Drafted filings for (e)/(f) live in the
orchestrator at `docs/briefs/beads-tls-upstream-filings-drafts.md`,
gated on reviewing engagement with our existing upstream filings.

Contribution vehicle: **ArcavenAE/beads** (fork of gastownhall/beads,
tier-2 shape: origin=fork, upstream=gastownhall). Intent is
contribute-back: issues with repro first, PRs where we can carry the
fix. This is NOT the F5 feature-fork; F5's trigger is unchanged.
Work-queue anchor: aae-orc-9h3f.

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
| Scaffold | 2026-07-25 | Repo created. README, vision, enrollment, local-instance, dolt-service design record; Helm chart extracted + scrubbed (namePrefix parameterized, org label → callbook.arcaven.com, Datadog optional, storage-class neutral); kit v0 (install/doctor/enroll + launchd/systemd); compose recipe; AWS/GCP/Azure cloud notes. B1–B3 set, F1–F6 opened, G1–G3 ruled. Origin: generic extraction of a deployed per-project Dolt platform service + its beads-enrollment proposal. bd: aae-orc-z2t8. |
| Direct-mode TLS verification | 2026-07-30 | finding-001: the "bd server mode cannot speak TLS" premise behind the proxied-mode default was disproven (dummy-password discrimination against a deployed TLS-required instance; runtime TLS works on released 1.1.0/1.1.2, only `bd init` drops TLS, upstream #3895/#3679 unreleased). Design doc client-compat rewritten, B2 scope note (CREATE defect is proxied-only, #5079), F2 reframed, F6 gains (d)-(g), enroll.sh writes direct-mode vars first, doctor.sh warning retargeted. Upstream filing drafts staged in the orchestrator, gated on engagement review. |
| Public-readiness pass | 2026-07-26 | Brand sweep: every em dash removed repo-wide (155 lines touched; gates now enforce absence via byte-escape grep). Public furniture: CONTRIBUTING.md, SECURITY.md, CI (harden-runner + checkout SHA-pinned; shellcheck, helm lint, two template renders, style/leak gate). just check mirrors CI and caught its own gaps (default render needed issuerRef; org-token grep self-matched; both fixed). Repo metadata: description de-dashed, 9 topics set (ai-agents, issue-tracking, task-management, dolt, kubernetes, helm, local-first, self-hosted, beads). Full-history scrub verified (only authorship matches). Still private; flip is a one-command decision. |
| Fresh-machine deltas + direct-path import defect | 2026-07-30 | Independent second-machine attempt against a kit-shaped server, arrived at from the orchestrator side (aae-orc finding-089, with the mode arc in aae-orc finding-088). Confirms finding-001 + G4 from a separate direction: the same false TLS premise had also been written into the orchestrator's Phase-1 plan, and building the proxied path is what disproved it there too. Additive here: **F2** gains two kit items (`doctor` must assert the *effective* port, since bd path-hashes one when unset and its auto-start then manufactures an empty server that fails as an *auth* error; and a host-specific connection pointer must not be a shared/committed artifact, which is what carried the bad port to the second machine). **F6** gains (i): `bd import` miscounts on the **direct** path, reporting existing rows as `created` and disagreeing with `--dry-run` on the same input. Unlike (h) this one is on-path, since direct mode is primary and import is the seeding tool. **F6(h)** corrected: our PR #5181 was withdrawn as needing rework, not in flight. |
