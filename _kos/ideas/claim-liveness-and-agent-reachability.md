# Claim liveness: an address on the bead, not just an assignee

*Operator question, 2026-07-31. Pre-hypothesis. The measurements are real;
the designs are candidates.*

## The ask

An agent that picks up a bead registers an address in some way, so that
someone authorized to do so can reach it, get a heartbeat, and check whether
it is still actively working the task.

## Why it comes up now

Two things measured on the aae-orc store the same day:

- **A claim never expires.** `in_progress` has no lease and no heartbeat, so
  a claim from 49 days ago is indistinguishable from one from five minutes
  ago. `aae-orc-0jl` and `aae-orc-kbk0` have both been claimed since June 12.
- **A claim does not name an actor.** Every assignee is the human principal,
  whether the claimant was a workflow subagent, a concurrent session, or a
  person. So the tracker cannot say who to ask, let alone reach them.

There is also a reporting gap that hid the first problem: `bd stale` defaults
to `--limit 50` without ordering by status, so open issues crowd out claimed
ones. Measured 183 stale at 30+ days, being 181 open and 2 in_progress, and
the default view showed zero claims. Fixed locally in `aq stale`; the
underlying default is upstream's.

## Three things that get conflated

Worth separating before designing anything, because they have different costs
and different trust models.

1. **Attribution.** Who claimed this. Recorded after the fact. Tracked at orc
   as `aae-orc-mq76` and `_kos/ideas/harness-invocation-agent-identity.md`.
2. **Reachability.** Where I can contact them. An address.
3. **Liveness.** Whether they are still on it. A heartbeat, or a challenge
   with a response.

Attribution without reachability gives a name nobody can call. Reachability
without liveness gives an address that may be dead. Liveness without
authorization gives anyone who can read the tracker the ability to poke every
agent in the fleet.

## Why this belongs to callbook and not only to marvel

The orc already has `question-agent-service-directory`, which puts a
directory inside marvel and names liveness in its entry model and callbook
enrollment among its readers. That covers agents marvel orchestrates.

The gap is everything else. Beads claims come from actors marvel does not
orchestrate: a bare Claude Code session, a Codex run, a workflow subagent, a
human at a terminal. If liveness lives only in marvel's directory, every
claim made outside marvel has none, which is most of them today.

Charter F9's independence rule and SOUL §2 both say callbook never requires
marvel. That rules out a liveness story that depends on it. And it points at
the right carrier: the work item is the one artifact every actor touches
regardless of harness. Bind the address to the claim, not to the
orchestrator, and the design survives an agent that has no orchestrator.

Marvel then becomes an enrichment rather than a prerequisite. When marvel is
present it can register on the agent's behalf and answer challenges from its
own directory. When it is absent the claim still carries whatever the
claimant could offer.

## Candidate shapes

**Passive lease.** The claim carries a TTL. The claimant refreshes it while
working. No address, no protocol, no new transport. Answers "is this claim
alive" rather than "what are you doing." Expiry becomes observable, which is
the whole of the 49-day problem. Cheapest by a wide margin and expressible in
stock bd as a note convention plus a checker.

**Address on the claim.** The claim carries a contact URI: a NATS subject, an
`mrvl://` path, a switchboard session, a unix socket, a tmux pane address.
Enables ask instead of poll. Needs either a field or a note convention, and
it raises the question of what is reachable from where.

**Challenge and response.** An authorized party sends a nonce; the agent
answers with something only a working agent would know, such as the file it
currently holds, its last tool call, or a progress note. This is the only
shape that separates "the process is alive" from "the agent is still working
the task." A wedged agent heartbeats happily.

**Authorization.** Who may challenge. At minimum the human principal who owns
the store. In the fleet case a supervisor or director role. This is where the
idea touches the capability-token work (`aae-orc-mqwk`, biscuit). The failure
to avoid is that read access to the tracker becomes permission to interrogate
every agent in it.

