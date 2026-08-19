# gh stack - command reference

GitHub's native stacked PRs, public preview since 2026-07-30, all repositories.
The extension is `github/gh-stack`.

```bash
gh extension install github/gh-stack     # install
gh extension upgrade gh-stack            # keep current - this is a preview
gh stack --version
```

The feature is in preview. Re-read `gh stack <cmd> --help` before you trust a
flag written here.

## Stack management

| Command | What it does |
|---|---|
| `gh stack init [branches...]` | Start a stack. Several names adopt existing branches bottom to top; missing ones are created. `--base <trunk>` sets the trunk, default is the repo default branch. |
| `gh stack add [branch]` | New branch on top of the current stack. `-m "msg"` commits and can auto-name the branch. `-A` stages everything including untracked, `-u` tracked only. |
| `gh stack view` | The chain and each PR's state. `--short` one line per branch, `--json` machine-readable. Icons: `✓` merged, `◎` queued, `○` open, `⚠` needs rebase. |
| `gh stack modify` | Interactive TUI. Keys: `x` drop, `d` fold into the branch below, `u` fold into the branch above, `i`/`I` insert, `r` rename, Shift+arrow reorder, `z` undo a staged action, Ctrl+S apply. `--abort`, `--continue`. Run `gh stack submit` afterwards. |
| `gh stack checkout [n]` | Check out a stack by stack number, PR number, PR URL or branch. No argument opens a picker of every stack, local and remote. |
| `gh stack unstack [n]` | Remove the stack object. `--local` keeps it on GitHub. PRs that are queued or have auto-merge stay stacked. |

## Remote

| Command | What it does |
|---|---|
| `gh stack submit` | Push every branch, create or update the PRs, create or update the stack on GitHub. Interactive editor for all titles and bodies at once; `--auto` skips it. `--open` marks PRs ready for review - without it, `--auto` and non-interactive shells create **drafts**. |
| `gh stack sync` | Fetch, reconcile local against the remote stack, fast-forward the trunk, cascade-rebase each branch onto its parent, push `--force-with-lease --atomic`, refresh PR state, relink the stack. Never opens PRs. `--prune` drops local branches for merged PRs. On a rebase conflict it restores everything and tells you to run `gh stack rebase`. |
| `gh stack rebase` | Cascading rebase. `--downstack` trunk to current, `--upstack` current to top, `--no-trunk` inter-branch only. `--continue`, `--abort`. `--preserve-dates`. |
| `gh stack push` | Push only. Per-branch `--force-with-lease`, **not atomic** - one branch can land while another is rejected. Skips merged and queued branches. |
| `gh stack merge [n]` | Atomic merge of everything up to your chosen PR. Interactive wizard, or `--yes`. `--squash` / `--merge` / `--rebase` / `--merge-method <m>`. |
| `gh stack link <a> <b> ...` | Build a stack on GitHub from branch names, PR numbers or PR URLs, bottom to top, with no local tracking. For jj, Sapling, ghstack, git-town users. A stack number as the first argument appends to that stack. |

## Navigation

`gh stack up` `down` `top` `bottom` `trunk` `switch` (interactive).

## Behaviour you have to plan around

- **Merge is bottom up and contiguous.** You can merge any group starting at the
  lowest unmerged PR. You cannot merge a middle PR alone.
- **Merge is atomic.** If one PR in the group cannot merge, none do.
- **Retargeting is automatic.** After a partial merge the next unmerged PR is
  rebased to target the stack base and moves to the bottom.
- **Auto-merge is not supported for stacks.**
- **Merge queues are supported.** The stack enters the queue.
- **Branch protection and required checks apply per layer.** Bypassing merge
  requirements is not supported for stacks.
- **Cross-fork stacks are not supported.** Every branch must be in one repo.
- **GitHub Desktop does not support stacks.**
- **The stack must be linear before merging.** A "Rebase stack" button appears in
  the UI if it is not; locally that is `gh stack sync`.
- **Programmatic merges** use the asynchronous merge API.
- **The "Rebase stack" button in the merge box creates unsigned commits.** If the
  repo requires signed commits, rebase locally with `gh stack sync` or
  `gh stack rebase` instead of using the button.
- **Unstacking is website-only.** It removes open, draft and closed PRs from the
  stack; merged and queued PRs stay.

## `gh-merge-base`

Separate from the extension, plain `gh pr create` honours a per-branch config:

```bash
git config branch.feat/002-api.gh-merge-base feat/001-schema
```

`gh pr create` with no `--base` then targets that branch. Useful for a manual
stack, or a repo where the extension is not available. It sets the base only; it
does not rebase or link anything.
