# finding-008: dolt write-throughput envelope per project instance; ~18 mutating ops/s per instance, the ceiling is the process-per-op client, claims are exactly-once under race

Date: 2026-08-16
Status: measured (isolated scratch instance; see honesty notes)
Task: aae-orc-8cfh6. Answers finding-003's to-measure section and
charter F10's throughput open item; sizes pattern 5's "breaks first:
per-project write throughput" claim.

## Method

Throwaway `dolt sql-server` (Dolt 2.2.3, `autocommit: true`, loopback
127.0.0.1:29965, own data dir and cfg dir under the session scratchpad,
max_connections 150). Throwaway bd project (bd 1.1.2 Homebrew) at
`~/probe-8cfh6/proj2`, initialized `bd init --server --external
--server-host 127.0.0.1 --server-port 29965 --server-user root`, env
overrides `BEADS_DOLT_SERVER_PORT=29965`, `BEADS_DOLT_PASSWORD=""`,
`BEADS_DOLT_AUTO_START=false` on every invocation (the production
client-env exports 3307 values into every shell). Proof gate before
every cell: `bd context` must resolve to 127.0.0.1:29965 or the
harness aborts. Production (3307/aae_orc) was never written; verified
before and during the run.

Workload: each op is one `bd` CLI invocation (create with unique
title, or update with `--append-notes`), the shape a fleet of
one-shot agent commands produces. N parallel workers, each under a
distinct `BEADS_ACTOR`. Per-op wall time captured around each
invocation; ops/s = total ops / cell wall clock; dolt commit delta
read from `dolt_log` before/after each cell; server CPU/RSS sampled
at 1s.

## Numbers

| cell | writers | ops | ops/s | p50 | p95 | fails | dolt commits | srv peak |
|---|---|---|---|---|---|---|---|---|
| off, sequential | 1 | 200 | 4.9 | 192ms | 202ms | 0 | 200 | 20% / 169MB |
| off, parallel | 4 | 120 | 17.7 | 208ms | 252ms | 0 | 120 | 89% / 203MB |
| off, parallel | 8 | 120 | 18.1 | 411ms | 622ms | 0 | 104 | 161% / 254MB |
| off, parallel | 16 | 128 | 16.2 | 1022ms | 1306ms | 0 | 84 | 207% / 327MB |
| on, parallel | 4 | 120 | 17.5 | 205ms | 290ms | 0 | 119 | 83% / 337MB |
| on, parallel | 8 | 120 | 16.9 | 492ms | 642ms | 0 | 101 | 176% / 386MB |
| on, parallel | 16 | 128 | 15.1 | 1017ms | 1589ms | 0 | 89 | 180% / 456MB |
| batch, parallel | 4 | 120 | 17.6 | 206ms | 242ms | 0 | 119 + 0.13s flush | 80% / 472MB |
| batch, parallel | 8 | 120 | 17.5 | 417ms | 643ms | 0 | 106 + 0.21s flush | 156% / 522MB |
| batch, parallel | 16 | 128 | 16.2 | 988ms | 1234ms | 0 | 84 + 0.14s flush | 230% / 594MB |
| updates (off) | 8 | 120 | 16.8 | 478ms | 486ms | 0 | 120 | 195% / 631MB |

Ceiling (raw SQL through one bd process): a single 500-row INSERT
statement completed in 0.17s (~2,970 rows/s, zero dolt commits; rows
land in the working set). 100 single-row INSERTs as separate `bd sql`
invocations: 7.0 ops/s (~143ms each), i.e. the per-invocation floor
without any issue-model work.

Claim contention (5 rounds, 8 racers per round on one bead): every
round produced exactly one winner (exit 0) and seven losers, each
with a clean, named error: `Error claiming <id>: issue already
claimed by racer1`. Final state every round: single assignee,
status in_progress. Zero double-claims, zero corruption.

## The envelope

