---
name: modernize
description: Use when the user says "modernize this PR", "rebase this old PR", "bring this PR up to date", "is this PR still needed", or "revive this stale branch".
---

# Modernize

Modernize the idea, not only the branch. A clean merge does not prove the PR still
belongs in the product.

Adapted from Theo Browne's [tstack](https://github.com/t3dotgg/tstack) (MIT), fitted
to our rules. Theo rebases and force-pushes with lease. **We never force push, not
even with lease.** We update by a merge commit, or by a new branch.

## Guardrails

- `git fetch origin` first: the PR branch, its base, and related branches.
- Dirty worktree, or one in use? Work in a new worktree.
- This grants updating the PR branch. It does not grant merge, close, a base change,
  or more scope.
- No PR comment unless the user asks. Comments go through `leaving-pr-comments`.

## 1. Find the intent

Record the PR URL, state, base, head branch, head SHA, author, checks, and reviews.
Read the title, body, linked issues, commits, threads and the full diff. Write the
smallest goal the PR was after, before you judge how it does it. Record the merge base.

## 2. See what changed around it

Read what landed on the base since the merge base. Search merged and open PRs that
touch the same code or behaviour. Ask:

- Is the same user problem already solved?
- Did APIs, types, schemas, or boundaries change under it?
- Would landing it bring back old behaviour, or make two ways to do one thing?
- Is the gain still worth what it costs to keep?

"No conflicts" does not mean "current".

## 3. Pick one

- **MODERNIZE:** goal useful, shape right. Update it.
- **REWORK:** goal useful, shape wrong. Write the smallest credible rewrite, and stop
  unless the user also asked for the rework.
- **CLOSE:** superseded, obsolete, or not worth it. Cite evidence and stop. Close it
  only when the user says so, and then with a comment that links what replaced it.

Age is not evidence. Sunk work is not a reason to keep a PR alive.

## 4. Update without losing intent (MODERNIZE)

1. In a new worktree at the PR head, `git merge origin/<base>`. Resolve each conflict
   by the PR's intent and the base's newer rules. A conflict that is a product or
   design disagreement: stop and pick again.
2. Read the final diff against the base. Nothing intended lost, nothing already
   landed brought back.
3. Run the focused checks. Tell real failures from ones that were there before.
4. Push normally. If the push is rejected, fetch and look again.

The history must be rewritten (author asks for a linear branch)? Push the rebased
commits to a **new** branch, open a new PR, and link it from the old one.

Never merge the PR here.

## Report

Lead with MODERNIZE, REWORK or CLOSE and why. Then: what changed on the base,
conceptual conflicts (or none), the update and push result, checks and results,
what is left, the PR link. Keep facts apart from judgment.
