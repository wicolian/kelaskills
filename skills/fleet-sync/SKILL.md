---
name: fleet-sync
description: Use when the same agent instructions and skills have to exist on several machines and keep matching. Triggers on "sync my skills across machines", "my laptop and desktop have different skills", "set up a new dev box", "provision a machine", "manage agent config on several machines", "which skills are on which machine", "my agents behave differently on the build box", "I keep copying my AGENTS.md around", or "how do I keep two laptops in step".
---

# Fleet sync

A laptop, a desktop that does the heavy builds, a couple of remote boxes, maybe
a cloud sandbox. Every one runs coding agents. Every one needs your agent
instructions and your skills. Keeping them in step by hand fails at about the
third machine.

## This is not agent-fleet

They sound alike and they solve opposite problems.

| Skill | Problem |
|---|---|
| `agent-fleet` | Many **agents**, one machine. Panes, spawning, watching, file ownership. |
| `fleet-sync` | Many **machines**, one configuration. Distributing skills and instructions. |

Six workers in six panes? Stop here and load `agent-fleet`.

## The one rule

**Do not build a sync system.**

The instinct is a daemon that watches directories and pushes deltas. It produces
a buggy program with an endless tail of edge cases: partial writes, clock skew,
conflict resolution, a machine that was asleep.

Your content is markdown. Markdown is text. Text is what git is for. So:

> A git repository of markdown plus a small amount of metadata, and a normal
> agent that applies it over ssh.

The repository is the source of truth. The apply step is ordinary work an agent
already knows how to do: pull, resolve, link, report.

## The repository shape

```
<fleet-repo>/
  AGENTS.md            what this repo is, and how an agent should change it
  fleet.md             the machine inventory
  skills/
    universal/         every machine gets these
    <runtime>-only/    only machines running that agent runtime
    control/           only the machine you drive everything from
  scripts/
```

`AGENTS.md` at the root is not decoration. You will edit this repository with an
agent, and an agent that does not know the tier rules will drop a control skill
into `universal/` and hand every worker the ability to reconfigure the fleet.

## Three tiers, and why

| Tier | Holds | Reason |
|---|---|---|
| `universal/` | The default. Most skills. | Anything that works on any machine belongs here. If you are unsure, it is universal. |
| `<runtime>-only/` | Skills bound to one agent CLI. | Some skills call a specific binary or rely on one runtime's behaviour. On a machine without that runtime they are dead weight that the agent will still try to use. |
| `control/` | Provisioning, fleet edits, anything that reaches another machine. | The machine you orchestrate from needs power the workers must not have. |

The control tier is the one with teeth. **Never let a worker machine hold a skill
that can reconfigure the fleet.** A compromised or confused worker with a
provisioning skill can rewrite every other machine. One machine holds that
capability, and you know which one.

## Scoping metadata

Each skill declares where it belongs and what it needs. Keep it small and in
frontmatter, in the style this repository already uses for extra keys.

```yaml
---
name: registry-publish
description: Use when ...
targets: [universal]        # or [control], or [codex-only], or named machines
requires:
  bins: [gh, rg]
  env: [SOME_TOKEN]
---
```

`targets``targets` takes a tier name or a machine name from the inventory. Omit it and the
skill inherits the tier of the directory it sits in.

The rule that makes the `requires` block worth having:
**if a requirement is missing on a machine, do not install the skill there.**

A skill that is present but cannot work is worse than an absent one. Absent, the
agent says it lacks that capability and does something else. Present and broken,
the agent loads it, follows it, hits a missing binary, and guesses. Half-working
is the failure mode to design against, not missing.

## The machine inventory

One file, `fleet.md`, listing every machine: role, how you reach it, rough specs, tiers, and what is deliberately absent.

| Machine | Role | Reach | Specs | Tiers | Deliberately absent |
|---|---|---|---|---|---|
| `ash-laptop` | Daily driver, control | mesh VPN, `ash-laptop` | 10 core, 32 GB | universal, control, claude-only | No GPU work |
| `oak-bench` | Heavy builds | mesh VPN, `oak-bench` | 24 core, 128 GB | universal, codex-only | No control tier, no browser QA |
| `fern-box-01` | Remote worker | ssh via the private network | 8 core, 16 GB | universal | No control tier, no secrets |
| `moss-sandbox` | Ephemeral cloud box | provider CLI, rebuilt weekly | 4 core, 8 GB | universal | Nothing persistent, no credentials |

Write the inventory down because an agent asked to set up or repair a machine
needs to know what "correct" looks like there. With no inventory it guesses, and
its guess is whatever the last machine looked like. The "deliberately absent"
column is the part people skip and then regret: without it, an agent sees a
missing skill and helpfully installs it.

