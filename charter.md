# callbook Charter

> Re-introduction document for callbook — work/task tracking for
> distributed agent+human teams, built on beads + Dolt. Restores context
> for a collaborator who was present but does not persist. Follows the
> kos process: Orient → Ideate → Question → Probe → Harvest → Promote.

Last updated: 2026-07-25 (scaffold session + founder scope framing: F1 refined, F7-F8 opened)

---

## The Problem Statement

Teams of humans and AI agents need shared work tracking that survives
agent ephemerality, records attribution honestly, works offline, and
deploys anywhere from a laptop to a replicated cloud service. beads (bd)
provides the data model (issues as versioned rows in Dolt, git
semantics, local-first). What's missing is everything around it: how
identities enroll, how instances connect and federate, how the service
deploys per cloud, and an opinionated collaboration model that makes
the whole thing coherent for any project — not just the ecosystem beads
grew up in.

callbook packages that: vision docs, a local-instance kit, and
production deployment recipes extracted from a real, verified platform
deployment (genericized and scrubbed of its origin org).

## Design Values

1. **Local-first, cloud-optional.** The kit works with zero cloud
   access; enrollment is an upgrade, not a prerequisite.
2. **Names are the durable identity.** Actor names outlive sessions,
   credentials, and (eventually) the honor system — chosen once, they
   become authenticated token subjects when first-class agent identity
   arrives.
3. **Enrollment terminates in a per-identity artifact.** Never in
   copying a shared secret by hand.
4. **TLS from day one** on anything beyond localhost.
5. **Extracted, not invented.** Recipes come from deployed, drilled
   infrastructure; untested translations are labeled as such.

## Non-Goals

- **Not a fork of beads** (today — see F5).
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
2.2.2).

### B3: The actor model — names + pools + tiers

Humans are actors under their own handles; each person's agents draw
durable names from a recorded name pool (`BEADS_ACTOR`), with `node_id`
per store; long-lived service agents get individually revocable named
accounts. Three standard account tiers per project (admin/rw/ro).
Full model: `docs/vision.md`, `docs/enrollment.md`.

---

## Frontier

*Actively open.*

### F1: What IS this repo — solution, recipe, or product? [refined 2026-07-25]

Partially resolved by the founder's framing: **callbook is the project
name for the whole program** — beads + identity enrollment + team,
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
may cite bead IDs but the tracker never stores project content — a
project with callbook disabled loses task tracking, nothing else.
vsdd-factory is the first case (deliberately complementary to its
derived-index traceability decision, upstream #671); teaming across
forks = shared database or federation. Needs: a docs/attaching.md
playbook + the vsdd-factory pilot.

### F8: Substrates beyond Kubernetes and the growth path

Named scope not yet in deploy/: plain-VM/EC2 recipe (systemd +
dolt sql-server + certbot/ACME TLS), DigitalOcean, Cloudflare
(genuinely open — no obvious TCP-passthrough for 3306; Tunnel or
Spectrum territory), and a first-class growth-path doc
(solo-local → team compose → cloud → federated) — the recipe/template
heart of the project, currently only implicit across docs.

### F9: Operational layers — marvel-managed vs standalone vs parts

Founder idea (2026-07-25): the moving parts (dolt instances, enrollment
artifacts, federation peering) should be operable at three levels —
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
runs, bd version pinning (proxied-TLS gate), a `--uninstall`, and the
smoke test exercising a proxied-server enrollment against a real
tracker. The enroll flow needs the admin-first-attach dance documented
inline once the upstream gap moves.

### F3: Per-cloud verification

AWS is drilled; GCP/AKS notes are honest translations, untested. The
logical-backup remote is `aws://`-shaped — the GCP/Azure story
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

### F6: Upstream gaps (tracked)

(a) federation sync always presents root to remotesapi instead of peer
credentials; (b) proxied-server stack should probe before
`CREATE DATABASE` (the direct-server stack already does) — also what
unlocks restricted-tier enrollment; (c) rw-tier first-attach of an
existing database needs `dolt_remote()` coverage. File upstream, link
issue numbers here.

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

---

## Session Log

| Session | Date | Outcomes |
|---------|------|----------|
| Scaffold | 2026-07-25 | Repo created. README, vision, enrollment, local-instance, dolt-service design record; Helm chart extracted + scrubbed (namePrefix parameterized, org label → callbook.arcaven.com, Datadog optional, storage-class neutral); kit v0 (install/doctor/enroll + launchd/systemd); compose recipe; AWS/GCP/Azure cloud notes. B1–B3 set, F1–F6 opened, G1–G3 ruled. Origin: generic extraction of a deployed per-project Dolt platform service + its beads-enrollment proposal. bd: aae-orc-z2t8. |
