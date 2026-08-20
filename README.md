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

| Skill | Use it when |
|---|---|
| [**stacked-prs**](skills/stacked-prs) | A branch is too big or too risky to land as one PR. Build a stack, or carve an existing fat branch into one. Built around GitHub's native `gh stack`. |
| [**sync-main**](skills/sync-main) | A long-lived redesign branch has to absorb what everyone else keeps shipping to `main`, without the redesigned twins silently going stale. |
| [**blackout-proof**](skills/blackout-proof) | A long unattended run has to survive a usage limit, a spend cap, or a crashed CLI. The watchdog, the backoff, and the handoff that means you don't lose the night. |
| [**overnight-dev**](skills/overnight-dev) | You want a web app taken from "probably fine" to "verifiably usable" unattended, with a report waiting in the morning. |
| [**agent-fleet**](skills/agent-fleet) | A job is bigger than one context and you want Claude Code, Codex, Cursor, Hermes, Pi, or a T3 Code provider visible in its own pane. |
| [**switch-env**](skills/switch-env) | Point a local dev server at a different backend without touching `.env`, and survive the auto-restart that trips people up. |
| [herdr](skills/herdr) | Pointer only; that skill ships with [herdr](https://github.com/herdr-dev) itself. |

## Install

Every skill is a plain folder with a `SKILL.md`. Two ways in.

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

Three rules I hold myself to:

1. **It has to have cost me something.** Every one of these exists because a
   specific failure was expensive. The z-index ladder, the parity checker that
   never says no, the dev server that serves a broken bundle while `curl` says
   200. Those are receipts, not theory.
2. **The scripts have to run.** Anything in a `scripts/` folder has been executed
   against a real repo, not just written.
3. **No numbers I did not measure.** Where a skill cites a result, someone ran it.

## Licence

MIT. Take what is useful.
