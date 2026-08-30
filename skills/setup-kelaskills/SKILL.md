---
name: setup-kelaskills
description: Use when installing, verifying, updating or removing the kelaskills pack, or when picking which one of its skills fits the job in front of you. Triggers on "install kelaskills", "set up my skills", "set up this skill pack", "what skills do I have", "which skill should I use for this", "update my skills", "my skill is not firing", "nothing happened after I installed it".
---

# Set up kelaskills

The front door to `wicolian/kelaskills`. This installs the pack, proves the agent
can see it, says which skill to reach for, and names the wiring each one needs.
It does none of the pack's actual work.

## Install, three ways

Pick by what you intend to do with the files.

| You want to | Use |
|---|---|
| Read and run them, nothing more | `npx skills@latest add ...` |
| Run all of them from a clone you keep updated | `./install.sh` |
| Edit them, and have the edit live everywhere at once | Symlink a clone by hand |
| Keep several machines in step | Read [fleet-sync](../fleet-sync) instead |

### 1. npx, the default

```bash
npx skills@latest add wicolian/kelaskills --list             # look, install nothing
npx skills@latest add wicolian/kelaskills --skill=stacked-prs   # one skill
npx skills@latest add wicolian/kelaskills --all              # all, every agent found
npx skills@latest update                                     # later
```

`-g` installs at user level instead of into the current project. The upstream
`skills` CLI recognises Claude Code, Codex, Cursor, Hermes Agent and Pi. T3 Code
drives a provider CLI, so install for the provider T3 Code has selected, or use
`./install.sh` below.

### 2. `./install.sh` from a clone

```bash
git clone https://github.com/wicolian/kelaskills.git ~/src/kelaskills
cd ~/src/kelaskills

./install.sh                      # every supported agent
./install.sh --agent codex        # one agent, repeatable
./install.sh --agent t3-code      # the T3 Code provider locations
./install.sh ~/.agents/skills     # one explicit directory, then exit
./install.sh --help
```

What it really does, from the source:

- **It symlinks. It never copies.** `ln -sfn` per skill folder. A `git pull` in
  the clone updates what every agent reads.
- It installs only folders that contain a `SKILL.md`. `skills/herdr` is a
  pointer folder with a README and no `SKILL.md`, so it is skipped on purpose.
- If a **real directory** already sits at the target it prints `skip` and leaves
  it alone. An existing **symlink** is replaced without asking.
- `--agent` values accepted: `claude`, `claude-code`, `codex`, `cursor`,
  `hermes`, `hermes-agent`, `pi`, `universal`, `t3`, `t3-code`, `all`. Anything
  else prints the usage and installs nothing for that name.
- `all` writes to six directories. `t3-code` writes to four: the cross-runtime
  one plus Claude Code, Codex and Cursor. It honours `CODEX_HOME` and
  `PI_CODING_AGENT_DIR`.
- No arguments means `--agent all`. A first argument that does not start with
  `-` is treated as a destination directory, and nothing else runs.

### 3. Symlink a clone by hand

Right when you intend to **edit** the skills. Your edit is live in every runtime
the moment you save it, and `git pull` updates every machine.

```bash
ln -s ~/src/kelaskills/skills/stacked-prs ~/.agents/skills/stacked-prs
ln -s ~/src/kelaskills/skills/setup-kelaskills ~/.claude/skills/setup-kelaskills
```

The honest tradeoff: a symlink breaks the moment the clone moves or is deleted,
and some runtimes and file-sync tools do not follow symlinks. If a skill is
installed and still invisible, suspect this first and test with a copy.

## Verify it worked

This is the step people skip, and then wonder why nothing fires.

```bash
skills/setup-kelaskills/scripts/preflight.sh          # every runtime, live state
ls -l ~/.agents/skills/ ~/.claude/skills/             # by hand, an arrow means symlink
```

**Files on disk is not the test. The test is whether the agent can see them.**
Most runtimes read the skill directory once, at session start. A skill installed
into a session that is already running is usually invisible until you start a
new one. "I installed it and nothing happened" is almost always this.

The positive test, and it takes one minute:

1. Start a **new** session.
2. Type a phrase from a skill's description, in your own words, not the skill
   name. For example: `this branch is way too big to land as one PR`.
3. `stacked-prs` should load. If it does not, the install is fine and the
   description is wrong. See [skill-authoring](../skill-authoring).

## The map of the pack

