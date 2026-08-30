# Runtimes

Where each supported runtime reads skills from, and what bites.

**How to read the confidence marks.** Anything marked **stated** comes from this
repo: the install table in `README.md` or the `destinations_for()` case statement
in `install.sh`. Anything marked **unverified** is the common behaviour but was
not confirmed against that runtime's own documentation while writing this page,
so a check command is given instead of a claim. Trust the repo over this page,
and trust the runtime's own docs over both.

## The user-level table

**Stated**, from `README.md` and confirmed against `install.sh`:

| Runtime | User skill directory | Env override |
|---|---|---|
| Claude Code | `~/.claude/skills/` | none |
| Codex | `~/.codex/skills/` | `CODEX_HOME`, so `$CODEX_HOME/skills/` |
| Cursor | `~/.cursor/skills/` | none |
| Hermes Agent | `~/.hermes/skills/` | none |
| Pi coding agent | `~/.pi/agent/skills/` | `PI_CODING_AGENT_DIR`, so `$PI_CODING_AGENT_DIR/skills/` |
| Cross-runtime and T3 providers | `~/.agents/skills/` | none |

`./install.sh --agent all` writes to all six. `./install.sh --agent t3-code`
writes to four: `~/.agents/skills/`, `~/.claude/skills/`, the Codex directory,
and `~/.cursor/skills/`.

`scripts/preflight.sh` prints this table with the live state of each directory.

## The project-level table

**Stated**, from `README.md`: to share a skill with a team, copy it into that
repo's `.agents/skills/` so it travels with the code and works across compatible
runtimes. The README also states that Pi reads `.pi/skills/` and Hermes reads
`.hermes/skills/`.

**Stated**, from `README.md`: `npx skills@latest add ...` installs into the
**current project** by default, and `-g` switches it to user level. So an install
with no `-g` puts files under the repo you are standing in, not under `~`.

**Unverified**: the project directory for Claude Code, Codex and Cursor. The
common convention is the dot-directory of the runtime inside the repo, for
example `.claude/skills/`, but this page does not assert it. Check it like this:

```bash
# what did the installer actually create in this repo
npx skills@latest add wicolian/kelaskills --skill=skill-tags
git status --porcelain --untracked-files=all | grep skills
```

The paths that appear are the paths that runtime uses. That is a stronger answer
than anything written here.

## Per runtime

### Claude Code

| | |
|---|---|
| User directory | `~/.claude/skills/` (**stated**) |
| Project directory | **unverified**, see the check above |
| Discovery | Reads the skill directory and holds every `description` in context. The body loads only when the skill fires. **Stated** in [skill-authoring](../../skill-authoring). |
| Restart | Assume yes. `install.sh` itself prints "Restart your agent so it re-reads the skills directory." |
| Quirk | Also the runtime `agent-retro` knows best: transcripts at `~/.claude/projects/**/*.jsonl`, one file per session, with subagent transcripts in a `subagents/` subdirectory. |

### Codex

| | |
|---|---|
| User directory | `~/.codex/skills/`, or `$CODEX_HOME/skills/` (**stated**) |
| Project directory | **unverified**, see the check above |
| Discovery | **unverified** |
| Restart | Assume yes |
| Quirk | `CODEX_HOME` is honoured by `install.sh` but is read at install time. If you export it after installing, the earlier install is in the old location and `preflight.sh` will report the new one as empty. |

### Cursor

| | |
|---|---|
| User directory | `~/.cursor/skills/` (**stated**) |
| Project directory | **unverified**, see the check above |
| Discovery | **unverified** |
| Restart | Assume yes |
| Quirk | `agent-retro` expects Cursor transcripts at `~/.cursor/projects/**/agent-transcripts/**/*.jsonl`. |

### Hermes Agent

| | |
|---|---|
| User directory | `~/.hermes/skills/` (**stated**) |
| Project directory | `.hermes/skills/` (**stated**, from `README.md`) |
| Discovery | **unverified** |
| Restart | Assume yes |
| Quirk | none known |

### Pi coding agent

| | |
|---|---|
| User directory | `~/.pi/agent/skills/`, or `$PI_CODING_AGENT_DIR/skills/` (**stated**) |
| Project directory | `.pi/skills/` (**stated**, from `README.md`) |
| Discovery | **unverified** |
| Restart | Assume yes |
| Quirk | The user path has an extra segment. It is `~/.pi/agent/skills/`, not `~/.pi/skills/`. The project path has no `agent` segment. Getting these two the wrong way round is the easy mistake. |

### T3 Code

| | |
|---|---|
| User directory | None of its own. **Stated**, from `README.md`: T3 Code runs the selected provider CLI, so a skill is installed for that provider. |
| How to install | `./install.sh --agent t3-code`, which covers `~/.agents/skills/` plus the Claude Code, Codex and Cursor locations. |
| Quirk | The upstream `skills` CLI does not recognise T3 Code (**stated**, from `README.md`). Install for the provider T3 Code has selected, or use `install.sh`. |

### Cross-runtime (`~/.agents/skills/`)

| | |
|---|---|
| User directory | `~/.agents/skills/` (**stated**) |
| Project directory | `.agents/skills/` (**stated**, and the README's recommendation for sharing with a team) |
| Discovery | Whatever the reading runtime does. This directory is a convention several runtimes agree on, not a runtime of its own. |
| Quirk | The `herdr` skill that `agent-fleet` depends on lands here, installed by herdr itself with `npx skills update`. Do not vendor a copy. |

## Symlinks

`install.sh` symlinks. It never copies. That is the whole reason a `git pull` in
the clone updates every runtime at once.

Two failure modes, both **unverified per runtime** and both worth knowing:

1. **Some runtimes and file-sync tools do not follow symlinks.** If a skill is
   installed, `preflight.sh` shows it as a symlink, and the agent still cannot
   see it, replace that one link with a copy and test again. If the copy works,
   that runtime does not follow links.
2. **A symlink breaks when the clone moves.** Nothing warns you. The link is
   still listed by `ls`, it just points at nothing.

```bash
# find broken links in a runtime directory
find ~/.agents/skills -maxdepth 1 -type l ! -exec test -e {} \; -print
```

## Restarting

`install.sh` ends with "Restart your agent so it re-reads the skills directory."
Take that as the rule for every runtime on this page. A skill installed into a
session that is already running is usually invisible to that session, and the
symptom is silence, not an error.

The check that settles it: start a new session and type a phrase from the
skill's description in your own words. If it fires, discovery works. If it does
not, the description is the problem, not the install. See
[skill-authoring](../../skill-authoring).
