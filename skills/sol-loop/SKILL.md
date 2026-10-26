---
name: sol-loop
description: Use when the user says "sol loop", "review loop", "have Sol review this", or "loop a Codex review on this diff", or when full-send or full-stop reaches its review step.
---

# Sol loop

Make a change more correct before (or after) the PR: one GPT Sol reviewer reads the
diff, you answer, repeat. Make the smallest change that satisfies a real finding.
Push back on scope creep.

Adapted from Theo Browne's [tstack](https://github.com/t3dotgg/tstack) (MIT), fitted
to our rules.

## Budget

- 3 rounds. Round 1 is the full diff. Later rounds: changed code and open ids only.
- Up to 5 only for security, auth, permissions, tenancy, data loss, or concurrency,
  while a blocker or should stays open with evidence. Or when the user asks.
- Stop early when a round returns only nits.
- One reviewer at a time. The reviewer starts no subagents.
- Keep a ledger: id, severity, outcome. Write down only what you saw.

## 1. Scope

`git status --short`. Leave unrelated changes alone; do not stash them. Find the
base after `git fetch origin`: for a PR, `git merge-base HEAD origin/<baseRefName>`;
local work, the default branch. Use one diff command for all rounds. Write intent
and out-of-scope in 1 to 2 sentences. Run the checks that cover the change and note
the ones that fail before your change.

## 2. Start the reviewer

Sol is Codex `gpt-6.1-sol` on flex, in a visible herdr pane. Load `codex-spawn`:

```bash
export AGENT_FLEET_ROOT=<programme dir>
CODEX_MODEL=gpt-6.1-sol ~/.claude/skills/codex-spawn/scripts/spawn-codex.sh \
  sol-review flex <brief-file> <tab> <repo>
```

Never `codex exec`. Name the pane `sol-review: <PR or branch>`. Codex is the user's
own money: say the cost (flex is about 1 USD in, 5 USD out per 1M tokens).

No Codex quota, flex "at capacity" twice, or tier not honoured: start a fresh Opus
5.5 reviewer pane with the same brief, and say so in the footer.

Do not edit the scoped files while the review runs. A timeout or no reply is not
approval.

Round 1 brief:

```
Review only. Do not edit, commit, push, comment, or start subagents.
Repo: <path> Base: <sha> Intent: <intent> Out of scope: <scope> Checks: <results>
See: git diff <base> [-- <paths>]; git status --short (read untracked files).
Find bugs, broken callers, mismatch with intent. Skip style unless it hides a bug.
Hold to the smallest change. Flag code, tests, or guards the intent does not need.
blocker = intended case wrong. should = real bug callers will hit. nit = the rest.
Reply:
VERDICT: APPROVE or CHANGES
S1 [blocker|should|nit] <file>:<line> <claim>. Fix: <suggestion>
```

## 3. Answer each finding

Check each finding and its severity yourself. Another path, a rare case, or a small
cost is a nit, whatever label it came with.

- Agree: smallest fix. Prefer delete or narrow over a new helper, lock, or option.
- Disagree: say why, with file:line, a test, or output.
- Nit or out of scope: decline in one line, list it as a follow-up.

Re-run checks and `git diff --shortstat <base>`. Did review grow the diff? Cut first.
Never agree only to end the loop.

## 4. Next round

Only when budget is left and a blocker or should is open, or behaviour code changed
since approval. Send the round 1 brief, the ledger (`fixed:` / `disagree:` /
`declined:` with evidence) and the change since last round. Close the old pane.

## 5. Stop

- **Approved:** APPROVE on the current diff, no blocker or should open.
- **Stuck:** a finding stays disputed after two replies, or the budget ends. Show both
  sides in 2 to 3 lines. The user decides. Budget end is not approval.

Push only when the user asked to push or ship. On the PR, add this line always, also
when the verdict is not approved:

```
Reviewed with sol loop: <N> rounds, gpt-6.1-sol on flex. Verdict: <approved|changes open|stuck>
```

Fallback: `Reviewed with review loop: <N> rounds, Opus fallback. Verdict: <...>`.

Report: rounds, model and tier, diff size before and after, fixed and declined
findings with reasons, cost, pushed or not. Close the reviewer pane.