### Landing code

| Skill | Reach for it when |
|---|---|
| [stacked-prs](../stacked-prs) | A branch is too big or too risky for one PR. Build a stack, or carve a fat branch into one. |
| [sync-main](../sync-main) | A long-lived redesign branch has to absorb what everyone keeps shipping to `main` without going stale, or a parity checker says fine and you do not believe it. |
| [file-pr](../file-pr) | "File a PR", "ship this branch", or writing the title and description. |
| [babysit-pr](../babysit-pr) | The PR is open. Drive it to green without letting review feedback triple its size. |

### Running agents

| Skill | Reach for it when |
|---|---|
| [graph-engineering](../graph-engineering) | A plan is about to be written as "first X, then Y, then Z", the job has many similar subtasks, or a previous run went out of context. Turn it into a dependency graph. |
| [agent-fleet](../agent-fleet) | The job is bigger than one context and each worker should stay visible in its own pane. Needs `HERDR_ENV=1`. |
| [blackout-proof](../blackout-proof) | A long unattended run has to survive a usage limit, a spend cap, or a crashed CLI. |
| [overnight-dev](../overnight-dev) | Take a web app from "probably fine" to "verifiably usable" unattended, with a report waiting in the morning. |

### Tuning your agents

| Skill | Reach for it when |
|---|---|
| [agent-retro](../agent-retro) | You are tuning agent config from memory. Mine your own transcripts for the mistakes your agents really make. |
| [agents-md](../agents-md) | Writing or fixing the `AGENTS.md` or `CLAUDE.md` an agent reads before it changes a repo. |
| [skill-authoring](../skill-authoring) | A skill never fires, or fires on everything. The `description` is a trigger, not a summary. |
| [fleet-sync](../fleet-sync) | Several machines all need the same skills and instructions, and keep drifting apart. |
| setup-kelaskills | This one. Install, verify, route, diagnose. |

### Lenses

A lens is not run alone. You add it to a skill you were already running.

| Skill | Tag | Reach for it when |
|---|---|---|
| [skill-tags](../skill-tags) | | An invocation carries a trailing `-tag`, two tags conflict, or you are writing a new lens. |
| [context-archaeology](../context-archaeology) | `-why` | The code looks wrong and you cannot tell a mistake from a scar. |
| [right-question](../right-question) | `-ask` | The work is under-specified and the agent is about to guess or interrogate. |
| [whatwillmattdo](../whatwillmattdo) | `-whatwillmattdo` | Every decision and gate should be held to a stricter bar. |
| [obsidian-graph](../obsidian-graph) | `-obsidian` | The run should write what it learned back to a vault, so next week is cheaper. |

### Odds and ends

| Skill | Reach for it when |
|---|---|
| [work-order-report](../work-order-report) | An audit or sweep must produce something an agent can act on rather than read. One browsable HTML with a built-in tracker. |
| [switch-env](../switch-env) | A local dev server has to point at a different backend, and the auto-restart keeps serving stale values. |
| [herdr](../herdr) | Pointer only. That skill ships with herdr itself and is not vendored here. |

Derived from each skill's own `description`. If `ls skills/` shows a folder that
is not here, it landed after this was written. Read its `SKILL.md`.

## Tags, the short version

A tag is a lens. It changes **how** a skill runs, never **what** it is for.

```bash
/graph-engineering -why                 plan the work, after finding out why the code is like this
/overnight-dev -why -obsidian           QA overnight, skip the known bugs, write the new ones back
/stacked-prs -whatwillmattdo            carve the stack, held to a stricter bar
```

**The one rule: a lens may add constraints, evidence, questions or gates. It may
never add scope.** If it makes the agent do a different job, it is a second skill
pretending to be a lens.

Phases are fixed and ignore the order you typed:
`before -> decisions -> gates -> after`.

Resolve a stack, and see how many times the run may interrupt a human:

```bash
skills/skill-tags/scripts/tag-resolve.sh --list
skills/skill-tags/scripts/tag-resolve.sh overnight-dev -why -obsidian
```

The rules, conflict resolution and the ask budget: [skill-tags](../skill-tags)
and [TAGS.md](../../TAGS.md).

## What needs extra wiring, and what degrades

Markdown alone is not enough for these. When the wiring is missing the failure is
usually silent or, worse, misleading.