Full worked layout, the metadata schema, and a longer inventory:
[references/repo-layout.md](references/repo-layout.md).

## Applying it

The apply step is a normal agent doing ordinary work over ssh.

1. Pull the fleet repository on the target machine.
2. Resolve which tiers that machine gets, from `fleet.md`.
3. Check each skill's `requires` against that machine.
4. Link or copy the resolved set into the runtime skill directories.
5. Report a diff.

Always dry-run first and print what would change. `scripts/fleet-plan.sh` does
exactly that, and nothing else.

```bash
scripts/fleet-plan.sh --repo ~/fleet --tier universal --machine oak-bench
scripts/fleet-plan.sh --repo ~/fleet --tier universal,control --runtime codex
```

It reads. It never copies, links, removes, or connects anywhere.

### Link or copy

Prefer symlinks into the runtime skill directories. An update then becomes
`git pull` rather than a re-copy, and there is no second copy to drift.

The tradeoff, honestly: symlinks break when the repository moves, and some
runtimes and file-sync tools do not follow them. On a machine you do not fully
control, copying is the safer default, at the cost of one extra step per update.

### Use the paths that already exist

Use the runtime skill locations from this repository's README install table.
Do not invent new ones.

| Runtime | User skill location |
|---|---|
| Claude Code | `~/.claude/skills/` |
| Codex | `~/.codex/skills/`, or `$CODEX_HOME/skills/` |
| Cursor | `~/.cursor/skills/` |
| Hermes Agent | `~/.hermes/skills/` |
| Pi coding agent | `~/.pi/agent/skills/`, or `$PI_CODING_AGENT_DIR/skills/` |
| Cross-runtime | `~/.agents/skills/` |

### Reuse install.sh where it fits

This repository's `install.sh` already symlinks a repository's skills into those
directories, handles the per-runtime paths, and refuses to overwrite a real
directory. Call it on the target machine for the plain case.

It does not do tiering, check requirements, or reach a remote machine. It
installs every skill in one repository into local runtime directories. Resolve
the tier and the requirements first, then hand it the resolved set, or link that
set yourself.

### Idempotence

Applying twice must be a no-op. This is the property that makes the whole thing
safe to run whenever you are unsure.

Check it: run apply, capture the reported diff, run apply again, and the second
diff must be empty. If the second run reports work, something in the apply step
is not comparing before it writes.

## Drift

The first install is easy. The real problem is the fifth machine six weeks later.

**Detect.** Compare the resolved set against what is on disk. Report both
directions:

- In the repository, missing on the machine. Usually a failed or skipped apply.
- On the machine, not in the repository. A skill someone added by hand.
- Present in both, but different. A local edit, or a stale copy.

The second direction is where the surprises live.

**Reconcile.** The repository is the source of truth, so an unknown skill on a
machine has two ends: adopt it into the repository with a tier and metadata, or
remove it from the machine. **The human decides which.** Never let the apply step
silently delete something a person put there on purpose.

## Bootstrapping a new machine

Worth stating plainly, because everyone tries it the other way first:
**do not write the provisioning script from imagination.**

1. Set one machine up by hand, the way you actually want it.
2. Have an agent read that machine's config files and shell history, and write
   down what was really done. Not what you meant to do. What happened.
3. Run that against a fresh machine.
4. Watch what it misses and what it does that it should not.
5. Correct it.

The second machine is where the script becomes real.

**Hard rule: a human reviews a provisioning routine before it runs anywhere.** It
installs software and edits shell configuration. Never run it unattended on first
use, and never let an agent write one and execute it in the same step.

## Secrets

Blunt, and not negotiable.

- The fleet repository holds markdown. It does not hold credentials.
- A skill references an environment variable **by name**. It never contains the
  value.
- If a machine lacks the variable, the skill is not installed there. That is
  what the `requires.env` block is for.
- Never commit a token. Never sync a credential file.

Where the value lives instead: a per-machine environment file outside the
repository, or the operating system keychain.

## What not to do

- **No bespoke sync daemon.** You will spend a month on conflict resolution that
  git already solved.
- **No config format with conditionals and inheritance.** Once a tier can extend
  another tier and override a field conditionally, you have written a programming
  language by accident, and it has no debugger.
- **Do not sync agent state, caches, or transcripts.** They are per-machine, they
  are large, and they often contain private content.
- **Do not push to every machine automatically on commit.** Apply is a deliberate
  act, run when you are watching. A commit is a draft.
