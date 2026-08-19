---
name: blackout-proof
description: Use when a long unattended agent run has to survive the thing that kills it - a usage or rate limit, a spend cap, a crashed CLI, a closed laptop. Triggers on "run overnight", "let me sleep", "I'm going out of town", "what happens if I hit the limit", "keep going without me", "it stopped at 3am and I lost the night", or before starting any programme longer than one quota window. Covers the survival tiers, the watchdog, blackout detection and backoff, self-regenerating reports, and the resume handoff.
---

# Blackout-proof long runs

## The one law

**Anything that runs inside the agent session dies with the agent session.**

A quota blackout does not pause your run. It ends the process that was driving
it. Background tasks, in-session schedulers, the orchestrator's own plan - all
gone, at the moment you are least able to notice.

So every guarantee you want in the morning has to live **outside** the session.
That is the whole skill. Everything below is a consequence.

## Survival tiers - know what actually outlives what

| Mechanism | Survives the session ending? | Survives herdr quitting? | Survives a reboot? |
|---|---|---|---|
| A background task the agent started | **no** | no | no |
| An in-session scheduler (`CronCreate` and friends) | **no** | no | no |
| A shell loop in a terminal pane | **yes** | no | no |
| A `setsid` / `nohup` detached process | yes | **yes** | no |
| A user LaunchAgent (macOS) or systemd timer | yes | yes | **yes** |

Most people stop at tier 3, get through one blackout, and conclude they are
covered. They are covered against the session dying and nothing else.

**Pick your tier from what you are actually away from.** Asleep at your desk with
the machine on: tier 3 is enough. Out of town, or a machine that might reboot for
an update: you need tier 5.

An in-session scheduler is a **belt, never braces**. It is genuinely useful - if
the CLI survives, it resumes you instantly and cheaply. It just cannot be the
thing you are relying on, because the case it needs to handle is the case that
kills it.

## Know which limit you hit. They reset differently.

This is the mistake that costs a whole night: scheduling a wake-up for a reset
that is not coming.

| Limit | Typical reset | A 03:00 wake-up helps? |
|---|---|---|
| Session / 5-hour window | rolling, a few hours | **yes** |
| Weekly cap | a fixed weekday | only if that is the day |
| **Monthly spend cap** | the billing date | **no. You wake into the same wall.** |
| Per-minute rate limit | seconds | you do not need cron, just backoff |

A watchdog with backoff handles all four correctly, because it retries until the
wall goes away rather than guessing when. A fixed cron wake-up only handles the
first. **That asymmetry is why the watchdog is the load-bearing part and cron is
the convenience.**

Before you go dark, write down which limit you are near and what its reset
actually is. `/usage` in the CLI, or your account's usage page.

## The three things to leave running

```
watchdog        restarts an orchestrator when the fleet empties and work remains
report loop     regenerates the status page from artifacts, every few minutes
usage monitor   a pane showing /usage, so a human glancing at the screen knows
```

```bash
scripts/preflight.sh                  # refuse to go dark until this is green
scripts/watchdog.sh   &               # tier 3; use install-launchd.sh for tier 5
scripts/refresh-loop.sh 180 ./make-report.sh &
```

The watchdog is the only one that matters if everything else dies. Keep it
boring: a `while` loop, `sleep`, and one command. **No agent, no CLI you have not
tested, nothing that needs a quota to decide whether it should run.**

## Derive the report. Never transcribe it.

**The status page must be generated from the artifacts on disk, not written by
the agent as it goes.**

An agent that transcribes progress into a document is a lossy log. The moment it
goes dark, the document freezes at the last thing it happened to write down, and
in the morning you read a number that was true hours ago.

Real measurement from one run: the transcribed count said 65 done. Regenerating
from the worker report files said **83**. Eighteen tasks had finished and been
lost to the blackout. Nobody would have known.

So:

- Each worker's last act is to write its own report file and `touch` a `.done`
  marker beside it.
- The report generator counts `.done` files. It does not ask anyone.
- It runs on a loop, so the page is fresh whether or not anything is driving it.
- Tag anything the generator discovered on its own, so a human can see which
  results arrived while the lights were off.

The test: **kill the orchestrator, wait five minutes, reload the report. If the
number moved, the report is honest.**

## Idempotent resume, or the watchdog makes it worse

A watchdog that restarts an orchestrator is only safe if starting an
orchestrator twice is harmless.

- **Take a lock.** One orchestrator at a time, enforced by the filesystem, not by
  hope. `scripts/watchdog.sh` uses an atomic `mkdir` lock.
- **Keep task state on disk, not in context.** A ledger with one row per task and
  a state. The resume prompt reads it; it never reconstructs from a transcript.
- **Make every task re-runnable.** A task that half-ran must be safe to run
  again, or it must record that it is unsafe.
- **Cap the restarts.** A crash loop respawning an orchestrator every ten minutes
  for six hours burns your quota on nothing. Stop after N and say so in the log.

## What must never be automated

The watchdog can restart work. It must never be able to ship it.

- **No publish.** Not a package, not a release, not a workflow dispatch.
- **No push, no PR**, unless the human authorised that specific thing before
  leaving.
- **No destructive git.** No force-push, no branch deletion, no history rewrite,
  no `stash` while a fleet is running.
- **No version bumps.**

Work that needs a human decision gets **held**, not guessed: leave it
uncommitted, snapshot it, and write down in the handoff exactly what is held and
what would unblock it. "I wasn't sure so I picked one" is the worst possible
thing to read at 8am.

Snapshot every uncommitted tree before going dark:

```bash
git diff HEAD > artifacts/snapshots/$(git branch --show-current)-$(date +%H%M).patch
```

## Before you go dark

`scripts/preflight.sh` checks these and exits non-zero on any miss:

- [ ] Which limit are you near, and when does it actually reset?
- [ ] Watchdog running, with its PID printed and a heartbeat file being touched
- [ ] Report loop running, and the report regenerates with the orchestrator dead
- [ ] `RESUME.md` written, and it names the first thing to do
- [ ] Task ledger on disk, one row per task, states current
- [ ] Uncommitted trees snapshotted
- [ ] Held work listed, with the reason
- [ ] Nothing scheduled that could publish or push
- [ ] Disk space for hours more logs and screenshots

## In the morning, read in this order

1. **The report** - what got done, derived from artifacts.
2. **The held list** - what is waiting on you, and why.
3. **The watchdog log** - how many blackouts, how long, how many restarts. This
   is the only place the night's real shape is recorded.
4. **The findings file** - what the run learned that changes the plan.

## Red flags

- An in-session scheduler as the only guard.
- A status document the agent updates by hand.
- A wake-up time chosen for a reset you did not verify.
- A watchdog that can `git push`.
- No lock, so two orchestrators race and both commit.
- A resume prompt that says "continue where you left off" with no ledger.
- Reporting a clean night without opening the watchdog log.
- Going dark with a dirty tree and no snapshot.

## Files

- `scripts/watchdog.sh` - the load-bearing loop: lock, blackout backoff, restarts
- `scripts/preflight.sh` - refuse to go dark until the guards are real
- `scripts/refresh-loop.sh` - regenerate anything on an interval
- `scripts/usage-watch.sh` - a pane that shows quota state to a passing human
- `scripts/install-launchd.sh` - tier 5 on macOS, survives a reboot
- `references/resume-contract.md` - `RESUME.md`, the ledger, and the report shape
- `references/blackout-detection.md` - telling a quota wall from a real failure