1. **One instance sustains ~17-18 mutating bd ops/s aggregate**, on
   this hardware, regardless of writer count or commit policy.
   Concurrency past ~4 writers converts to latency, not throughput:
   p50 climbs 192ms (solo) to ~210ms (4 writers) to ~450ms (8) to
   ~1s (16), p95 ~1.3-1.6s at 16. Saturation is graceful: zero
   failures in 1,304 measured ops; the server queues rather than
   errors.
2. **The ceiling is the process-per-op client model, not dolt.** The
   dolt engine absorbed ~3,000 rows/s in one transaction; a bare
   `bd sql` invocation costs ~143ms before any work; a full
   `bd create` costs ~192ms solo. Fleet write throughput is bounded
   by bd CLI invocation overhead plus commit serialization, in that
   order.
3. **Commit policy is a no-op for one-shot invocations.** off/on/
   batch produced statistically identical throughput and latency,
   and `batch` still emitted per-op dolt commits: its deferral is
   per-process, and each bd process flushes on exit. Batching only
   pays inside a long-lived bd process, which a fleet of one-shot
   agent commands never has. Related observation: under concurrency
   the server coalesces anyway (84-106 dolt commits for 120-128 ops
   at 8-16 writers), so dolt-commit volume self-limits under load.
4. **At-most-one-claim holds under race, with clean loser
   semantics.** The pattern-5 premise (claims serialize at the write
   plane) is empirically true on stock bd 1.1.2: one winner, losers
   get a named error identifying the holder (and `--claim` is
   idempotent for the holder per bd's contract).

Fleet sizing corollary: at one write per agent per 30s, ~18 ops/s
supports ~500 agents per project instance on throughput alone; a
p50-under-500ms write SLO suggests keeping sustained concurrent
writers per instance in the single digits and letting bursts queue.
Network round trips (absent here) add latency per op but do not
change the serialization ceiling.

## Gotcha discovered en route (report before workaround, per rule)

`bd init` run in a directory that is not a git repository walks UP
past the intended project root, adopts the first ancestor `.beads/`
it finds, and rewrites metadata there. On this machine that ancestor
was the user-level `~/.beads/`, and init overwrote/created
`metadata.json`, `config.yaml`, `README.md`, `eventsData/`, pointing
the user-level dir at the scratch server (port 29965). Contaminated
files were quarantined to `~/.beads/probe-8cfh6-contamination/`
(moved, not deleted) and production was verified untouched
(3307/aae_orc resolves and answers). Prevention: `git init` BEFORE
`bd init` anchors resolution to the repo root. Also: bd refuses
`.beads` under /tmp paths ("unsafe location"), so throwaway projects
must live under $HOME. Candidate kit/doctor check for callbook F2
(the class matches the existing "host-specific pointer" sharp edge)
and a candidate upstream report.

## Honesty notes

- Loopback only; no TLS; no network RTT. A remote write plane adds
  per-op latency but the ~18/s serialization ceiling is server-side.
- Shared machine under real load (load avg 3.5-4.1; four sibling
  agents active). Numbers are conservative-side estimates of an idle
  box.
- Single hardware point (Apple Silicon workstation), Dolt 2.2.3,
  bd 1.1.2, root user, no password, autocommit on, ~1,300 issues and
  ~1,400 dolt commits accumulated by run end.
- Server RSS grew monotonically 169MB to 631MB across the run;
  unbounded-growth vs cache-warmup was not separated; worth watching
  in any long-lived deployment.
- Evidence: raw per-op latency files, cpu logs, server log, and the
  scratch data dir remain under the session scratchpad `8cfh6/`;
  throwaway project at `~/probe-8cfh6/` (left in place, no-deletion
  rule).

## Cross-references

- finding-003 (to-measure section), finding-004 (claims need
  coordination; now measured), finding-005 (at-most-one-claim as the
  first invariant; now demonstrated under race), finding-006 (the
  1.1.2 agent surface), charter F10 (throughput open item: this
  closes the first measurement), patterns.md pattern 5 (the "breaks
  first" line can now cite ~18 ops/s per instance).
