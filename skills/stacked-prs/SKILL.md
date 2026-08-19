---
name: stacked-prs
description: Use when a branch is too large or too risky to land as one pull request - a month-long revamp, a migration (npm to pnpm, TypeScript upgrade), or any branch with hundreds of commits or changed files that must reach main without landing half-working code. Also use when asked about stacked PRs, dependent PRs, gh stack, splitting or carving a branch into layers, keeping a stack rebased after review feedback, or merging a stack.
---

# Stacked PRs

## Overview

A stack is a chain of pull requests. Each PR targets the branch below it, not the
trunk. A reviewer sees one layer at a time. The trunk receives the layers bottom
up.

GitHub has this natively since 2026-07-30 (public preview). The `gh stack` CLI
extension does the cascading rebase, the base retargeting and the atomic merge.
**Do not hand-roll the rebase chain.** Older guides that tell you to
`git rebase` each child and `git push --force-with-lease` describe the era before
this feature. Use them only as the fallback in `references/manual-fallback.md`.

Two jobs, both covered here:

| Job | You have | Go to |
|---|---|---|
| **A - Build a stack** | Nothing yet. You are about to start a large change. | [Job A](#job-a---build-a-stack-from-scratch) |
| **B - Carve a stack** | One fat branch, weeks of commits, huge diff vs trunk. | [Job B](#job-b---carve-a-fat-branch-into-a-stack) |

Job B is the harder one and the reason this skill exists. Its full recipe is in
`references/carving.md`.

## Step 0 - Is this a stack at all?

Stack only when the layers are **dependent**. Independent work goes in parallel
PRs off the trunk, which is simpler and always the default.

| Signal | Verdict |
|---|---|
| Layer 2 does not compile without layer 1 | Stack |
| One change, split only to make review easier, but each part builds alone | Parallel PRs |
| Two people own two parts and will work at the same time | Parallel PRs - a stack serialises them |
| A migration: toolchain, then codegen, then callers | Stack |
| Cross-fork contribution | **Cannot stack.** GitHub stacks need all branches in one repo. |

## Step 1 - Pick the trunk

The trunk is what the bottom PR targets. Ask this one question:

> Will the layers merge one at a time over days, with the trunk deployed in
> between? Or will the whole stack land in one shot?

| Answer | Trunk | Why |
|---|---|---|
| **All at once** | `main` (or the repo default) | `gh stack merge` is atomic and all-or-nothing. Merge the top PR and every layer below lands in one operation. The trunk never holds a half-done revamp, so an integration branch buys nothing. |
| **One at a time** | A long-lived integration branch, e.g. `release/v2` | Each layer merges as it passes review. The trunk stays whole. One final PR takes the integration branch to `main`. |
| Unsure | `main`, all at once | Fewer moving parts. You can always cut an integration branch later. |

Set it with `gh stack init --base <trunk>`.

## Step 2 - Make CI run on the stack (do this first)

**Most repos do not run CI on a stacked PR, and say nothing about it.** A
workflow filtered to the trunk only fires for PRs whose base is the trunk. In a
stack, exactly one PR has that base. Every layer above it shows no checks at all.

```yaml
# breaks a stack: only the bottom PR gets CI
on:
  pull_request:
    branches: [main]

# works: a PR into any base branch gets CI
on:
  pull_request:
```

Check before you build anything:

```bash
grep -rn -A4 'pull_request' .github/workflows/ | grep -B1 -A3 'branches'
```

If any required workflow is filtered, fix it **first**:

| Option | When |
|---|---|
| Its own small PR straight to the trunk, merged before the stack opens | Preferred. The whole stack then has CI from its first push. |
| The bottom layer of the stack | You cannot merge to the trunk separately. It is a good bottom layer - tiny, obviously safe, and it unblocks every layer above. |

This matters more than it looks. Branch protection and required checks are
evaluated per layer, so a layer whose checks never ran either cannot merge, or
merges having verified nothing. Either way invariant 2 stops being enforced by
anything except you running it locally.

## Job A - Build a stack from scratch

```bash
gh stack init --base main feat/001-schema      # bottom layer, trunk = main
# ...work, commit...
gh stack add feat/002-api      -Am "API on the new schema"
gh stack add feat/003-ui       -Am "UI on the new API"
gh stack view                                   # see the chain
gh stack submit                                 # push all, open all PRs, link the stack
```

`gh stack add` branches off the current top, so the chain is correct by
construction. `gh stack submit` opens an editor to title and describe every PR at
once; `--auto` skips it and creates drafts.

Naming: the GitHub stack UI already shows the order, so branch names are free to
say **what** rather than **where**. Both work:

- Semantic - `ci/run-on-stacked-prs`, `migration/docs-and-hygiene`,
  `design/v2-token-consumption`. Reads well in `git branch` and in review.
- Ordinal - `feat/001-schema`, `feat/002-api`. Order survives outside the UI, in
  logs and in Slack.

Pick one and hold it across the stack. Do not mix.

## Job B - Carve a fat branch into a stack

You have `feat/big-revamp`: one month, hundreds of commits, a huge diff. Do not
try to split it by commit ranges. Interleaved history almost never groups into
layers that each build.

**Split by paths, not by commits.** Full recipe, ordering rules, worked example
and the escape hatches: `references/carving.md`.

The short version:

0. **Fix CI first** (Step 2). Verifying layers locally and then opening seven
   PRs with no checks is the most common way a stack gives false comfort.
1. **Bring the fat branch current with the trunk.** Merge the trunk in. Do not
   rebase - a month of commits will fight you.
2. **Inventory the diff** by top-level path and size.
3. **Measure the import direction between candidate layers** - do not assume it.
   Both directions means a cycle, and a cycle means one layer.
4. **Write a layer plan** - a text file, one line per layer, bottom to top:
   `<branch-name><TAB><pathspecs>`. Order it so each layer builds without the
   ones above it: config and toolchain, then leaf packages, then their consumers,
   then deletions and renames. Backend work has its own ladder - see
   `references/backend-layers.md`.
5. **Carve** with `scripts/carve-stack.sh`. For each layer it branches off the
   previous one and copies exactly those paths out of the fat branch.
6. **Verify** both invariants below.
7. `gh stack init` the branches bottom to top, then `gh stack submit`.

The fat branch stays untouched on disk the whole time. It is your reference copy
and your undo.

## The two invariants

These are the whole point. A stack that fails either one is worse than the fat
branch, because it looks reviewed.

**Invariant 1 - the stack reproduces the branch, exactly.**

```bash
git diff --stat feat/big-revamp..<top-of-stack>   # must print nothing
```

Anything printed is a path your layer plan missed. Add a layer, or widen one.
Never wave it through.

**Invariant 2 - every layer is green on its own.**

Check out each branch in the stack and run the repo's real gate - install, build,
typecheck, test. `scripts/verify-stack.sh` walks the stack and prints a table.

A layer that is red is the bug the stack exists to prevent. Fix it by moving
paths between layers or by folding two layers together
(`gh stack modify`). Do **not** fix it by adding code that is not in the fat
branch - that breaks invariant 1.

Run both before `gh stack submit`. Not after.

## Living with a stack

| Situation | Command |
|---|---|
| Trunk moved, or you want the stack current | `gh stack sync` |
| Review feedback on a middle layer | Commit on that branch, then `gh stack sync` |
| Rebase conflict | `gh stack rebase`, fix, `gh stack rebase --continue` |
| Reorder, rename, drop or fold layers | `gh stack modify` (then `gh stack submit`) |
| Where am I | `gh stack view` |
| Move around the stack | `gh stack up` / `down` / `top` / `bottom` / `switch` |
| Pull someone else's stack | `gh stack checkout <pr-number>` |

`gh stack sync` fetches, fast-forwards the trunk, cascade-rebases every branch
onto its parent, pushes with `--force-with-lease --atomic`, and relinks the stack
on GitHub. It is the one command to run at the start of every session on a stack.

**Commit the fix on the layer that owns it.** A fix committed on the top branch
for a bug that lives in layer 1 makes layer 1 ship broken and the layers between
it unreviewable.

## Merging

```bash
gh stack merge            # interactive: pick how far up to merge, and the method
gh stack merge 42         # merge everything up to and including PR #42
gh stack merge --yes --squash
```

Facts that change how you plan:

- **Atomic.** Every PR up to your chosen one merges in one all-or-nothing
  operation. If one cannot merge, none do.
- **Bottom up only.** You cannot merge a middle PR alone; everything below comes
  with it.
- **Partial merges retarget themselves.** Merge the lower layers and the next
  unmerged PR is rebased onto the stack base automatically. No manual retarget.
- **Auto-merge does not work on stacks.** Do not plan around it.
- **Merge queues do work.** The stack enters the queue.
- **Branch protection and required checks still apply**, per layer. Bypassing
  merge requirements is not supported for stacks. This is the feature, not a
  limitation.

## Gotchas

| Thing | Reality |
|---|---|
| Cross-fork stacks | Not supported. All branches must live in the same repo. |
| GitHub Desktop | Not supported. |
| Public preview | Behaviour can change. Re-read `gh stack <cmd> --help` before trusting a flag. |
| `gh stack submit` in a non-interactive shell | Skips the editor, creates **drafts** with generated titles. Pass `--open` for ready-for-review. |
| Squash merge on the trunk | Fine. `gh stack sync` handles the SHA rewrite. Do not rebase by hand to "help". |
| Deep stacks | Every layer is a review someone must do. Above roughly 6 layers, reviewers stop. Fold. |
| CI silent on every layer but the bottom | The workflow is filtered to the trunk. See Step 2. |
| You based the stack on a non-default branch, then linked it | **`gh stack link` retargets the bottom PR to the repo default branch**, and GitHub then refuses to change it back: *"Cannot change the base branch because the pull request is part of a stack."* A native stack's bottom always targets the trunk. If the stack must not point at `main`, you cannot use the native stack UI - chain plain PRs instead. |
| `commit-msg hook exited with code 1` while carving | The repo runs commitlint or husky and the generated message is not conventional. Pass `--type <feat\|fix\|chore\|refactor>` to `carve-stack.sh`. Do not reach for `--no-verify`. |
| The fat branch after carving | Keep it. Do not delete it until the stack is merged. It is the proof of invariant 1. |

## Red flags - stop

- About to `git rebase` a child branch by hand. Use `gh stack sync`.
- About to `git push --force` (without `--with-lease`) on a stack branch.
- `git diff trunk..<top>` is not empty and you are about to submit anyway.
- A layer does not build and you are about to write new code to fix it.
- Splitting by commit range because the paths "look messy".
- Deleting the fat branch to "clean up" before the stack lands.
- Submitting a stack whose CI is filtered to the trunk, so only the bottom PR
  has checks.
- Pushing or opening PRs without the repo owner asking you to. Carving and
  verifying are local and reversible. Pushing is not.

## Quick reference

| Task | Command |
|---|---|
| Start a stack | `gh stack init --base <trunk> <branch>` |
| Adopt existing branches, bottom to top | `gh stack init b1 b2 b3` |
| Add a layer | `gh stack add <branch> -Am "msg"` |
| Open / update all PRs | `gh stack submit` |
| Refresh everything | `gh stack sync` |
| Restructure | `gh stack modify` |
| Merge | `gh stack merge` |
| Link PRs made by other tools | `gh stack link <pr> <pr> <pr>` |
| Undo the stack, keep the PRs | `gh stack unstack` |

Install if missing: `gh extension install github/gh-stack`

## Files

- `references/carving.md` - splitting a fat branch: the full method
- `references/backend-layers.md` - backend order: migration, contract, implementation, routing
- `references/gh-stack.md` - command reference and flags
- `references/manual-fallback.md` - plain git + gh, when `gh stack` is unavailable
- `scripts/carve-stack.sh` - build the branches from a layer plan
- `scripts/verify-stack.sh` - check both invariants

Installed from [kelaskills](https://github.com/wicolian/kelaskills). To make a
repo-specific version, copy the folder into that repo's `.claude/skills/` and add
a `references/<repo>.md` with its branches, trunk choice and verify command.
