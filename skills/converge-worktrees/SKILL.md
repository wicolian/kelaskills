---
name: converge-worktrees
description: Use when a work period ends with the code scattered across several worktrees, branches and open pull requests, and it has to land as one pull request per repo. Triggers on "commit and push everything", "get all my worktrees onto one branch", "converge my branches", "land the week's work", "I want one PR at the end", "several worktrees, one PR", or "I don't want to lose the PR descriptions".
---

# Converging scattered worktrees into one PR per repo

One person, several worktrees, work finished on different ports over several
days. The job is not "merge things". It is to end with **one pull request per
repo** that the trunk can take in a single click, without throwing away the
review descriptions you already wrote.

## This is not the other two

| Skill | Direction | Shape |
|---|---|---|
| [stacked-prs](../stacked-prs) | One big branch, split **outward** into layers | Many PRs, merged bottom up |
| [sync-main](../sync-main) | Trunk flows **into** one long-lived branch, repeatedly | A cadence, over weeks |
| **converge-worktrees** | Many scattered branches pulled **inward** into one | A single event, at the end |

Read those for their own jobs. This file assumes you have decided to converge.

## Name your branches first

Everything below uses two placeholders. Fill them in once, out loud, before you
touch anything.

| Placeholder | What it is |
|---|---|
| `<trunk>` | The branch pull requests actually merge into. Often the repo default, often not. |
| `<integration>` | The branch that collects your scattered work and opens the single PR into `<trunk>`. |

Two shapes exist and both are normal:

```
main --fork--> <integration> --PR--> <trunk>     repo with an integration branch
main --fork--> feat/*        --PR--> <trunk>     repo without one
```

A repo without an integration branch targets `<trunk>` directly, and your job is
to create `<integration>` for the length of the convergence and then delete it.
Never push to a protected or deployed branch by hand.

Gate commands are placeholders too: `<typecheck>`, `<tests>`, `<lint>`,
`<health>`. Do not guess them. Read the repo's own script definitions and its
agent instructions file first. If that file is thin or missing, [agents-md](../agents-md)
is the skill for fixing it, and doing so pays for itself on the next convergence.

## When not to use this

Convergence is overhead. Skip it when:

- **One branch, one PR.** Nothing to converge. Open the PR.
- **Two or three commits on a single worktree.** Push the branch. An integration
  branch to carry three commits is a merge commit and a wait for nothing.
- **The branches are independent and land separately.** Parallel PRs off
  `<trunk>` are simpler and reviewers get smaller diffs.

The threshold is roughly: **two or more worktrees, or two or more branches, that
must land together.** Below that, converging costs more than it saves.

## Step 1 - Measure. Do not trust yesterday's picture.

Nothing below is decidable without this. Run it for every repo involved.

```bash
scripts/worktree-survey.sh --base <trunk> --compare <branch-you-suspect>
```

It enumerates worktrees from `git worktree list --porcelain`, then prints per
worktree: branch, whether an upstream is even configured, dirty file count,
unpushed commits, and commits behind and ahead of `<trunk>`. It is read only.

Then read the **overlap check**, which is the part that changes the size of the
job. For each uncommitted file it reports whether a byte-identical copy is
already committed on the compare branch:

```
  DIFFERS  README.md
  DIFFERS  src/delta.ts
  ABSENT   src/epsilon.ts
  SAME     src/gamma.ts
```

`SAME` rows are not work you have to carry. This check has repeatedly shown that
most "lost" uncommitted work was already committed on another branch, which
turns a frightening convergence into a small one.

The script also lists your open PRs when `gh` is installed and authenticated,
and says plainly which of the two is missing when it is not.

## Step 2 - Check for supersession before you build anything

A branch far behind the trunk may already be fully landed there, in a better
form. Cherry-picking it then produces conflicts that really mean "this is
already done".

```bash
git rev-list --left-right --count origin/<trunk>...<branch>   # behind  ahead
```

Deeply behind and barely ahead is the shape to suspect. Confirm it by comparing
exported symbols, not line counts: full commands and the judgement calls are in
[references/conflict-resolution.md](references/conflict-resolution.md).

**If the branch is superseded, say so and drop it.** Do not build an integration
branch to carry nothing.

## Step 3 - One integration branch, or a stack?

**Default: one integration branch. One PR per repo, merged once.**

Choose a stack only when the layers are genuinely dependent **and** someone is
reviewing them separately. A stack buys reviewability and costs you N merges in
strict order instead of one. Building one is [stacked-prs](../stacked-prs), which
is where the `gh stack` mechanics belong.

One trap worth knowing before you pick, because it is why people wrongly conclude
stacks are unusable on a non-default trunk:

> `gh stack init` and `gh stack link` both default `--base` to the **repository
> default branch**. If your stack sits on a trunk that is not the default, pass
> `--base <trunk>` explicitly. Omit it and the bottom pull request is retargeted
> to the default branch.

Verified on `gh` 2.98.0: `gh stack init --base <trunk>` and
`gh stack link --base <trunk>` both accept a non-default trunk. Whether GitHub
lets you move a stacked PR's base back afterwards is unverified here, so plan on
passing `--base` rather than on fixing it later.

## Step 4 - Commit local work FIRST, before any merge

A merge against a dirty tree is unresolvable. Commit every worktree first.

- **Split by concern, not by file count.** A product change and a test harness
  are two commits.
