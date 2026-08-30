---
name: babysit-pr
description: Use when asked to "babysit this PR", "watch the PR", "monitor the pull request", "get it green", "address the review comments", "keep it rebased", "handle the bot feedback", or to sit on an open pull request until CI passes and reviewers approve. For writing and opening the PR, use file-pr.
---

# Babysit a PR

## Why this is two skills

This started as one skill and split in two. Writing a pull request and watching
one have different triggers, you normally want one and not the other, and once
the trigger words were sharp each fired reliably alone. `file-pr` opens the pull
request. `babysit-pr` takes it from open to green and approved.

## The problem

A modern repo has several automated reviewers. An agent told to satisfy all of
them treats every comment as mission critical and triples the size of the pull
request. The failure is not laziness. It is compliance.

## The one rule

**Do not let review feedback expand the pull request beyond the original goal.
Address real shortcomings. Refuse scope creep out loud, with a reason.**

A pull request that grew a new abstraction because a bot suggested one is a
failed babysit, even if every check is green.

| Feedback | Verdict |
|---|---|
| A bug in a line this PR changed | Fix it |
| A missing null check in code this PR wrote | Fix it |
| A pre-existing bug in a file this PR touched | Reply, decline, suggest a follow-up |
| "Consider extracting this into a service layer" | Decline with a reason |
| "Add tests for this whole module" | Add tests for what this PR changed, decline the rest |
| A style preference the repo does not enforce | Decline, point at the linter config |

## The loop

### 1. Watch

If the harness offers tools that watch a pull request, use those. Otherwise poll.

```bash
gh pr checks <n> --watch
gh pr view <n> --json reviews,comments,statusCheckRollup,headRefOid,isDraft,mergeStateStatus
gh api repos/<owner>/<repo>/pulls/<n>/comments        # inline review comments
gh api repos/<owner>/<repo>/issues/<n>/comments       # top-level comments
```

`scripts/pr-status.sh <n>` prints one read-only snapshot: checks, reviews, and
which comments arrived after the last push. It changes nothing.

### 2. Act only on what is newer than your last push

Re-litigating stale feedback is how a babysit session never ends. A bot comment
from before your fix is about code that no longer exists.

The mechanic: get the head commit's timestamp, then keep only comments created
after it.

```bash
SHA=$(gh pr view <n> --json headRefOid -q .headRefOid)
SINCE=$(gh api repos/<owner>/<repo>/commits/$SHA -q .commit.committer.date)
gh api repos/<owner>/<repo>/pulls/<n>/comments \
  -q ".[] | select(.created_at > \"$SINCE\") | {user:.user.login, path, line, body}"
```

Same filter for check runs: a failing run whose `completedAt` predates the head
commit is telling you about the old code.

### 3. Verify every finding against the source before you touch code

Automated reviewers are useful and frequently wrong. They hallucinate a caller,
miss a guard three lines up, or assume a framework the repo does not use.

Open the file. Read the actual lines. **A finding you cannot reproduce in the
source is a false positive.** Say so in the reply and move on. Never change code
because a bot sounded confident, only because you read the source and it was
right.

Triage table, the findings that are almost always real, and the ones that are
almost always safe to dismiss: `references/review-bots.md`.

### 4. Tell a real CI failure from infrastructure flake

| Tell | Reading |
|---|---|
| Fails on a job unrelated to your diff | Likely flake |
| Passes on re-run with no code change | Flake, confirmed |
| Log shows a network timeout, a registry 5xx, a runner eviction, an out-of-disk | Infrastructure |
| Log shows an assertion, a type error, a lint rule, a snapshot diff | Real, fix it |
| Fails the same way twice on the same commit | Real, fix it |

Re-run once before you treat a suspected flake as a failure.

```bash
gh run rerun <run-id> --failed
gh run view <run-id> --log-failed
```

A flake that recurs across many pull requests is a repo problem worth naming to
the human. It is not this pull request's job to fix it.

### 5. Dismiss out loud, never in silence

When you decline a finding, reply with a written reason and resolve the thread.
Silence reads as neglect to the next human who opens the page.

```
Not changing this. <one sentence of reason.> <If it is worth doing
later: good follow-up, out of scope here.>
```

An unanswered bot thread and a considered refusal look identical in the count at
the top of the page. Only the reply tells them apart.

### 6. Watch the base branch

```bash
git fetch origin
git log --oneline HEAD..origin/main | wc -l
gh pr view <n> --json mergeStateStatus -q .mergeStateStatus
```

Rebase or merge the base in when it has moved enough to matter: conflicts,
`BEHIND` or `DIRTY` merge state, or the base changed something this PR depends
on. Do not rebase on every base commit for tidiness. Each rebase invalidates a
review someone already did.

If another pull request lands that makes this one obsolete: **stop, report to the
human, and ask.** Never close a pull request without explicit authorisation.

### 7. Exit condition

Loop until **every required check is green and the pull request has the
approvals the repo requires**. That is the exit. Report it and stop. Not "no new
comments for a while", and not "the bots went quiet".

### 8. Attribution on every comment you post

When an agent comments through a human's account, it must say so. Lead the reply
with one line:

```
<model or harness> responding on behalf of <user>.

<the actual reply>
```

An unmarked agent comment in a human's account is dishonest to reviewers. They
calibrate their trust differently once they know.

## The human gate

| Yours, do it | Theirs, ask first |
|---|---|
| Push commits to the PR branch | Merge, including enabling auto-merge |
| Reply to comments, resolve threads | Close the pull request |
| Re-run failed checks | Change the base branch |
| Rebase or merge the base in | Dismiss a human reviewer's requested changes |
| Force-push your own rebase, `--force-with-lease` only | Approve the pull request |

The boundary: everything reversible and inside the PR is yours. Anything that
lands code, discards work, or overrides a person is theirs.

## Red flags, stop

- The diff has grown a file that has nothing to do with the original goal.
- You are editing code because a bot said so and you have not read the source.
- You are replying to a comment older than your last push.
- Three rebases in an hour with no base conflict.
- You are about to merge, or close this because another PR seems to cover it.
- The bot count went to zero because you did what all of them said.

## Files

- `references/review-bots.md` - triaging automated review comments: real versus
  false positive, the safe-to-dismiss categories, and reply templates
- `scripts/pr-status.sh` - read-only status snapshot, including which feedback
  is newer than the last push
