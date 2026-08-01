# Runbook: resolving a working-copy sync conflict

> Scope: pattern 4 in [patterns.md](../patterns.md), a working copy
> syncing against a hub. Verified on bd 1.1.2 with Dolt 2.2.3.

## When you are here

`bd dolt pull` stopped with:

```
Error: merge origin/main: merge conflicts in issues require operator
resolution; merge aborted and working set restored
```

Nothing is corrupted. Your local store is exactly as it was before
the pull; the merge was rolled back whole. The cause is almost always
two machines editing the SAME bead between syncs. Note that editing
DIFFERENT fields of the same bead still conflicts: every edit writes
the row's `updated_at` cell, and two writes in different seconds are
two values for one cell.

## Before touching anything

```sh
cp -r .beads .beads.backup-conflict
```

## Why this runbook uses raw dolt

The documented recovery tool (`bd doctor --fix`) is not available in
embedded mode as of bd 1.1.2, and no `bd dolt resolve` exists yet.
Until upstream ships one, the resolution is three SQL statements in
the store's own directory. This is the one sanctioned exception to
"never run raw dolt against a bd-managed store".

## Decide the winner

Look at both sides first:

```sh
bd show <bead-id>                       # your local value
cd .beads/embeddeddolt/<dbname>
dolt sql -q "SELECT priority, assignee, status, updated_at
             FROM issues AS OF 'origin/main' WHERE id='<bead-id>'"
```

`--theirs` takes the remote row whole; `--ours` keeps yours whole.
Cell-level cherry-picking is not offered here; if both sides carry
real changes you want to keep, pick one side, then re-apply the other
side's change through normal `bd update` afterward.

## Resolve

From the store directory (`.beads/embeddeddolt/<dbname>` for embedded
mode, the server data directory for server mode):

```sql
SET @@autocommit = 0;
CALL dolt_merge('origin/main');
CALL dolt_conflicts_resolve('issues', '--theirs');   -- or '--ours'
CALL dolt_commit('-Am', 'merge: resolve sync conflict');
```

Then, back in the project directory:

```sh
bd dolt push
bd list        # sanity: the store answers normally
```

If you resolved with `--theirs` and had a change worth keeping,
re-apply it now with `bd update`; it becomes a normal new commit and
syncs cleanly.

## Prevent the next one

- One active editor per bead: claim (assign) before editing.
- Discuss in comments (append-only, never conflict), not field edits.
- Keep auto-push on and a pull timer running: the shorter the window
  between syncs, the smaller the collision surface.

## If this happens weekly

You do not have a conflict problem, you have a convention problem:
two roles are sharing beads they should be splitting. Split the bead,
or split the role.