| Skill | Needs | Without it |
|---|---|---|
| [context-archaeology](../context-archaeology) | `git` always works. `gh` installed and authenticated. Chat, error tracking, product analytics, meeting transcripts and session recordings each need their own MCP server. | A dig reports "no recorded reason" when it simply could not reach three of the places a reason lives. Read [its sources reference](../context-archaeology/references/sources.md) before trusting a zero. |
| [obsidian-graph](../obsidian-graph) | A vault path in `VAULT_DIR`. | It writes the same notes to a local directory in the repo and prints where. It never silently skips the write. |
| [agent-fleet](../agent-fleet) | `HERDR_ENV=1`. It only works inside herdr. | Nothing to spawn into. Use `graph-engineering` with headless subagents instead. |
| [file-pr](../file-pr), [babysit-pr](../babysit-pr) | `gh`, authenticated. | No fallback. Say so and stop. |
| [agent-retro](../agent-retro) | Local agent transcripts on disk. | Nothing to count. It also carries a privacy warning: a transcript is a recording of your work, so never upload one and never quote one unredacted. |
| [overnight-dev](../overnight-dev) | A running app to QA, and a deploy target if you want the deployed check. | Local checks only, and it must say the deployed check was skipped. |

The MCP bridge into Obsidian only runs while the desktop app is open on that
vault. There is no headless Obsidian. Treat the filesystem path as the normal
one and MCP as a bonus.

`scripts/preflight.sh` checks the ones a shell can see: `git`, `gh` and whether
it is authenticated, `python3`, `node`, `HERDR_ENV` and `VAULT_DIR`. It says what
each missing thing disables, never prints a token, and never prints the body of
`gh auth status`. MCP servers cannot be checked from a shell.

## Update and uninstall

```bash
npx skills@latest update          # an npx install
git -C ~/src/kelaskills pull      # a clone, symlinked or installed by install.sh
```

A clone needs nothing after `git pull`. The symlinks already point at it. Start a
new session so the runtime re-reads the directory.

To remove, delete the entry in each runtime directory you installed into:

```bash
ls -l ~/.agents/skills/stacked-prs         # an arrow means it is a symlink
rm    ~/.agents/skills/stacked-prs         # a symlinked install
rm -rf ~/.agents/skills/stacked-prs        # a copied install
```

**If you symlinked, delete the link and not the clone.** `rm` on the link path
removes the link only, but a trailing slash or an editor "delete folder" can
follow it into the clone and take your edits with it. Run `preflight.sh` after
removing; it lists every runtime directory, so it finds the copy you forgot.

## Troubleshooting

| Symptom | Usually | Do |
|---|---|---|
| The skill never fires | The session started before the install | Start a new session and try again |
| Still never fires | The description does not match how you phrase it | Read [skill-authoring](../skill-authoring). Write five real phrasings, test each |
| It fires when it should not | The description is too broad | Same skill. Run `skills/skill-authoring/scripts/lint-descriptions.sh skills` |
| A bundled script fails | Wrong interpreter, or bash 4 syntax | macOS ships bash 3.2. No associative arrays, no `${x^^}`. Scripts here are read-only by convention, so a script that wants to write is a bug |
| A tag is not recognised | It is not a registered lens, or the pack is half installed | `skills/skill-tags/scripts/tag-resolve.sh --list` |
| Installed, but the wrong runtime | The runtime reads a different directory | `preflight.sh`, then [references/runtimes.md](references/runtimes.md) |
| Edits do not take effect | Two copies installed and drifting: a symlinked clone in one directory and an `npx` copy in another | `preflight.sh` shows real directory versus symlink per runtime. Delete the copy, keep the link |

## Contributing back

```bash
./scripts/check-skills.sh
skills/skill-authoring/scripts/lint-descriptions.sh skills
```

The first is the gate: frontmatter, folder-name match, the lens contract, script
syntax, and the em-dash ban. Run it before opening a pull request. The second is
a judgement call and not a hard failure.

Four house rules:

- **No em-dashes.** Rewrite the sentence, never swap the character.
- **Anything in `scripts/` has been executed** against something real. Written
  but never run does not ship.
- **Generic only.** No employer, customer, internal project or person. Name the
  variable and let the reader fill it in.
- **No numbers nobody measured.**

Writing a skill: [skill-authoring](../skill-authoring). Writing a lens:
[skill-tags/references/lens-template.md](../skill-tags/references/lens-template.md),
then add a row to [TAGS.md](../../TAGS.md).
