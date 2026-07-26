# Reference: the Kubernetes deployment, as actually wired

> How the origin platform deploys the [dolt chart](../../deploy/helm/dolt/)
> with IaC around it (anonymized). The chart is in this repo; this doc is
> the *wiring*: what your Terraform/Pulumi/scripts must supply around a
> `helm install` to reproduce the verified production shape. Names below
> use `dolt-<project>` / `example.com`; substitute your own.

## The two-component split (deliberate)

The origin runs **two** IaC components per project, and the split is
load-bearing:

1. **Instance**: namespace, root secret, the Helm release
   (StatefulSet/LB/certs). Changes rarely; touching it risks the LB and
   volumes.
2. **Resources**: SQL accounts, grants, database inventory. Changes
   often (enrollments, new agents); applies must never be able to touch
   the StatefulSet.

Small frequent identity changes should never carry infrastructure blast
radius. Whatever tool you use, keep this seam.

## Instance wiring

Per project, around `helm install dolt-<project> deploy/helm/dolt`:

- **Namespace** `dolt-<project>` (one per instance), labeled for
  inventory queries.
- **Root credential**: generate a 32-char password; write it twice:
  a SecureString in the credential store (operator break-glass at
  `/dolt/<project>/root_password`) and a k8s Secret
  (`dolt-<project>-root`, key `root-password`) that the chart's
  `existingSecret` consumes. `root` never leaves platform automation.
- **Values wiring** (the full set the origin passes):
  `project`, `region`, `replicas`, `primaryPodIndex`, image
  repository behind an optional private-registry prefix,
  `existingSecret`, `tls.issuerRef` + both `dnsNames` (public vanity
  name + the automation-owned zone name), `service.annotations` (LB
  provisioning + external-dns hostname), `loadBalancerSourceRanges`,
  `persistence.size`, `resources`, `remotesapi.{enabled,lbEnabled}`,
  `workbench.enabled`, `backup.{enabled,schedule,remoteUrl}`, and the
  ServiceAccount workload-identity annotation when backups are on.
- **LB annotations** (AWS flavor): external NLB, IP targets,
  internet-facing, `external-dns.alpha.kubernetes.io/hostname` set to
  the automation-owned zone name. The public vanity name is a CNAME on
  top, managed wherever that zone lives (with the `_acme-challenge`
  CNAME beside it; see the [design record](design/dolt-service.md)).
- **Backup IAM** (when enabled): the policy grants object read/write on
  `<bucket>/dolt-<project>/*`, list on the bucket, and item-level
  access on the DynamoDB manifest table; it binds to the **chart's
  ServiceAccount** via workload identity. This is the subtle part:
  `dolt_backup()` executes *inside* the dolt sql-server process, so the
  StatefulSet pods (not the CronJob) need the credentials; they share
  the SA. Backup remote URL: `aws://[<table>:<bucket>]/dolt-<project>`
  (the chart appends `/<db>`).

## Resources wiring

Connects as `root` to the instance's **public TLS endpoint** (the same
path clients use, verifying the cert chain end-to-end on every apply),
and manages:

- **Accounts**: `<project>_admin`, `<project>_rw`, `<project>_ro`
  (+ any `additional_users` like `<project>_agent_ci`). Passwords
  generated, written to the credential store at
  `/dolt/<project>/users/<account>` and to a per-namespace Secret.
  Because Dolt lacks `SHOW CREATE USER` (which IaC MySQL providers need
  to read user state), account create/rotate runs as an **idempotent
  hook Job** (`CREATE USER IF NOT EXISTS` + `ALTER USER`) rather than a
  provider resource.
- **Grants** (declarative; Dolt's `SHOW GRANTS` is MySQL-compatible,
  so drift is detected):
  - `rw`: the app-owner object set bd needs (SELECT/INSERT/UPDATE/
    DELETE/CREATE/DROP/ALTER/INDEX/REFERENCES/EXECUTE/CREATE VIEW/
    SHOW VIEW/TRIGGER/CREATE+ALTER ROUTINE/CREATE TEMPORARY TABLES/
    LOCK TABLES), **plus `CLONE_ADMIN`**.
  - `ro`: SELECT, EXECUTE, `CLONE_ADMIN`.
  - `admin`: `*.*` with GRANT OPTION.
  - `CLONE_ADMIN` is what authorizes **remotesapi reads** (dolt
    clone/fetch/pull, i.e. bd federation and disconnected working
    copies). remotesapi *push* still requires superuser, i.e. admin.
- **Databases (hybrid model)**: declared databases are created if
  absent (`utf8mb4`/`utf8mb4_0900_bin`) and delete-protected
  (`prevent_destroy`); grants stay instance-wide (`*.*`) so bd's
  unconditional `CREATE DATABASE IF NOT EXISTS` keeps working. A
  scoped-grants toggle exists for non-bd instances; it is incompatible
  with current bd (see the design record).
- **Enrollment output**: a ready-made credential-store read policy
  (scoped to `/dolt/<project>/users/*`); attaching it to a person's
  role IS Phase-0 enrollment ([enrollment.md](../enrollment.md)).

## Failover interplay

Users/grants exist only on the acting primary (cluster replication
does not carry them; standbys reject writes). The failover runbook is
therefore three steps, not two: `dolt_assume_cluster_role` on both
pods → flip `primaryPodIndex` → **re-apply the resources component**
against the promoted pod. Drilled on the origin platform; deterministic.

## Verified state (what "extracted, not invented" means here)

On the origin deployment, from this exact wiring: ACME cert issued for
both SANs via CNAME-delegated DNS-01; `openssl s_client -starttls
mysql` presents it on the public name; write on primary visible on
standby with `replication_lag_millis=0`; pods on separate nodes
(required anti-affinity); internet `dolt clone` over remotesapi with a
user credential succeeds and credential-less access is refused; backup
job → objects + manifest rows → `dolt clone` restore with data intact;
failover + re-provision drill green.