**Escalation.** What happens when nobody answers: expire the claim, flag for a
human, notify the principal, reassign. Per ADR-007 and SOUL §8 the automation
may remind, check, and propose. It must not judge. Auto-unclaim is a
judgment; proposing an unclaim is not. Closure and reassignment stay human
acts.

## What stock bd can and cannot do

Charter F5 says not a fork today, and the fork trigger is the upstream path
stalling on something load-bearing. So the shapes above should be sorted by
how much they need from upstream.

Available now, no fork: notes, labels, the `Updated` timestamp,
`bd stale --status in_progress`. A lease is a note convention plus a checker
that reads it. An address is a note convention. Neither is enforced, both are
reported.

Not available: a lease field with expiry semantics, a hook that fires on
claim, per-actor identity distinct from the human assignee, any notion that a
claim can lapse on its own.

The fork or extension trigger is enforcement. Reporting a claim as expired
needs nothing from upstream. Making a claim actually lapse is storage
semantics and upstream has to want it. That is an issue to file before it is
a fork to cut, and it pairs naturally with the `bd stale` default-limit
report.

## Tensions to preserve

- **Sovereignty and observability, SOUL §1 and §6.** An address is both a
  telemetry surface and an attack surface. Local-first, opt-in, no
  phone-home. An agent that registers nothing must still be able to claim
  work, or the mechanism becomes conscription.
- **Independence, SOUL §2 and charter F9.** No dependency on marvel,
  director, or switchboard.
- **Not a PM methodology,** per the non-goals. This is liveness plumbing, not
  a standup ritual. Resist the slide into "agents report progress every N
  minutes," which measures compliance rather than liveness.
- **Self-reported liveness is still self-reported.** A heartbeat proves the
  agent believes it is working. That is the same trust model as an agent
  closing its own ticket, which the orc already has open as
  `closure-verification-and-dispute`. A challenge with a verifiable answer is
  stronger than a heartbeat for exactly this reason.

## Multi-human

Two humans, two factories, one store. Whose supervisor may challenge whose
agents? Cross-principal challenge is a consent question before it is an ACL
question, and it is the same boundary the deployment ladder walks. A
reasonable default is that a principal may challenge only their own actors,
and cross-principal challenge is granted, not assumed.

## Smallest first probe

The lease, with no address and no protocol and no fork. A claim writes a TTL
note; a checker reports claims past it; nothing auto-unclaims. That alone
would have surfaced `0jl` and `kbk0` on day 31 instead of day 49, and it
needs no agreement from upstream and no new transport.

If the lease earns its keep, the address is the next increment, and the
challenge is the one after that. Each is separately useful, which is the test
this project applies to everything else.

## Open

- Does the lease TTL belong to the claimant, the store, or the policy? An
  agent that knows it is starting a two-hour task wants a different TTL from
  one doing a five-minute edit.
- What refreshes the lease: the agent explicitly, or a hook on any bd write
  by that actor? The second is harder to forget, which is the argument for it.
- Is "still working" even answerable without reading the agent's context? A
  progress note is cheap and gameable; a current-file answer is verifiable
  and invasive.
- Does this want to be a callbook capability, an upstream bd feature, or a
  sidecar service that reads the store? The sidecar is the only one we can
  ship without anyone's agreement.
- How does an agent that dies mid-task differ, observably, from one that
  finished and forgot to close? Both look like a stale claim.

## Cross-references

- orc `question-agent-service-directory` (entry model names address and
  liveness; readers name callbook enrollment; registration lifecycle asks
  what happens on crash, shift, and adopt)
- orc `aae-orc-mq76` and `_kos/ideas/harness-invocation-agent-identity.md`
  (attribution, the sibling problem)
- orc `aae-orc-mqwk` (authorization substrate and capability tokens)
- orc `_kos/ideas/closure-verification-and-dispute.md` (self-reported
  closure, same trust model)
- callbook charter F5 (fork trigger), F9 (operational layers and the
  independence rule)
