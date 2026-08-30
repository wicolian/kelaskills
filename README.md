# kelaskills

Agent skills I actually use. Mostly the unglamorous kind: how to land a huge
branch, how to keep a redesign from silently drifting off `main`, how to QA a web
app while you sleep.

Every skill here is **generic**. Nothing is tied to one employer's repo, hosts, or
customers. Where a skill needs a project-specific value, it names the variable and
lets you fill it in.

The skill format and bundled scripts support Claude Code, Codex, Cursor, Hermes
Agent, Pi coding agent, and T3 Code. T3 Code runs the selected provider CLI, so a
skill is installed for that provider rather than into a separate T3-only folder.

| Runtime | User skill location |
|---|---|
| Claude Code | `~/.claude/skills/` |
| Codex | `~/.codex/skills/`, or `$CODEX_HOME/skills/` |
| Cursor | `~/.cursor/skills/` |
| Hermes Agent | `~/.hermes/skills/` |
| Pi coding agent | `~/.pi/agent/skills/`, or `$PI_CODING_AGENT_DIR/skills/` |
| Cross-runtime and T3 providers | `~/.agents/skills/` plus the selected provider location |

## The skills

**Start here:** [**setup-kelaskills**](skills/setup-kelaskills) installs the pack,
verifies the agent can actually see it, tells you which skill to reach for, and
diagnoses the usual "it did not fire" causes. Ask an agent to "install
kelaskills" and it is the skill that knows how.

### Landing code

| Skill | Use it when |
|---|---|
| [**stacked-prs**](skills/stacked-prs) | A branch is too big or too risky to land as one PR. Build a stack, or carve an existing fat branch into one. Built around GitHub's native `gh stack`. |
| [**sync-main**](skills/sync-main) | A long-lived redesign branch has to absorb what everyone else keeps shipping to `main`, without the redesigned twins silently going stale. |
| [**file-pr**](skills/file-pr) | Your agent can already open pull requests. It opens ones humans hate. Lead with the problem in the user's own words, title the symptom and not the code, and open a real PR so the reviewers actually run. |
| [**babysit-pr**](skills/babysit-pr) | Drive a PR to green without letting review feedback triple its size. Act only on feedback newer than the last push, verify every automated finding against source, and refuse scope creep out loud. |

### Running agents

| Skill | Use it when |
|---|---|
| [**graph-engineering**](skills/graph-engineering) | A job has many similar subtasks, a plan is about to be written as "first X, then Y, then Z", or a previous run went out of context. Turn it into a dependency graph: fan out, gate on blast radius, return the unit and not the batch. Includes the wiring for Claude Code, Codex, Cursor, Pi, LangGraph and Google ADK, and a 200-line runner with no framework. |
| [**agent-fleet**](skills/agent-fleet) | A job is bigger than one context and you want each worker visible in its own pane. Pane-to-pane handoff, one-question escalation, worktree isolation. |
| [**blackout-proof**](skills/blackout-proof) | A long unattended run has to survive a usage limit, a spend cap, or a crashed CLI. The watchdog, the backoff, and the handoff that means you don't lose the night. |
| [**overnight-dev**](skills/overnight-dev) | You want a web app taken from "probably fine" to "verifiably usable" unattended, with a report waiting in the morning. |

### Tuning your agents

| Skill | Use it when |
|---|---|
| [**agent-retro**](skills/agent-retro) | Stop guessing which instruction your agents need. Mine your own session transcripts for the mistakes they actually make, count them per model and per harness, and turn the top few into config changes you can verify. |
| [**agents-md**](skills/agents-md) | Write the instructions file an agent reads before it changes a codebase. Most are a README with a different name, which is the wrong job. The glossary, the non-negotiables, the surface checklist, and the ways an agent hurts itself here. |
| [**skill-authoring**](skills/skill-authoring) | Your skill never fires, or fires on everything. The `description` is a trigger, not a description: it is loaded into every conversation whether or not the skill runs, and one detailed enough to be useful on its own means the body never loads. |
| [**fleet-sync**](skills/fleet-sync) | Several machines, all running agents, all needing the same skills. Do not build a sync system. One git repo of markdown, a little scoping metadata, and a dry run before anything is applied. |

### Lenses

