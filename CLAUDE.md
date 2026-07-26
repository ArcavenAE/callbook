# CLAUDE.md: callbook

Work/task tracking for distributed agent+human teams: beads (bd) + Dolt,
packaged as vision docs + local-instance kit + production deploy recipes.
The opinionated companion to beads.gascity.com, for any project.

> **⚠ Public-repo scrub rule (load-bearing).** callbook is destined to be
> PUBLIC and its content was extracted from a private corporate
> deployment. NEVER introduce the origin org's name, domains, zone names,
> environment identifiers, ticket prefixes, or internal hostnames into
> this repo: in code, docs, comments, commit messages, issues, or PRs.
> Genericize at the keystroke: "your credential store", "your
> authenticating proxy", `dolt-<project>.trackers.example.com`. When
> porting future material from the origin deployment, scrub BEFORE the
> first commit. Git history is forever here.

@charter.md

## Layout

```
docs/            vision.md, enrollment.md, local-instance.md, design/
kit/             install.sh, doctor.sh, enroll.sh, launchd/, systemd/
deploy/helm/dolt      production chart (any Kubernetes)
deploy/compose/       single-node small-team recipe
deploy/clouds/        aws.md (verified), gcp.md + azure.md (translations)
```

## Build / Test

Content + shell + Helm; no compiled code yet.

```sh
just check          # shellcheck kit/*.sh + helm lint + helm template
just template       # render the chart with default values
```

## Conventions

- **Bash:** `set -euo pipefail`, shellcheck-clean, `[[ ]]`, quoted vars.
- **Helm:** chart must stay `helm template`-able with default values;
  no cloud-specific defaults in values.yaml (cloud specifics live in
  deploy/clouds/ and service annotations).
- **Honesty labels:** anything not verified on a live deployment is
  labeled as untested translation. Extracted-and-drilled material says
  so. Don't blur the two.
- **Upstream discipline:** bd/dolt gaps get upstream issues, linked from
  charter F6. No forking by accident (charter F5 has the trigger).
- **Git workflow:** `main`, trunk-based (no distribution channel yet;
  gitflow per orc B11 when releases begin).
- **No file deletion:** never delete user files. Overwrite only with
  explicit intent.

## How to Work Here (kos Process)

1. Read charter.md (orient)
2. Capture ideas in `_kos/ideas/`; questions become frontier nodes
3. Probe, then write findings in `_kos/findings/`
4. Harvest: update `_kos/nodes/`; charter stays summary + pointer

Cross-repo questions belong in the orchestrator's `_kos/`.
