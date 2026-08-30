---
name: agent-retro
description: Use when agent config is being tuned from memory instead of evidence. Triggers on "why do my agents keep doing this", "audit my agent history", "what mistakes does my agent make most", "tune my AGENTS.md with evidence", "which model breaks my environment", "retro on my agent usage", "my CLAUDE.md is too long and I do not know what still matters", "is that instruction still earning its place", "did that config change actually work". Mines the session transcripts already on your disk, counts failures by model and by harness, and turns the top few into concrete config changes.
argument-hint: "[-obsidian]"
---

# Agent retro

Most people tune agent config by vibes. You remember the time an agent deleted
the wrong thing, you add a line about it, and the line stays forever. Six months
later the file is long, half of it aims at problems that stopped happening, and
nobody can tell which lines are load-bearing. That is anecdote.

You already have the data. **Every coding-agent session on your machine leaves a
transcript on disk.** This skill mines them for what actually went wrong, counts
it by model and by harness, and turns the top few failure modes into config
changes.

Stop guessing which instruction your agents need. Go measure which mistake they
actually make.

| File | Read it when |
|---|---|
| [scripts/retro-scan.sh](scripts/retro-scan.sh) | Running the count. Read only, never modifies a transcript. |
| [references/failure-taxonomy.md](references/failure-taxonomy.md) | Turning a count into a finding. All nine categories, their patterns, their false positives, and the config change each one takes. |
| [references/audit-prompts.md](references/audit-prompts.md) | The store is too big for one context. Fan-out brief, output contract, merge rules. |

## Privacy first, because this is the real risk

A transcript is not a log. It is a recording of your work: your source code,
your credentials, your customers' data, your half-formed thinking, and every
mistake you made out loud.

Hard rules. Not preferences.

- **Never upload a transcript anywhere.** Not a pastebin, not an issue, not an
  analysis tool, not a service offering to summarise it.
- **Never paste one into a third-party tool.** Running locally is the whole
  point.
- **Never quote a transcript line into a public report, a commit message or a
  pull request without redacting it.** Paths, hostnames, table names and
  customer identifiers all leak from one line.
- **Prefer running the audit locally**, on the machine that holds the files.
- **Fanning out to subagents widens exposure.** Every auditor you spawn now
  holds that content. That is the price of auditing a store too big for one
  window. Keep it inside the trust boundary that already has your code.
- **If the audit surfaces a secret, rotate it.** A secret printed in a session
  is a secret on disk in plain text. Noting it is not fixing it.

`scripts/retro-scan.sh` truncates and redacts the command text it prints. That
is a seatbelt, not a guarantee. Read its output before you paste it anywhere.

## Step 1: find the transcripts, do not assume where they are

These paths move between versions. Ranking your own disk beats trusting any
list, including this one.

```bash
./scripts/retro-scan.sh --discover
```

It walks the dot-directories under `~/`, groups every `.jsonl` and `.log` by
store, and ranks by size. On the machine this was built on it found stores for
six agents, three of which no hand-written list would have included. Starting
points only:

| Agent | Where to look |
|---|---|
| Claude Code | `~/.claude/projects/**/*.jsonl`, one file per session. Also `~/.claude/history.jsonl` for prompt text only. Subagent transcripts sit in a `subagents/` subdirectory. |
| Codex | `~/.codex/sessions/**/rollout-*.jsonl`, plus `~/.codex/history.jsonl` and `~/.codex/archived_sessions/` |
| Cursor | `~/.cursor/projects/**/agent-transcripts/**/*.jsonl` |
| Anything else | `~/.<agent>/`, `~/.config/<agent>/`, then that agent's own docs |

Confirm before you count. One record is enough:
`head -1 <a session file> | python3 -m json.tool`

## Step 2: learn the shape, do not trust a documented schema

Formats change and nobody announces it. A skill that hardcodes a schema which
has since moved is worse than one that teaches the check. What you usually find,
all of it worth verifying rather than believing:

| Field | Typically |
|---|---|
| `type` | `user`, `assistant`, `system`, or a harness-specific envelope name |
| `message.role`, `message.content` | The turn. `content` is a string or a list of blocks. |
| `message.model` | The model id, on assistant records, when it is recorded at all |
| `timestamp`, `cwd`, `sessionId`, `toolUseResult` | Metadata, and the result attached after a tool call |

Three things that skew your numbers if you skip this step:

1. **A "user" record is often not a human.** Tool results, system reminders,
   command echoes and injected context all arrive with `role: user`. Count them
   and the denominator inflates until the correction rate reads as zero.
2. **Subagent transcripts may be separate files, or flagged inline.** One store
   carried more than twenty subagent turns per human turn. A dispatch prompt is
   not a person talking.
3. **Some stores record no model id at all.** Say the split is unavailable for
   that harness. Do not invent a bucket.

## Step 3: run the count

```bash
./scripts/retro-scan.sh                                   # discover, then scan each
./scripts/retro-scan.sh --store ~/.codex/sessions         # one store
./scripts/retro-scan.sh --since 2026-08-01 --max-files 0  # since a date, no cap
./scripts/retro-scan.sh --examples                        # print the matched text
```

