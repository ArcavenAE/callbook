# Enrollment: attaching identities to a shared tracker

> Companion to [vision.md](vision.md) (the model) and
> [design/dolt-service.md](design/dolt-service.md) (the instance being
> enrolled against). This is the operational detail per phase.

Enrollment means an identity — human or agent — gains a **scoped,
revocable** path to a project's tracker. The anti-pattern in all phases:
copying a shared secret by hand. Enrollment must terminate in a
per-identity artifact.

## Account tiers

The production recipe provisions three SQL accounts per project, plus
any named service-agent accounts:

| Account | Tier | Who uses it |
|---|---|---|
| `<project>_admin` | Full object privileges on the instance | Break-glass, first-attach bootstrap, migration |
| `<project>_rw` | App-owner object set (what bd needs, including `CREATE VIEW` for schema migrations) | Day-to-day humans + their agent troupes |
| `<project>_ro` | Read + clone (`CLONE_ADMIN` for remotesapi working copies) | Dashboards, auditors, disconnected working copies |
| `<project>_agent_<name>` | Scoped per purpose | Long-lived service agents (CI, standing automations) |

`root` is reserved for platform automation (the IaC that provisions
accounts and grants). Humans never connect as root.

Passwords live in your credential store — cloud parameter store, Vault,
a team password manager — one path per account (the reference layout is
`/dolt/<project>/users/<account>`). Enrollment grants an identity *read
access to a path*, never the value out-of-band.

### Known upstream gaps (tracked)

- bd's proxied-server bootstrap of an *existing* database calls
  `dolt_remote()`, which the rw grant set does not cover — first attach
  from a new machine currently needs the admin account. Upstream issue;
  the kit's enroll flow documents the admin-assisted first-attach.
- bd's proxied-server stack issues `CREATE DATABASE IF NOT EXISTS`
  unconditionally on every open, and Dolt denies that statement without
  global CREATE even when the database exists — which is why grants stay
  instance-wide in the hybrid database model (see the design doc) until
  the upstream probe-before-create fix lands.
- Federation sync should forward peer credentials to remotesapi rather
  than always presenting the local root identity. Prerequisite for
  cross-org federation.

## Phase 0 — humans and troupes (convention)

**Human enrolls in project `<p>`:**

1. Grant their identity read access to `/dolt/<p>/users/*` in the
   credential store (attach a policy, add to a vault group — whatever
   your store's grant primitive is).
2. They run the kit's enroll step (or fetch the `<p>_rw` password
   manually) on each machine.
3. Revocation = detach the grant. One grant, one person, one project.

**Their agent troupe:** shares the person's `<p>_rw` credential. Each
agent gets a durable name from the person's name pool (recorded in the
project docs), set as `BEADS_ACTOR`; each distinct store sets `node_id`.
Ephemeral agents are fresh sessions under a pool name.

**Service agents:** a named account (`<p>_agent_ci`) minted through the
same IaC that manages the standard accounts — independent, individually
revocable.

## Phase 1 — the local-instance kit

See [local-instance.md](local-instance.md) and [../kit/](../kit/). The
enrollment step (`kit/enroll.sh`) does, in order:

1. Authenticate to your credential store (pluggable — see below).
2. Fetch the per-account credential.
3. Write the per-machine connection config (proxied-server bootstrap or
   federation peer, chosen by flag). Never into git-tracked files.
4. Mint `node_id` if absent.
5. Register the actor name from the pool.
6. Fail closed at every step.

The credential fetch is pluggable via `CALLBOOK_CRED_COMMAND` — any
command that prints the secret to stdout (an `aws ssm get-parameter`,
`vault kv get`, `op read`, or `pass show` one-liner). The kit ships
examples; it does not embed a cloud SDK.

## Phase 2 — ephemeral credential minting (pilot shape)

OpenBao/Vault **database secrets engine** against the shared instance —
the one Dolt-proven short-TTL minter. Auth methods by caller class:

- Humans: OIDC login against your IdP.
- In-cluster agents: Kubernetes auth.
- Off-cloud agents: cloud IAM auth (e.g. IAM Roles Anywhere for truly
  external machines).

Operational cares recorded from research and drills — read before
building:

- Write **explicit `DROP USER` revocation statements** in the role
  config; don't rely on defaults.
- Run an **orphan-lease sweep** plus a monitor: leases can outlive their
  pods.
- Minted users need the rw grant set **including global CREATE** (bd's
  unconditional `CREATE DATABASE` — see gaps above).
- **Post-failover, leases self-heal**: minted users die with the old
  primary; clients re-read their lease and get fresh accounts on the
  promoted pod. Verify in a drill before trusting it.
- Decision gate before build: this is a new operated service. Don't
  deploy a secrets engine to avoid writing four IAM policies.

## Phase 3 — the gateway

A tracker gateway verifying short-lived tokens presented as SQL
usernames (bd's client contract: `BEADS_DOLT_CREDENTIAL_COMMAND`,
token-as-username, fail-closed), routing per project database, owning
schema — bd goes passive, which also delivers a strict
databases-as-IaC model as a side effect.

Token issuer: your IdP (the industry's agent-registry direction makes
agents real principals there). This is where actor names become
authenticated subjects and the Phase-0 honor system retires.

**Build trigger:** external-team tenancy or a hard per-actor
authentication requirement. Not before.

## Open decisions (inherited, still open)

- OpenBao vs Vault for Phase 2 (licensing/ops preference).
- Whether ephemeral agents on developer workstations enroll via the
  person's identity (Phase 0 semantics) or wait for Phase 2 leases.
- bd version channel: proxied-server TLS requires a post-1.1.0 bd; the
  kit must pin or ship a known-good build until a release carries it.
- Whether mTLS (cert-manager-minted client certs, Dolt
  `REQUIRE SUBJECT`, bd's client-cert flags) is worth a spike for
  long-lived agents before the gateway exists — one empirical test
  decides.
