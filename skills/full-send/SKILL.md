---
name: full-send
description: Use when the user says "full send", "full-send this", "take it all the way to merged", or "I am not watching, finish and merge it". Not for "full stop", which never merges.
---

# Full send

The user is not watching. Nobody reads your updates until long after you stop.
You own the work from where it is now to a **merged** PR.

Only a clear "full send" grants this. Without it, work as normal.

Adapted from Theo Browne's [tstack](https://github.com/t3dotgg/tstack) (MIT), fitted
to our rules. Where they differ, ours win.

## What the request grants

- Merge the PR when the merge gate below passes.
- Use the test method that proof needs (browser, dev server, screenshots) without
  asking first. Rules about *how* to test still apply.

It does not grant: force push of any kind, production changes, data deletion,
closing a PR, or work outside the repo. Those go to "Asking the user".

## Steps

1. **Finish the change.** Smallest change that fixes the case that happened. On the
   default branch? Make a branch first.
2. **Prove it.** See "Proof".
3. **Review it** with `sol-loop`.
4. **File the PR** with `file-pr`. Bring the branch up to date with a merge commit,
   not a rebase. Add one line to the description that says how you proved it.
5. **Babysit it** with `babysit-pr`. Prove each fix before you push it.
6. **Merge** when the gate passes, with the method the repo uses.
7. **Report:** PR link, merge commit, proof, and each decision you made for the user.

Stay active from 1 to 7. If you end the turn while checks run, the work stops. Wait
with one watcher (see `babysit-pr`), so a PR change wakes you.

## Proof

Evidence you saw yourself in this session, the most direct the change allows:

- Reproduce the failure, apply the fix, run the same reproduction and see it pass.
- Run what CI runs: typecheck, lint, tests.
- One focused test that fails on the old code, when the repo has a test setup.
- UI or runtime change: run the product and look. agent-browser screenshots go on
  the PR. Green mocked tests are not proof that the user flow works.

No way to prove it means no full confidence. Ask.

## Merge gate

All true on the latest commit:

- Proof covers every change in the diff, in a running product for UI.
- Required CI is green. The e2e comment says 0 failed, where e2e runs.
- Greptile says confidence 5/5 and 0 review threads are open. Ask for a new review
  with one `@greptileai review` comment only; a thumbs up on it counts as the pass.
- No human review requests changes. Human approval is not a gate unless asked.
- The branch is up to date with its base and GitHub says it is mergeable.
- No item in the change is a FLAG item that still waits for the user's go.

Never `--admin`, never bypass branch protection. A merge queue or auto-merge: stay
until GitHub says merged.

## Asking the user

A question in a normal message is not seen. Ask through a channel that shows it:

- In Claude Code: `AskUserQuestion`. In Codex: `request_user_input`.
- Not watching at all: their Slack self-DM with `~/.claude/scripts/dm-koushik.sh`.
  Never another channel or person.

Short, simple English. Put the PR link, the blocker, and two options with your pick
first.

Ask only when: you cannot prove the change, the gate cannot pass and you cannot fix
it, the next step is outside the grant, the goal is ambiguous in a way that changes
the result, or another PR makes this one obsolete. Decide the rest yourself and list
those decisions in the report.

No answer? Take the safe path: leave the PR open, and start the final message with
the question.