Per store it reports sessions, date range, per-model message counts,
corrections per 100 human messages split by model, and destructive-command hits
with their session file and timestamp.

A full pass over 4,000 sessions and 4.4 GB across three harnesses finished in
under 25 seconds. Size is not your excuse.

## Step 4: the taxonomy

Nine categories. Full detection patterns, false positives and fixes in
[references/failure-taxonomy.md](references/failure-taxonomy.md).

| # | Category | The shape of it |
|---|---|---|
| 1 | Destructive or wrong-target actions | Killed the dev server, or the session it was running in. `rm` outside scope, `git reset --hard`, force push. |
| 2 | Tool misuse | Wrong command for the tool. A subcommand that silently does the wrong thing. The same call failing repeatedly. |
| 3 | Overbuild | Far more code than the request implied. Abstraction nobody asked for. |
| 4 | Stopping early | Reported done with work outstanding. Handed back a to-do list. |
| 5 | Unasked edits | Files touched outside the stated scope. |
| 6 | Process failures | Stale branches, red CI ignored, a draft PR when a real one was wanted. |
| 7 | Misreading intent | Did a different job from the one asked. |
| 8 | Regression | Broke something that worked. Rare. Expensive. |
| 9 | Verification skipped | `--no-verify`, bypassed hooks, committed without the project's own gates. |

**The proxy metric that ties them together: corrections per 100 human
messages.** Every time you said a variant of no, normalised per model and per
harness, because a raw count only tells you which model you used most.

Categories 3 and 7 have no keyword signature. They need a model that reads the
request beside the diff. If a grep counted them, you did not count them, and the
honest report says so.

## Step 5: the honest-reading rules

This matters more than the counting. A naive report misleads you confidently.

- **Normalise or the numbers are meaningless.** The model you use most tops
  every raw count. That is a usage fact, not a quality fact.
- **Correction rate is confounded by task difficulty.** Hand your hardest,
  least-specified work to one model and it looks worst. Say that in the report
  rather than ranking models on it.
- **Correction rate is confounded by task type.** A model you never gave
  frontend work has a clean frontend record. That is absent data, not strength.
- **Rank by cost, not frequency.** One destroyed environment outranks fifty
  verbose replies, every time.
- **Separate what config could have prevented from what it could not.** Only the
  first is actionable, and the report must say which is which. Write the rest
  down anyway, marked, so nobody audits them again next quarter.
- **A phrase match is a candidate, not a correction.** On a real store a bare
  `stop` pattern matched a hundred worker dispatch prompts before it was
  tightened. Loosen the patterns and you measure your own vocabulary instead of
  your agent's behaviour.

## Step 6: turn each finding into exactly one change

A finding is not a deliverable. Take the top three to five, give each a
destination.

| Destination | When |
|---|---|
| A line in the global agent instructions | It applies everywhere |
| A line in the project's own instructions | It is repo-specific |
| A new skill | It is a whole procedure, not a rule |
| A hook or a guardrail | A rule will not hold and it must be mechanically blocked |
| Nothing, with a stated reason | Config could not have prevented it |

Categories 1 and 9 usually land on the guardrail row. Both fail exactly when the
agent is under pressure to finish, which is when a prompt line has least grip.

**Write one line per finding, and prompt it positively.** State the target
behaviour, not the ban. A prohibition drags the banned behaviour into context
every time the file is read, and the config becomes a museum of complaints.

```
worse   Never commit without running tests
better  Run `<the project gate command>` before you call the work done
```

The useful part is the command name, not the prohibition.

## Step 7: interrogate the thread, not just the counts

The numbers tell you what. The transcript tells you why. This is the step people
skip, and it holds the actual causes.

Open a session that went badly, resume it, and ask the agent directly:

```
Why did you make this decision?
What in your context indicated that was the right direction?
Categorise every tool call you made in this session into groups.
  Say which groups were not useful.
```

Two triggers reliably hide a cause:

- **A run that took far longer than expected.** Ask what it spent its time on.
  Usually a loop it could not see itself in.
- **A decision that came out of nowhere.** Ask what made that look correct.
  Almost always a stale instruction in your config nobody has read in months, or
  something misread early and then faithfully followed all session.

That second one is the argument for this whole skill. A stale line does not sit
quietly. It steers.

## Step 8: close the loop, or it was not a retro

Re-run the audit after the config change, bounded to sessions since the change:

```bash
./scripts/retro-scan.sh --since <the date you changed the config>
```

Check that the rate actually moved. **An unverified fix is a superstition.**

- Compare like with like. A month of hard work against a month of easy work
  proves nothing, whichever way the number went.
- If the rate did not move, the line was wrong or was never the cause. Delete
  it. A line that failed its own test and stayed is what this skill removes.

## Red flags

- A config line was added without checking the failure it targets still happens.
- The report ranks models on correction rate with no note on who got the hard
  work.
- Overbuild and misreading intent are reported clean, and a grep did the count.
- The denominator includes tool results or subagent dispatch prompts.
- A destructive-command count became a rule with nobody opening a session to
  check the hits were real.
- Findings ranked by frequency, so a hundred cosmetic hits outranked one broken
  environment.
- The audit produced a document and no change.
- The change shipped and nobody re-ran the count.
