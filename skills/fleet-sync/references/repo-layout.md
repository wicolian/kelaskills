# Fleet repository layout

The full shape, the metadata schema, a filled-in inventory, and the two
procedures you will run again and again.

## The worked layout

```
fleet/
  AGENTS.md
  fleet.md
  README.md
  skills/
    universal/
      repo-hygiene/SKILL.md
      pr-review/SKILL.md
      release-notes/SKILL.md
      registry-publish/SKILL.md
    claude-only/
      pane-fleet/SKILL.md
    codex-only/
      codex-review-loop/SKILL.md
    control/
      fleet-provision/SKILL.md
      fleet-audit/SKILL.md
  agents/
    AGENTS.base.md
    AGENTS.build-box.md
  scripts/
    fleet-plan.sh
    fleet-apply.sh
    fleet-drift.sh
```

Notes on the parts that are not obvious:

- `agents/` holds the instruction files you distribute, kept apart from the
  skills so an apply step can install one without the other. `AGENTS.base.md`
  goes everywhere. A per-role file is appended on the machines that need it.
- `scripts/` holds the apply machinery. Only `fleet-plan.sh` is safe to run
  anywhere at any time, because it is the only one that does not write.
- There is no `secrets/`. There is never a `secrets/`.

## AGENTS.md at the root

You edit this repository with an agent, so the repository has to explain itself.
A short version that carries the load:

```markdown
# What this repository is

The source of truth for agent skills and instructions on every machine in the
fleet. It contains markdown and small shell scripts. Nothing else.

# How to change it

- A new skill goes in `skills/universal/` unless it needs a specific agent CLI
  (then `<runtime>-only/`) or it can reach another machine (then `control/`).
- Every skill declares `targets`. Add `requires` when it needs a binary or an
  environment variable.
- A new machine gets a row in `fleet.md` before any skill targets it.

# Never

- Never commit a token, a key, a `.env`, or any credential file.
- Never put a skill that provisions or reconfigures machines outside `control/`.
- Never add conditionals or inheritance to the metadata. Two flat keys only.
- Never write an apply step that deletes without printing a plan first.
```

## Metadata schema

Two keys, added to the frontmatter a skill already has. Flat on purpose.

```yaml
---
name: registry-publish
description: Use when ...
targets: [universal]
requires:
  bins: [gh, rg]
  env: [PACKAGE_REGISTRY_TOKEN]
---
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `targets` | list of strings | the tier directory the skill sits in | Tier names or machine names. The skill installs where any one matches. |
| `requires.bins` | list of strings | empty | Executables that must be on `PATH`. Checked with `command -v`. |
| `requires.env` | list of strings | empty | Environment variables that must be set and non-empty. Names only. |

Both list forms parse:

```yaml
targets: [universal, control]
```

```yaml
targets:
  - universal
  - control
```

Rules the schema depends on:

- A missing requirement means **do not install**, not install and warn.
- `requires.env` names a variable. It never carries a value.
- No conditionals, no inheritance, no expressions. If you want "universal except
  the sandbox", list the machines, or add a tier.

## Filled-in machine inventory

`fleet.md`, using invented names. Pick a naming scheme with no meaning attached
so a machine can change role without a rename.

```markdown
# Fleet

| Machine | Role | Reach | Specs | Tiers | Deliberately absent |
|---|---|---|---|---|---|
| ash-laptop | Daily driver, control node | mesh VPN, hostname `ash-laptop` | 10 core, 32 GB, 1 TB | universal, control, claude-only | No GPU builds. No long unattended runs, the lid closes. |
| oak-bench | Heavy builds and long runs | mesh VPN, hostname `oak-bench` | 24 core, 128 GB, 4 TB | universal, codex-only | No control tier. No browser QA, there is no display. |
| fern-box-01 | Remote worker | ssh over the private network | 8 core, 16 GB | universal | No control tier. No publishing credentials. |
| fern-box-02 | Remote worker | ssh over the private network | 8 core, 16 GB | universal | Same as fern-box-01. |
| moss-sandbox | Ephemeral cloud box, rebuilt weekly | provider CLI | 4 core, 8 GB | universal | Nothing persistent. No credentials of any kind. |

## Per-machine notes

### ash-laptop
Control node. The only machine that holds `control/`. Holds the fleet
repository at `~/fleet`. Skills are symlinked.

### oak-bench
Runs the long jobs. Skills are symlinked. `codex-only` because that is the
runtime installed here.

### moss-sandbox
Rebuilt from scratch every week, so apply runs at boot. Skills are **copied**,
not symlinked, because the repository checkout is not guaranteed to outlive the
apply. Requirement checks remove most of the skill set here, which is correct.
```

Keep the "deliberately absent" column. It is the difference between an agent
knowing a gap is a decision and an agent helpfully filling it.

## Procedure: detect drift

Run this whenever a machine behaves differently from the one next to it.

1. On the target machine, `git -C <fleet-repo> pull --ff-only`. If that fails,
   stop. You are about to compare against a stale truth.
2. Resolve the expected set:
   `scripts/fleet-plan.sh --repo <fleet-repo> --tier <tiers> --machine <name> --runtime <runtime>`
3. List what is actually in the runtime skill directory, one name per line.
4. Compare in both directions and write three lists:
   - **Missing.** Expected, not on disk. Usually a failed or skipped apply.
   - **Unknown.** On disk, not expected. Someone added it by hand, or a tier
     changed and nothing cleaned up.
   - **Different.** In both, but the content does not match. A local edit, or a
     copy that never got refreshed. For a symlink, check the link target too, not
     just that the name exists.
5. Report all three. A drift report that only shows "missing" hides the case
   that actually bites, which is a machine holding a skill nobody sanctioned.

Do this on every machine, not just the one that misbehaved. The machine that
looks fine is where the unknown skill has been sitting for six weeks.

## Procedure: reconcile drift

The repository is the source of truth. Every difference resolves toward it.

1. **Missing.** Re-run apply. If it stays missing, the requirement check is
   removing it. Read the skip reason before you install it by hand, because the
   skip is usually right.
2. **Different, and the machine's copy is a stale copy.** Re-apply. If you are
   using symlinks this case cannot happen, which is one reason to prefer them.
3. **Different, and the machine's copy is a local edit.** Somebody improved it in
   place. Move the edit into the repository, then re-apply. Do not overwrite it
   without reading it first.
4. **Unknown.** Two ends, and only two:
   - **Adopt.** Move it into the repository, give it a tier and metadata, commit,
     then re-apply so the machine gets the repository's copy.
   - **Remove.** Delete it from the machine.

   **The human picks.** An agent may propose, with a one-line reason per skill.
   It may not decide, and it may not delete on its own initiative.
5. Re-run the drift check. It must come back clean. If it does not, apply is not
   idempotent and that is the bug to fix, not the drift.

## Procedure: bring up a new machine

1. Add the row to `fleet.md` first. Role, reach, specs, tiers, what is
   deliberately absent. This is the definition of "correct" for that machine.
2. Install the agent runtimes by hand, or with a provisioning routine a human has
   read end to end.
3. Clone the fleet repository.
4. `scripts/fleet-plan.sh` with that machine's tiers. Read the plan. The skip
   list tells you what the machine is still missing, which is usually a binary
   you forgot.
5. Apply. Diff. Apply again. The second diff must be empty.
6. Record anything you did by hand in the provisioning routine, then run that
   routine against the next fresh machine and watch what it gets wrong.
