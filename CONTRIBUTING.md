# Contributing

Thanks for looking. callbook is young; issues and small PRs are the most
useful contributions right now.

## What helps most

- **Verification reports.** The AWS recipe is drilled; the GCP and Azure
  notes are labeled translations. If you deploy on either (or on a
  substrate we haven't covered), an issue with what worked and what
  didn't is gold.
- **Kit runs on fresh machines.** `kit/install.sh` on a clean macOS or
  Linux box, with the transcript, pass or fail.
- **Corrections with evidence.** Every claim here is supposed to trace
  to a deployed, drilled setup. If you find one that doesn't hold, say
  what you ran and what you saw.

## Ground rules

- Branch from `main`; PRs target `main`. Trunk-based.
- Run `just check` before pushing (shellcheck + helm lint + template).
- Conventional Commits (`feat:`, `fix:`, `docs:`, ...).
- Claims about behavior must be executed, not extrapolated. Label
  untested translations as such; that honesty is a design value here.
- beads and Dolt bugs belong upstream (gastownhall/beads,
  dolthub/dolt). We track the ones that shape callbook in
  [charter.md](charter.md) F6; feel free to add pointers.

## Style

Plain, specific language. No marketing words. No em dashes.