- **Use `git commit -- <pathspec>`, never `git add` then a bare commit.**
  `git add` scopes nothing in a shared checkout, and a bare commit sweeps in
  whatever else was staged.
- **Untracked files still need `git add` first**, then commit with a pathspec.
- **Do not `git stash` here.** Anything else touching the tree during the stash
  window can take the work with no trace. A scheduled sync job once collided
  with a stash and the changes were simply gone, with nothing in the reflog to
  recover. Commit to a scratch branch instead. It is recoverable.
- **Leave generated build stamps and version files dirty.** Committing them is
  noise that conflicts on every single merge.

If the repo lints commit messages, match its case convention before you write
fifteen of them. Many commitlint setups reject sentence-case and start-case
subjects and accept only a lowercase conventional subject.

## Step 5 - Merge order: smallest delta first

Merge the branch with the **fewest commits ahead** of `<integration>` first, then
the larger one on top. The second merge is where the conflicts are, and a smaller
first merge keeps them readable.

```bash
git merge-tree --write-tree <integration> <branch>    # predicts conflicts
git merge --no-commit --no-ff <branch>                # then resolve by hand
```

`git merge-tree` predicts against the tree **as it is right now**. Once you
commit anything to `<integration>`, re-run it. A clean prediction goes stale the
moment you land something.

Resolution rules, the "the integration branch is the later decision" principle
and its one exception, and how to write a commit message that names the conflict
theme: [references/conflict-resolution.md](references/conflict-resolution.md).

## Step 6 - Gates, locally, on the merged tree, before pushing

```bash
set -o pipefail
<typecheck> ; <tests> ; <lint> ; <health>
```

**Run them yourself. Do not hand gate-running to a fleet of subagents.** Four
self-verifying agents once put 25 Node workers on one machine at 417% CPU, and
the machine, not the code, became the thing being debugged.

Traps, all of which generalise:

| Trap | What happens |
|---|---|
| `$?` after a pipe | Always `0`. Pipe a typecheck into `tail` and a failure reads as green. Use `set -o pipefail`, or read `${PIPESTATUS[0]}`. |
| A package-manager builtin shadowing a repo script | `<pm> test` may run the builtin, not your script. Use `<pm> run <script>`. |
| Tooling that moved | After a package-manager cutover or a linter swap, the old runner is gone. The command in your notes is not the command in the repo. Read the scripts again. |
| A heavy `<health>` script | It can exhaust the default heap. Raise it (for Node, `NODE_OPTIONS=--max-old-space-size=8192`). |
| `<health>` treated as a gate | If it is in no CI workflow, it is advisory. **Run it on the pre-merge base too** before you report its score as a regression. It is usually already red. |
| A pre-push hook running a lint ratchet | It checks the whole pushed range, which is wider than what you edited, so it surfaces debt from files you merely touched. Fix the violation. Never regenerate the baseline. |

## Step 7 - A merge that runs an install breaks a live dev server

Merging a lockfile change triggers an install that rewrites `node_modules` under
any running dev server. The page then shows `Failed to resolve import ...` for a
file that **exists on disk**.

Diagnose before you touch code:

```bash
node -e "console.log(require.resolve('the/import', {paths:['<dir>']}))"
ls -la node_modules/<pkg>        # symlink mtime = when the install ran
ls -ld node_modules/.vite        # dep cache mtime = how stale the server is
```

The last path is the dev server's dependency cache directory. Vite uses
`node_modules/.vite`; other bundlers keep their own. Find yours once.

**Resolves fine, and the cache is older than the symlink? Restart the server. Do
not debug the page.** Do not kill a dev server you did not start, because you do
not know which script or which port it belongs to. Hand the owner the command.

## Step 8 - Keep the descriptions

The descriptions on your existing PRs are the review context you already paid
for. Closing and reopening throws it away. Instead:

1. `gh pr edit <n> --base <integration>` to retarget. The description survives.
2. Merge that branch into `<integration>` locally, then push.
3. GitHub marks each PR **MERGED** on its own once its head is an ancestor of its
   base. It stays linkable as a merged PR.

Then open the single `<integration>` PR into `<trunk>` and reference the merged
ones from its body. Write it with [file-pr](../file-pr), which leads with the
problem rather than an inventory of files, and take it to green with
[babysit-pr](../babysit-pr).

## Red flags - stop

- Merging into a dirty tree.
- Trusting a `git merge-tree` prediction made before your last commit.
- `git stash`, at any point in a convergence.
- Regenerating a lint baseline to make a push succeed.
- Reporting `<health>` as a new regression without running it on the base.
- Killing a dev server you did not start.
- Claiming the gates passed after piping their output somewhere, with no
  `pipefail`.
- Opening the `<integration>` PR before the gates ran on the **merged** tree.
- Building an integration branch for a branch the trunk already superseded.

## Files

- `scripts/worktree-survey.sh` - read-only survey of every worktree, plus the
  overlap check that shows how much of the work is already committed elsewhere
- `references/conflict-resolution.md` - merge order, the resolution rule and its
  exception, conflict-resolution commit messages, and supersession detection

Installed from [kelaskills](https://github.com/wicolian/kelaskills). To make a
repo-specific version, copy the folder into that repo's `.agents/skills/` and add
a `references/<repo>.md` naming its real `<trunk>`, `<integration>` and gate
commands.
