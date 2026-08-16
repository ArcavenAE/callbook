# callbook

**The call book for distributed agent companies.** Work and task tracking
for teams of humans and AI agents, built on [beads](https://github.com/steveyegge/beads)
(`bd`) and [Dolt](https://www.dolthub.com/): version-controlled, local-first,
federable, and honest about who did what.

In a theater, the call book is the stage manager's record of calls: who is
called, for what, and when. That is exactly what a distributed agent team
needs, not another project-management SaaS, but a shared, diffable,
branch-aware record of the work, one that agents and humans write to with
equal standing and that survives any one machine, cloud, or company.

callbook is the opinionated companion to
[beads.gascity.com](https://beads.gascity.com): the same tool, applied to
*any* project, with deployment recipes from a laptop to a replicated
cloud service, and a collaboration model for the day your "team" is three
humans and forty agents.

## What's in the box

callbook is part solution, part recipe. Three layers, each useful alone:

| Layer | What it gives you | Where |
|---|---|---|
| **The vision** | How humans and agents share one tracker: actor identity, name pools, enrollment, attribution, the path to first-class agent identity | [docs/vision.md](docs/vision.md) |
| **The kit** | Scripts that stand up a local beads instance the way we run ours: install, doctor, enroll | [kit/](kit/) |
| **The recipes** | Deployment shapes: solo laptop → small team → replicated, TLS-required Dolt service on Kubernetes (any cloud) | [deploy/](deploy/), [docs/design/dolt-service.md](docs/design/dolt-service.md) |

## The working modes

All of these are supported shapes, not aspirations (the production
recipe has been verified end-to-end on a live cluster), with one
labeled exception: the agent-fleet edge is design assembled from the
deployed pieces, not yet a drilled deployment:

- **Solo, local-only.** A local bd instance; no cloud dependency at all.
  Optional sync through your project's git remote (`refs/dolt/data`).
- **Solo + cloud tracker.** Your bd talks TLS to a hosted Dolt instance.
- **Team on one project.** One database, many contributors, one-time
  per-machine bootstrap.
- **Agent fleet.** Many agents across many machines working the same
  projects at machine speed: every agent writes and claims on the
  project's central tracker under its own actor name; edge read
  replicas absorb polling, dashboards, and history tooling. Claims
  are atomic; no merge class exists. (Design; pattern 5 in
  [docs/patterns.md](docs/patterns.md).)
- **Fork / parallel work.** Your own database on the shared instance, or
  your own instance entirely.
- **Federation.** Peer trackers syncing over the dolt remote protocol,
  across teams, orgs, or forks.
- **Disconnected.** `dolt clone` a working copy, work offline, push/pull
  on reconnect (human-pace teams; fleet writes stay central).
  Air-gap-tolerant channels (git, file, S3 remotes) need no
  reachable server.

Local-first is the default posture. The kit works with zero cloud access;
enrollment to a shared tracker is an *upgrade*, not a prerequisite.

## Quick start (local)

```sh
kit/install.sh        # install bd + dolt, initialize the local shared server
kit/doctor.sh         # verify: versions, server reachability, config
cd your-project && bd init
bd create --title="first call" && bd ready
```

See [docs/local-instance.md](docs/local-instance.md) for the full runbook,
including the always-on service (launchd/systemd) variant.

## Production shape (any Kubernetes)

One Helm release per project: a Dolt `sql-server` StatefulSet (primary +
warm standby via Dolt cluster replication), TCP-passthrough load balancer
pinned to the acting primary, TLS required from day one (cert-manager),
optional remotesapi listener for federation and `dolt clone`, optional
browser workbench behind your authenticating proxy, optional scheduled
logical backups.

```sh
helm install myproject deploy/helm/dolt -f your-values.yaml
```

Design rationale and the full decision record:
[docs/design/dolt-service.md](docs/design/dolt-service.md). Per-cloud
notes: [deploy/clouds/](deploy/clouds/). As-built references (the
running local instance and the verified k8s wiring this was extracted
from): [docs/reference/](docs/reference/).

## Opinions

callbook is opinionated. The load-bearing ones:

1. **The tracker is a database with git semantics, not a website.**
   Branch, diff, merge, and clone the work record like the code.
2. **Agents are contributors, not tooling.** Every agent works under a
   durable actor name; attribution is first-class even before
   authentication is.
3. **First-class agent identity is the way of the future.** Today's
   shared-credential + actor-label model is a deliberate stopgap; every
   recipe here is shaped so the migration to authenticated per-agent
   principals is a re-pointing, not a re-architecture.
4. **Local-first, cloud-optional.** Nothing here phones home. A
   contributor with no cloud access is a full participant.
5. **TLS from day one** on anything that leaves localhost.
6. **Claims are locks.** At most one actor holds a bead, which needs
   one coordinated write plane per project. Read anywhere; claim in
   one place.

## Relationship to beads

callbook deploys and operates stock `bd` + Dolt. It is not a fork. Where
we hit gaps (federation credential handling, restricted-tier enrollment,
TLS-capable releases), we file and track upstream issues; a maintained
fork adding features we need (offered back upstream) is a likely future,
recorded in the [charter](charter.md).

## Status

Early. The production recipe is battle-tested (extracted from a deployed,
verified platform service); the kit and enrollment tooling are being
generalized from that deployment. See [charter.md](charter.md) for what is
bedrock vs frontier.

## License

MIT. See [LICENSE](LICENSE).
