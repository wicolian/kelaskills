---
name: sync-main
description: Use when a long-lived redesign or refactor branch has to absorb work that other people keep shipping to main - running the merge, telling a real gap from a false positive, deciding whether a mainline fix needs porting into a redesigned twin file, resolving a recurring merge conflict, or auditing whether a branch is still main-compliant. Also use when a parity or drift checker reports everything is fine and you do not believe it.
---

# Syncing main into a long-lived branch

One person on a redesign branch. Several people shipping to `main`. This skill is
the ritual that keeps the two from silently diverging.

Architecture - where code goes, how v1 and v2 coexist, how to extract shared
logic - is in [references/parallel-redesign.md](references/parallel-redesign.md).
Read that first when the question is placement. This file is cadence, execution,
and what to believe.

## The hazard, stated once

**A mainline fix lands in the v1 file, merges clean, and leaves the redesigned
twin stale, with no conflict and no signal.**

The merge is not the risk. The merge is what hides the risk. Git resolved
everything it was asked to resolve. Nobody asked it about the twin, because the
twin is a different file.

So a sync is two layers, and only one of them is `git merge`:

| Layer | What | Signal if you skip it |
|---|---|---|
| **A** | Merge `origin/main` in, resolve, tag the catch-up point | Loud. Conflicts, red builds. |
| **B** | Port each mainline fix into the redesigned twin | **Silent.** Everything is green and the bug is back. |

**Layer A without Layer B is not a sync.** If you cannot finish B, say so in the
log rather than tagging and moving on. An unfinished sync that looks finished is
worse than one that was never started.

## Cadence: session start, on a clean tree

Run the sync at the **start** of a work session, never right before pushing.

At pre-push time the tree is dirty, the sync refuses (correctly), and the
temptation is to stash. Do not. A stash window collides with anything else
touching the tree, and the work vanishes with no trace. Commit or discard.

Make the sync script assert the branch it expects, so running it from the wrong
checkout aborts before it merges anything.

## Do not trust a parity checker that never says no

The usual attempt at automating Layer B is a script that diffs `main`, pulls
identifiers out of the added lines, and greps for them on the branch. It reports
"ported" or "absent".

**Audit it before you rely on it.** The failure mode is specific and it looks
like success:

| Symptom | What it means |
|---|---|
| Every row scores `PORTED` | It has never emitted a negative. It cannot. |
| Aggregate "match" is 98%+ | It is matching English, not code. |
| It has never found a real gap | Correct - and it never will. |

A real audit of one such tool: the probe extracted `/\b[a-z][A-Za-z0-9]*\b/g`
from raw `+` lines and tested membership in a 45,000-word bag drawn from the
whole tree, comments and string literals included. It scored the words
`unnecessary`, `associated` and `expressions` out of a lint pragma as ported
code. Because it anchors on `[a-z]`, **every component, class and exported type
was invisible to it**. Precision across every finding it ever produced: 0 of 23.

A green gate that has never gone red has not measured anything. Check when it
last failed before you believe it.

## The detector that actually works

New exported symbols on `main` that exist nowhere on your branch. That is the
whole thing, and it needs no API:

```bash
git diff $(git tag -l 'sync/main-*' --sort=-creatordate | head -1)...origin/main -- src \
  | grep '^+' \
  | grep -oE 'export (const|function|async function|class|type|interface) [A-Za-z_$][A-Za-z0-9_$]*' \
  | awk '{print $NF}' | sort -u \
  | while read -r s; do
      git grep -q "$s" -- src || echo "ABSENT-FROM-BRANCH: $s"
    done
```

**A new exported function in a shared helper is the highest-signal finding there
is.** It means the seam exists on `main` and nothing on your branch plugged into
it.

## Telling a real gap from a false positive

Most flags are not gaps. These five classes are what a legitimate
reimplementation produces, and all five will trip a naive checker:

| Class | Example | Why it is not a gap |
|---|---|---|
| Local variable | `showClientCol` | Function-scoped. The twin does the same thing inline, or under another name. |
| CSS-module class | `gridDisplay` | A styling identifier, not behaviour. |
| Test-id string literal | `"create-filter-switch"` | The twin builds test ids from a helper, so a literal match can never succeed. |
| Renamed in the twin | `showData` -> `shouldShowData` | Same predicate, different name. |
| Moved code | appears on both `-` and `+` lines | Nothing was added. |

**Judge a PR's real size from `git diff -w`.** On a repo with line-ending churn a
PR that reads `+1670/-1553` is routinely 30 real lines, and one reading 2,697
changed lines in a single file is 133. Deciding what to port from raw line counts
wastes a day per sync.

## The standard: rewrite, don't line-port

When a mainline fix and the redesign touch the same behaviour, **do not copy the
mainline diff into the redesigned twin.**

1. **Prefer extracting the shared logic into a module both twins import.** This
   is the highest-leverage move available. Every extraction permanently removes a
   future porting job, and it is why most mainline PRs end up needing no port at
   all.
2. **When a twin must own it, write it in the branch's own language** - its
   tokens, its component primitives, its language version. Do not import the old
   idiom along with the fix.
3. **Never resolve a conflict by taking one side wholesale** when both sides
   added behaviour. Keep your extraction layer *and* take their rename.
4. **Wire what you port.** The single worst defect found in one real audit was a
   file whose stylesheet had been rewritten properly and then never imported -
   invented class names on live elements, whole surfaces rendering with no layout
   at all. The work was done. The halves were never joined. Grep for the import.
5. **Log every behavioural change in the same commit that makes it.** A ledger
   row added later is a row nobody trusts, and absence only carries information
   if the file is complete.

## Conflict resolution by file type

| File | Resolution |
|---|---|
| Source | Normally. In the redesign tree the redesign usually wins; in the legacy tree the incoming change is usually the fix. Union when both added behaviour. |
| `package.json` | Keep **both** sides' dependencies. |
| Lockfile | Never by hand. Fix `package.json`, re-run install, let the package manager rewrite it. That clears the conflict. |
| A lockfile your branch deleted, modified by them | `deleted by us, modified by them` after a bot PR. **Keep the deletion.** Restoring it puts two lockfiles side by side and your install guard can no longer tell a wrong install from a right one. |

Then install and build before committing the merge.

## Before you trust any gate

Gates rot quietly. Before concluding a branch is clean, confirm each one **starts**:

- A linter with an unknown key in its config exits on the config error. Every
  script that calls it, and every pre-commit hook behind those scripts, becomes a
  silent no-op. Undefined classes and dead imports ship through a green board.
- A boundary or parity test that has been red long enough stops being read.
- A checker that has never failed (above).

`<lint command> && echo STARTED` is a five-second check and it has caught this
more than once.

## Report honestly

State how many candidates were ported, skipped, or already shared; which files
you edited; and anything you could not finish.

A silent skip here ships a bug that production already fixed. That is the exact
failure the whole ritual exists to prevent.

## Files

- `references/parallel-redesign.md` - where code goes: v1/v2 coexistence, logic
  extraction, CSS bundle split, rollout models, harvesting an existing branch
- `references/porting-checklist.md` - the per-candidate loop, as a checklist
