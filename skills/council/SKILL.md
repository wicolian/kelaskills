---
name: council
description: Use when the user says "council", "ask the council", "get a second and third opinion from other models", or "have Claude and Codex both review this".
---

# Council

Get independent views on a request, usually a review, from models of different
providers. On our box that is two members: Claude and Codex. Gemini and others are
not installed here.

Adapted from Theo Browne's [tstack](https://github.com/t3dotgg/tstack) (MIT), fitted
to our rules.

## Members

| Member | How |
|---|---|
| Claude Opus 5.5 | its own herdr pane, `cc-fleet` (`spawn-if-capacity.sh`) |
| GPT Sol (`gpt-6.1-sol`, flex) | its own herdr pane, `codex-spawn` |

The user names other members? Use those. A member you cannot start: report it, do
not swap in another model. Codex is the user's own money: say the cost.

Pane names in plain words: `council-claude: review <PR>`, `council-sol: review <PR>`.

## Run it

1. Give each member the same brief: the request, the repo path, the base, the diff
   command. For review, read-only: no edits, commits, pushes or comments.
2. For a code review, ask each for a score out of 10 and findings as
   `[blocker|should|nit] file:line claim`.
3. Collect both answers. Summarize the useful findings, where they disagree, and
   the next steps. You decide what is real; check it in the source.
4. Agree with a finding? Make the smallest fix, then start a new round with fresh
   panes. One full review pass is one round.
5. Stop when both are satisfied, or after 3 rounds. Fight scope creep the whole way.
6. Close the panes.

## Put it on the PR

Edit the PR description (no comment), before the attribution line:

```markdown
## Council review

Rounds: 2

| Member | Round 1 | Round 2 |
| --- | --- | --- |
| Claude Opus 5.5 | 7/10 | 9/10 |
| GPT Sol (gpt-6.1-sol, flex) | 8/10 | 10/10 |
```

No score given: write `no score`. No PR: put the table in the final reply.
