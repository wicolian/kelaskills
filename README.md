# kelaskills

Agent skills I actually use. Mostly the unglamorous kind — how to land a huge
branch, how to keep a redesign from silently drifting off `main`, how to QA a web
app while you sleep.

Every skill here is **generic**. Nothing is tied to one employer's repo, hosts, or
customers. Where a skill needs a project-specific value, it names the variable and
lets you fill it in.

## The skills

| Skill | Use it when |
|---|---|
| [**stacked-prs**](skills/stacked-prs) | A branch is too big or too risky to land as one PR. Build a stack, or carve an existing fat branch into one. Built around GitHub's native `gh stack`. |
| [**sync-main**](skills/sync-main) | A long-lived redesign branch has to absorb what everyone else keeps shipping to `main`, without the redesigned twins silently going stale. |
| [**overnight-dev**](skills/overnight-dev) | You want a web app taken from "probably fine" to "verifiably usable" unattended, with a report waiting in the morning. |
| [**cc-fleet**](skills/cc-fleet) | A job is bigger than one context and you want each worker visible in its own pane, not hidden in a headless subagent. |
| [**switch-env**](skills/switch-env) | Point a local dev server at a different backend without touching `.env`, and survive the auto-restart that trips people up. |
| [herdr](skills/herdr) | Pointer only — that skill ships with [herdr](https://github.com/herdr-dev) itself. |

## Install

Skills are plain folders with a `SKILL.md`. Symlink the ones you want:

```bash
git clone https://github.com/wicolian/kelaskills.git ~/src/kelaskills

# Claude Code
ln -s ~/src/kelaskills/skills/stacked-prs ~/.claude/skills/stacked-prs

# cross-runtime (Codex, Copilot CLI, Gemini CLI also read this path)
ln -s ~/src/kelaskills/skills/stacked-prs ~/.agents/skills/stacked-prs
```

Or install all of them:

```bash
./install.sh              # symlinks every skill into ~/.claude/skills
./install.sh ~/.agents/skills
```

Symlinks rather than copies, so `git pull` updates what your agent reads.

To share one with a team, copy it into that repo's `.claude/skills/` instead —
then it travels with the code and everyone gets it.

## What makes a skill here

Three rules I hold myself to:

1. **It has to have cost me something.** Every one of these exists because a
   specific failure was expensive. The z-index ladder, the parity checker that
   never says no, the dev server that serves a broken bundle while `curl` says
   200 — those are receipts, not theory.
2. **The scripts have to run.** Anything in a `scripts/` folder has been executed
   against a real repo, not just written.
3. **No numbers I did not measure.** Where a skill cites a result, someone ran it.

## Licence

MIT. Take what is useful.
