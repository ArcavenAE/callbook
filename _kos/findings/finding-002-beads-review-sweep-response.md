# finding-002: beads review-sweep response, the stack refreshed in one day

- **Date:** 2026-08-03
- **Status:** complete
- **Relates:** charter F6 (upstream gaps), aae-orc-9h3f (contribution anchor)

## Context

On 2026-08-02 the beads maintainer posted a consolidated review sweep
(reviews signed "codex-gpt-5.6-sol-high on behalf of matt wilkie",
05:37 to 06:20 UTC) across our open PR stack. A colleague's summary of
the sweep arrived first; we verified every claim against the live repo
before acting, and all six held, with one nuance: the "superseded"
approval on #5085 was a COMMENTED review whose prose supersedes the
earlier approval, so GitHub's reviewDecision still read APPROVED.

## What the sweep asked, and what we did (2026-08-03)

| PR | Review state | Our action |
|----|--------------|-----------|
| #5087 (init-only create) | approved; base conflict; refresh onto main and rerun checks | merged upstream main `1da3ac377`, head `7ce822d22`, MERGEABLE |
| #5086 (probe-first open) | do not merge independently; retires as carried by #5087 | deliberately nothing |
| #5085 (stored peer creds) | two seam fixes requested: URL binding, mutex over fallbacks | both fixed, head `fdfa7c2d0` |
| #5207 (route all remote verbs) | two gaps, both identical to the #5085 asks | refreshed onto corrected #5085, head `9f1a157b4`; zero PR-specific code needed |
| #5214 (actionable decrypt errors) | three gaps: short ciphertext bypasses the sentinel, plus the two #5085 asks | gap 1 fixed (`8ac97de65`), then refreshed onto corrected #5085 (`16146e7d2`) |
| #5215 / #5216 | approved, no findings | wait |
| #5178 (flag precedence) | fix-merge disposition, maintainer-side | wait |

The #5087 refresh was a semantic weave, not a textual merge: upstream
had landed its own provider-option mechanism (#4985, `ProviderOption` +
`WithPreview`) and moved database creation under the migration lock
(#5309, `WithLockedPreparation`) in the exact seam our PR occupies. We
folded our `WithCreateIfMissing` / `WithNoDatabaseBind` options into
upstream's mechanism and moved the probe-first policy inside the locked
preparation, so the PR now reads as extending upstream's plumbing
rather than duplicating it. One upstream test needed a contract update
(the lock-order mock gains the `SHOW DATABASES` probe between
`GET_LOCK` and `CREATE DATABASE`).

The #5085 fixes: a new `verifyPeerRemoteURL` fails closed before any
credential is installed when the live `dolt_remotes` URL diverges from
the stored peer row (or the remote is missing), and the plain-remote /
empty-credential fallback callbacks now run under `federationEnvMutex`.
Three regressions added: diverged-URL fail-closed, missing-remote
fail-closed, and env-fallback-does-not-observe-peer-credentials.

## What this teaches

1. **Stacked PRs concentrate review fixes at the seam.** The reviewer
   routed both shared defects to first-filed #5085 and asked the
   siblings to rebase. Fixing `withPeerAuth` once covered #5207's
   entire review with no PR-specific code, because #5207 only adds
   call sites through the seam. When we file stacked PRs, expect this
   consolidation and design the stack so the seam PR is the one we can
   fix fastest.
2. **"Maintainer-fix" dispositions accept contributor absorption.**
   The sweep assigned #5085 and #5178 to maintainer-side fixing, but
   nothing blocked us from carrying the #5085 fixes ourselves, and
   doing so unblocked three PRs at once instead of waiting on
   maintainer bandwidth. The #5214 review said it explicitly: "a
   request-changes review is unnecessary if maintainers absorb these
   fixes"; contributor absorption is the same consolidation from the
   other side.
3. **Upstream evolves under open PRs; fold, do not duplicate.** Two
   independent option mechanisms collided (#4985 vs ours). The
   resolution rule that worked: adopt upstream's names and shape, then
   re-express our policy inside it. The alternative (keeping our type
   and renaming theirs) would have inflated the diff against main and
   read as competition for the seam.
4. **Fork-PR CI needs a maintainer click.** All refreshed heads sit at
   `action_required` until someone approves workflow runs, so "refresh
   and rerun checks" completes only maintainer-side. Factor that into
   any "is this landable" read.

## Tooling friction (captured late; workaround in use)

CGO tests of `internal/storage/embeddeddolt` fail on this machine with
`fatal error: 'unicode/regex.h' file not found` (dolthub's
go-icu-regex compiles against ICU headers). Workaround, applied
2026-08-03 and needed for every local run:

```sh
export CGO_CFLAGS="-I$(brew --prefix icu4c@78)/include"
export CGO_CXXFLAGS="-I$(brew --prefix icu4c@78)/include"
export CGO_LDFLAGS="-L$(brew --prefix icu4c@78)/lib"
```

The upstream reviewer's environment failed the same way ("local build
blocked by missing unicode/uregex.h; no verdict"), which means locally
verified embeddeddolt tests are evidence upstream review could not
produce for itself. Worth keeping the recipe alive.

## Verification record

- #5087 branch: pure-Go build of the whole tree; 3 create-policy
  wiring tests; 8 external-provider end-to-end tests; full `uow` +
  `schema` packages; preview wiring tests; `go vet` clean.
- #5085 branch: all 7 `withPeerAuth` tests (4 existing + 3 new); full
  federation / sync / remote-verb suite; `go vet` clean.
- #5207 and #5214 branches: build + the same federation suite on the
  merged heads.