Tags you add to a skill you were already running. See [Tags](#tags) below.

| Skill | Use it when |
|---|---|
| [**skill-tags**](skills/skill-tags) | A skill invocation carries a trailing `-tag`. The composition rules, the fixed phase order, conflict resolution, and a resolver that runs. |
| [**context-archaeology**](skills/context-archaeology) | Lens `-why`. The code looks wrong and you cannot tell if it is a mistake or a scar. Recovers the reason from pull requests, incidents, chat threads, telemetry and meeting transcripts, and tells you plainly when the reason was never recorded. |
| [**right-question**](skills/right-question) | Lens `-ask`. Work is under-specified. Auto-answers what the evidence answers, merges what is left, and takes the human one batched round instead of twenty interruptions. |
| [**whatwillmattdo**](skills/whatwillmattdo) | Lens `-whatwillmattdo`. Holds every design decision and every gate to a stricter bar, distilled from [Matt Pocock's skills](https://github.com/mattpocock/skills). Routes to his originals when you have them installed. |
| [**obsidian-graph**](skills/obsidian-graph) | Lens `-obsidian`. Writes what a run learned back to a typed-edge vault, so the next run starts where this one ended instead of paying for the same discovery twice. |

### Odds and ends

| Skill | Use it when |
|---|---|
| [**setup-kelaskills**](skills/setup-kelaskills) | Install this pack, check the agent can see it, find the right skill, or work out why one is not firing. Also the preflight for what each skill needs wired before it works. |
| [**switch-env**](skills/switch-env) | Point a local dev server at a different backend without touching `.env`, and survive the auto-restart that trips people up. |
| [herdr](skills/herdr) | Pointer only; that skill ships with [herdr](https://github.com/herdr-dev) itself. |

## Tags

Four of the skills above are **lenses**. A lens is not something you run. It is
something you add to a skill you were already running, and it changes how that
run behaves.

```bash
/graph-engineering -why                 plan the work, after finding out why the code is like this
/overnight-dev -why -obsidian           QA overnight, skip the known bugs, write the new ones back
/stacked-prs -whatwillmattdo            carve the stack, held to a stricter bar
/agent-fleet -ask                       six workers, one question to the human
```

The one rule that keeps this from turning into soup: **a lens may add
constraints, evidence, questions or gates. It may never add scope.** If it makes
the agent do a different job, it is a second skill pretending to be a lens.

Lenses apply in a fixed phase order and ignore the order you typed them:

```
-why  ->  -ask  ->  [the skill itself, with -whatwillmattdo at its decisions]  ->  -obsidian
```

`-why` then `-obsidian` is the loop that makes the whole thing get smarter. This
run's dig becomes next run's starting context, so nobody pays for the same
archaeology twice.

Registry and the rules for writing one: [TAGS.md](TAGS.md).

## Install

Every skill is a plain folder with a `SKILL.md`. Three ways in.

### Ask an agent

If you already have one skill from this pack installed, or you point an agent at
this repository, say "install kelaskills". The
[setup-kelaskills](skills/setup-kelaskills) skill knows the runtime directories,
runs a preflight for what each skill needs wired, and checks afterwards that the
agent can actually see what it installed.

### npx (easiest)

```bash
# see what is in here, install nothing
npx skills@latest add wicolian/kelaskills --list

# one skill
npx skills@latest add wicolian/kelaskills --skill=stacked-prs

# all of them, for every agent it finds, no prompts
npx skills@latest add wicolian/kelaskills --all

# later
npx skills@latest update
```

Add `-g` to install at user level instead of into the current project. The
upstream `skills` CLI currently recognizes Claude Code, Codex, Cursor, Hermes
Agent, and Pi. T3 Code drives provider CLIs, so install for the provider selected
in T3 Code or use this repository's installer below.

### Symlink (if you want to edit them)

Clone once, then link the ones you want:

```bash
git clone https://github.com/wicolian/kelaskills.git ~/src/kelaskills

# Cross-runtime project or user location
ln -s ~/src/kelaskills/skills/stacked-prs ~/.agents/skills/stacked-prs
```

Or install all of them:

```bash
./install.sh                         # every supported agent
./install.sh --agent codex          # one agent
./install.sh --agent t3-code        # T3 Code provider locations
./install.sh ~/.agents/skills       # an explicit custom location
```

Symlinks rather than copies, so `git pull` updates what your agent reads.

To share one with a team, copy it into that repo's `.agents/skills/` so it
travels with the code and works across compatible runtimes. Pi also reads
`.pi/skills/`; Hermes reads `.hermes/skills/`; provider-specific directories
remain available when a runtime does not yet expose the universal location.

## What makes a skill here

Four rules I hold myself to:

1. **It has to have cost me something.** Every one of these exists because a
   specific failure was expensive. The z-index ladder, the parity checker that
   never says no, the dev server that serves a broken bundle while `curl` says
   200. Those are receipts, not theory.
2. **The scripts have to run.** Anything in a `scripts/` folder has been executed
   against a real repo, not just written.
3. **No numbers I did not measure.** Where a skill cites a result, someone ran it.
4. **No em-dashes.** Rewrite the sentence, never swap the character. Enforced by
   `./scripts/check-skills.sh`, which also validates skill frontmatter and the
   lens contract. Run it before opening a pull request.

## Credit

`whatwillmattdo` and the interview machinery inside `right-question` are a
distillation of [Matt Pocock's skills](https://github.com/mattpocock/skills)
(MIT). They are a lens over his published judgment, not a replacement for it, and
they route to his originals when you have them installed. Go read the source.

The em-dash ban is his convention too, and it is a good one.

## Licence

MIT. Take what is useful.
