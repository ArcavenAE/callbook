# Design: a per-project Dolt database service

> The production recipe's decision record. Extracted from a deployed,
> verified platform service; genericized. Where a choice was
> environment-specific, the constraint that forced it is stated so you
> can re-derive the choice for your environment.

## Context

Teams need per-project version-controlled databases: branch/merge/diff
semantics on relational data, with a MySQL-compatible wire protocol.
[Dolt](https://www.dolthub.com/docs/introduction/what-is-dolt/) provides
this; beads (`bd`) rides on top of it. The target shape: one small,
replicated, TLS-required Dolt instance per project, addressable as
`dolt-<project>.<your-zone>`, at a scale envelope of roughly 10–30
instances per environment.

Platform constraints that shape everything downstream:

1. **Dolt is single-writer per data directory.** Two `sql-server`
   processes cannot share a data dir; NFS/multi-attach storage is
   unsupported. Eviction tolerance must come from **Dolt replication**,
   not shared network storage.
2. **The MySQL protocol cannot ride an HTTP load balancer.** MySQL TLS
   is negotiated in-protocol (STARTTLS-style), so TLS-terminating LBs
   and SNI routing do not apply. The load balancer must be **TCP
   passthrough**, and **certificates must be served by Dolt itself**.
3. **Wildcard DNS on a shared zone is a trap.** A `*.yourcompany.com`
   wildcard swallows every undefined label on the zone. Prefer explicit
   per-project records (one small DNS change per onboarding), or a
   dedicated subzone for the trackers.

## Decision

One Helm release per project (chart in
[deploy/helm/dolt](../../deploy/helm/dolt)) on whatever Kubernetes you
already run:

| Decision | Choice |
|---|---|
| SQL access | Per-project **TCP-passthrough load balancer**, port 3306, DNS name on the LB. MySQL auth + required TLS are the access controls. |
| Topology | **2 pods per project: primary + warm standby** via Dolt cluster (direct-to-standby) replication, with *required* pod anti-affinity so node consolidation/evictions never take both. The chart supports a second standby (scale `replicas`). |
| TLS | **Required from day 1** (`require_secure_transport`). cert-manager issues the certificate for the instance's DNS names; Dolt serves it on both listeners. |
| UI | `dolt-workbench` (browser SQL/diff/branch UI) is ClusterIP-only, published through your **authenticating app proxy** (Teleport, Pomerium, oauth2-proxy…) — never on the public LB. Opt-in per project. |
| Storage | Per-pod block storage (encrypted SSD class). Explicitly **not** NFS — constraint 1. |
| Sizing default | requests 500m/1Gi, limits 1 vCPU/2Gi, 20Gi per pod; override per project. |
| Onboarding | One values file (+ one DNS record if your zone isn't delegated). |

### TLS and DNS chain

cert-manager solves ACME DNS-01 in a zone the cluster's DNS automation
owns. If your public name lives on a corporate zone the cluster must not
write to, use CNAME delegation — both for the name and for the ACME
challenge:

```
dolt-foo.yourcompany.com                 CNAME  dolt-foo.trackers.internal-zone.example
_acme-challenge.dolt-foo.yourcompany.com CNAME  _acme-challenge.dolt-foo.trackers.internal-zone.example
dolt-foo.trackers.internal-zone.example  ALIAS  <load balancer>   (external-dns)
```

The issuer needs `cnameStrategy: Follow` for the challenge delegation to
work. No cross-account/zone DNS write is ever granted to the cluster.
The certificate carries both names as SANs.

### Access model

SQL-level resources (accounts, grants, database inventory) are managed
**separately from the instance** — small, frequent, low-blast-radius
changes that never touch the StatefulSet, LB, or certificates. Per
project: `<p>_admin`, `<p>_rw`, `<p>_ro` (tiers in
[enrollment.md](../enrollment.md)), passwords in your credential store,
`root` reserved for the automation itself.

Two Dolt-specific mechanics worth knowing before you build this layer:

- Dolt lacks `SHOW CREATE USER`, which most IaC MySQL providers need to
  *read* user resources — manage account create/rotate as an idempotent
  job (`CREATE USER IF NOT EXISTS` + `ALTER USER`), and manage **grants**
  declaratively (Dolt's `SHOW GRANTS` is MySQL-compatible, so grant
  drift is detectable).
- **Users and grants do not replicate** in cluster mode, and standbys
  reject writes. Accounts exist only on the acting primary — after a
  failover, re-run account provisioning against the promoted pod.

**Database creation policy: hybrid.** Declare the databases you care
about as IaC inventory (created if absent, delete-protected), but leave
grants instance-wide so bd's golden path — `CREATE DATABASE IF NOT
EXISTS` at `bd init` — keeps working. Strict IaC-only is empirically
broken with current bd: its proxied-server stack issues the CREATE
unconditionally on every open, and Dolt denies the statement without
global CREATE *even when the database exists*. Keep a strict-mode toggle
for non-bd instances or a future upstream fix. Note Dolt keeps dropped
databases recoverable via `dolt_undrop()` until purged, and CREATE/DROP
both replicate to standbys.

### Client compatibility

- bd ≤ 1.1.0 server mode cannot negotiate TLS and is rejected by the
  listener. Its **proxied-server** mode (post-1.1.0) connects with
  `--proxied-server-external-tls`. Pin a known-good bd until a release
  carries it.
- bd day-to-day traffic is the SQL wire; **federation sync uses the dolt
  remote protocol (remotesapi)** — which is why remotesapi is exposed as
  a second TLS listener on the same LB.

### remotesapi exposure

remotesapi (dolt clone/fetch/pull/push; gRPC over TLS, served by Dolt
with the same certificate, authenticated with SQL user credentials)
rides the SQL LB as a second listener (port 8000, toggleable). Verified:
`dolt clone --user <p>_admin https://dolt-<p>.<zone>:8000/<db>` from the
internet succeeds; credential-less access is refused. Note that
HTTP-only app proxies cannot front this listener — it is gRPC; that is
why it lives on the LB rather than behind the UI proxy.

### Monitoring

Dolt exposes a native Prometheus endpoint (`/metrics`, dedicated port);
the chart annotates pods for scraping (generic Prometheus annotations,
plus optional Datadog OpenMetrics autodiscovery). Replication state
comes from `dolt_cluster.dolt_cluster_status`. The monitors that matter
in production: standby replication lag/error, disk fill, and
failed-auth rate on the public listener (it *will* be scanned — see
Consequences).

### Backups

Two complementary layers:

1. **Volume snapshots** via your platform's block-storage backup.
2. **Nightly logical backups**: a CronJob issues
   `CALL dolt_backup('sync', …)` per database against the primary,
   targeting a Dolt `aws://` remote (S3 bucket + DynamoDB manifest
   table). The procedure executes *inside* the dolt sql-server process
   — so the instance's workload identity (e.g. IRSA) covers it and the
   job itself only needs SQL. Restore = `dolt clone` from the backup
   remote; drill it.

### Failover

Documented runbook, not automation: `CALL
dolt_assume_cluster_role('standby'|'primary', <epoch>)` on both pods,
then repoint the LB by flipping the chart's `primaryPodIndex`. Then
re-run account provisioning (users don't replicate). Post-failover
provisioning is deterministic — drill it before you need it.

## Consequences

- One LB per project — linear cost (order-of $16/mo + traffic on AWS),
  zero port-multiplexing complexity.
- Public 3306 is deliberately exposed (auth + required TLS as the
  controls). It **will** be scanned; failed-auth monitoring is part of
  the production gate, and source-range allowlists can be added later
  without redesign.
- The cluster gains a stateful workload class; aggressive node
  consolidation (e.g. Karpenter) stays safe because of required
  anti-affinity + PDB + the warm standby.
- Onboarding a project is mechanical: one values file, one DNS record.
