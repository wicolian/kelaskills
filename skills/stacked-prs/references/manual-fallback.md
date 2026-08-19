# Manual stacking - plain git and gh

Use this only when `gh stack` is genuinely unavailable: the extension cannot be
installed, the host is GitHub Enterprise Server without the preview, or the
contribution is cross-fork (which native stacks do not support).

Everything here is what `gh stack` automates. Doing it by hand is slower and the
mistakes are silent, so prefer the extension.

## Create the chain

```bash
git checkout main && git pull

git checkout -b feat/001-schema
#  ...work, commit...
git push -u origin feat/001-schema
gh pr create --base main --title "[1/3] Schema" --body-file pr-001.md

git checkout -b feat/002-api            # from 001, NOT from main
#  ...work, commit...
git push -u origin feat/002-api
gh pr create --base feat/001-schema --title "[2/3] API" --body-file pr-002.md

git checkout -b feat/003-ui             # from 002, NOT from main
#  ...work, commit...
git push -u origin feat/003-ui
gh pr create --base feat/002-api --title "[3/3] UI" --body-file pr-003.md
```

The single most common mistake is `git checkout main` before creating the next
branch. That produces three independent PRs that only look like a stack.

Guard against it by pinning the base in git config, so a bare `gh pr create`
cannot target the wrong branch:

```bash
git config branch.feat/002-api.gh-merge-base feat/001-schema
git config branch.feat/003-ui.gh-merge-base  feat/002-api
```

## PR body template

```markdown
## This PR
<what changed in THIS layer only>

## Stack
1. #123 Schema        (feat/001-schema)   <- merge first
2. #124 API           (feat/002-api)      <- THIS PR
3. #125 UI            (feat/003-ui)

Depends on #123.

## Reviewing just this layer
GitHub already shows only this layer's diff, because the base is the branch
below. Locally: `git diff feat/001-schema...feat/002-api` (three dots).

## Verification
- [ ] Builds and tests green on this branch alone
```

Keep the numbered list identical in every PR of the stack and update it when the
stack changes. Nothing does this for you here.

## Rebase after the base changes

Any commit on a lower layer means every layer above it has to be rebased, in
order, bottom to top:

```bash
git checkout feat/001-schema && git pull --ff-only

git checkout feat/002-api
git rebase feat/001-schema
git push --force-with-lease origin feat/002-api

git checkout feat/003-ui
git rebase feat/002-api
git push --force-with-lease origin feat/003-ui
```

`--force-with-lease`, never `--force`. Lease refuses the push if someone else
moved the branch; plain force silently destroys their commits.

Miss a layer and the skipped PR's diff fills with commits that belong to the
layer below it. That is the usual cause of "the stacked PR shows 200 files".

## Merge

Bottom up, one at a time:

1. Merge PR-001 into main.
2. **Retarget PR-002 to main** - the "Edit" button next to the PR title. GitHub
   retargets automatically only when the merged branch is deleted, and many
   repos have `delete_branch_on_merge` off. Check, do not assume.
3. Rebase PR-002 onto main, force-with-lease, wait for green.
4. Merge PR-002. Repeat for PR-003.

There is no atomic all-or-nothing merge here. Between step 1 and the last merge,
main holds a partial stack. If that is unacceptable, point the whole chain at a
long-lived integration branch and take that to main in one final PR.

## Checklist

- [ ] Each branch created from the branch below it, not from the trunk
- [ ] Each PR's base is the branch below it
- [ ] `gh-merge-base` set per branch
- [ ] Every PR body carries the stack list, and it is current
- [ ] Every branch builds and tests green on its own
- [ ] Rebases go bottom to top, none skipped
- [ ] `--force-with-lease`, never `--force`
- [ ] Nothing pushed without the repo owner asking for it
