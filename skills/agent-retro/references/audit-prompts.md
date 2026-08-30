# Audit prompts

This file is the fan-out kit for agent-retro: when a store is too big to read in one
context, this is the prompt you hand each auditor, the shape they must answer in, and
how you merge their answers back into one number.

## Why fan out at all

A transcript store is not small. On one real machine: `~/.claude/projects` held
2,415 session files, 3.7 GB, about 5 months of history. `~/.codex/sessions` held
791 files, 2.4 GB, about 9 months. `~/.cursor/projects` held 794 files, 74 MB.

A single session file routinely exceeds 6 MB. Some exceed 50 MB. One file can fill a
whole context window by itself. You cannot read a 3.7 GB store in one pass, and you
should not try.

Split along one of two dimensions, never both loosely mixed:

- **One agent per store.** Claude Code, Codex, and Cursor are different schemas
  anyway (see SKILL.md). This split is free and always correct as a first cut.
- **One agent per date range inside a store.** Use this when a single store is still
  too big on its own, for example the 3.7 GB Claude Code store split into monthly
  slices.

Slices must not overlap. Two auditors counting the same file means a correction gets
counted twice and the merged rate is wrong in a way nobody will notice. Pick a
partition rule up front (file mtime range, or a directory boundary) and give each
auditor the exact boundary in writing.

## PRIVACY

Read this before you fan out anything. It is not a footnote.

- Fanning transcripts out to subagents means every one of those subagents now holds
  your source code, your secrets, your customer data, and your private
  conversation. That is a real widening of exposure. It is the cost of the audit,
  not a side effect you can ignore.
- Never send transcript content to a tool or model outside the boundary you already
  trust with your code. If your code stays local, the audit stays local too.
- Auditors return counts, categories, file paths, and timestamps. They return
  quoted text only when it is redacted and only when the quote is load-bearing for
  the finding. Default to no quote.
- Never paste a transcript into a public issue, a commit message, or a shared
  report without redacting it first. Assume anything pasted there is now
  permanent and searchable.
- Prefer running the audit locally, on the same machine that holds the transcripts.
  Do not upload a store to a remote service to save time.
- Reading a transcript re-exposes any secret ever printed in a session: a token
  pasted into a prompt, a key in a command, a password in a log dump. If an
  auditor surfaces one, rotate it. Do not just note it and move on.

## THE FAN-OUT BRIEF

Copy this whole block into the auditor's prompt. Fill in the two blanks (store path,
date range) before you send it. The auditor should not need to ask you anything.

```
You are auditing one slice of a coding-agent transcript store. Do not read the
whole slice line by line. Sample it, then say plainly what you sampled and what
you skipped.

SLICE
  Store path: <STORE_PATH, e.g. ~/.claude/projects>
  Date range: <START_DATE> to <END_DATE>, by file mtime
  This is your slice only. Do not read files outside this path or this date
  range, even if you find a reference to one.

SAMPLING RULE
  Read up to 40 session files in this slice, chosen by: newest 20 files, plus
  20 more spread evenly across the remaining files in the range. If the slice
  has 40 files or fewer, read all of them and say so.
  For each file, read the whole thing unless it exceeds 6 MB, in which case
  read the first 2 MB and the last 2 MB and say the file was partially read.

FAILURE CATEGORIES (use these exact names, nothing else)
  1. Destructive or wrong-target actions
  2. Tool misuse
  3. Overbuild
  4. Stopping early
  5. Unasked edits
  6. Process failures
  7. Misreading intent
  8. Regression
  9. Verification skipped

HONEST-READING RULES
  - A phrase match is a candidate, not a finding. Open the session and confirm
    intent before you count it.
  - "0" and "did not look" are different answers. If you did not sample a
    category or a file, say so. Do not report 0 for something you never
    checked.
  - A correction that was actually agreement, or a destructive command the
    human explicitly asked for, is a false positive. Do not count it.
  - Distinguish a real second attempt at the same request from a new
    unrelated request that happens to share words with the first.

WHAT TO RECORD
  For every count, keep the file path and a timestamp so the count can be
  verified later. A count with no pointer back to the transcript does not
  merge, it gets thrown out.

PRIVACY
  Return counts, categories, file paths, and timestamps only. Return a quoted
  snippet only when it is redacted (no names, no keys, no customer data, no
  full file paths beyond what is needed to locate the session) and only when
  the finding is not intelligible without it.

OUTPUT
  Fill in the OUTPUT CONTRACT below exactly. Do not add extra sections. Do
  not omit a field, use "did not look" or "0" as appropriate instead of
  leaving it blank.
```

## THE OUTPUT CONTRACT

Every auditor returns exactly this shape. A ragged shape pushes reconciliation work
into the merge step, which is where quality is already thinnest, because the
orchestrator is now reading N different report formats instead of one number per
cell.

```
SLICE ID:            <store>/<date range>
STORE:                <store path>
DATE RANGE:           <start> to <end>
SESSIONS IN SLICE:    <n>
SESSIONS SAMPLED:     <n>  (say if this is all of them)
HUMAN MESSAGES:       <n>              <- the denominator for every rate below

PER-MODEL COUNTS
  model_id            human_messages   corrections
  <model or "no model id in this store">   <n>   <n>

PER-CATEGORY COUNTS
  category                              count   examples (file : timestamp)
  Destructive or wrong-target actions   <n>     <path:ts>, <path:ts>
  Tool misuse                           <n>     ...
  Overbuild                             <n>     ...
  Stopping early                        <n>     ...
  Unasked edits                         <n>     ...
  Process failures                      <n>     ...
  Misreading intent                     <n>     ...
  Regression                            <n>     ...
  Verification skipped                  <n>     ...
  (1 to 3 example pointers per category, file path and timestamp, no quoted
   content unless redacted and load-bearing)

NOT COVERED
  <name what you could not check and why: files too large, no model id in
   this schema, date range had gaps, etc. "0" for a category you did sample
   and found nothing in; "did not look" for a category you never sampled.>
```

## THE MERGE INSTRUCTIONS

Run this in the orchestrator. Do not delegate the merge itself.

- Count expected slices against received slices before merging anything. If a
  slice is missing, name it and stop, don't fold the gap into the total silently.
  A missing slice is a hole in the count, not a zero.
- Sum denominators first, then sum numerators, then divide. Human messages
  and corrections each sum across slices before you compute any rate.
- Never average per-slice rates. A slice with 20 human messages and a slice
  with 900 human messages do not get equal weight in an average, that treats a
  thin sample the same as a thick one and produces a rate nobody's data
  actually shows. Recompute the rate from the summed totals, always.
- Rank findings by cost, not by frequency. A rare destructive action that ran
  against a wrong target outranks a common but low-cost stopping-early pattern.
  Frequency picks the loudest problem; cost picks the one that hurt the most.
- Keep every slice's confounder notes (the NOT COVERED lines, and any caveat
  about task difficulty or a partially read file) attached to the merged
  number. A clean merged total that drops the caveats reads as more certain
  than the underlying audit actually is.

## THE AUDITING MODEL MATTERS

A weaker model produces a shallower audit. It counts the phrases it was given and
misses the failure that had no keyword to match. That miss lands hardest on two
categories that need judgment rather than pattern matching: **Overbuild** and
**Misreading intent**. Neither has a reliable phrase signature; both require reading
a thread and forming a view about what the human actually wanted.

Guidance:

- Use a cheap, fast model for mechanical extraction: counting correction phrases,
  splitting date ranges, classifying a shell command as destructive or safe.
- Use your strongest available model for the categories that require reading a
  thread and forming a judgment, especially Overbuild and Misreading intent.

State plainly in the final report which model ran the audit. A "clean" result on
Overbuild from a cheap model is not the same evidence as a clean result from your
strongest model, and the reader needs to know which one they're trusting.

## Interrogating a bad session

Once retro-scan.sh or an auditor points at a specific session that went wrong,
resume that session and ask the agent itself. Use this exact wording:

- "Why did you make that decision at [point in the session]? What indicated that
  direction was correct?"
- "Categorise every tool call you made in this session into groups. Say which
  groups were not useful and why you made those calls anyway."
- "This session took much longer than expected. What did you spend your time on?"
- "At [point in the session] you made a decision that came out of nowhere. What in
  your context made that look like the right call?"

For the last one: an out-of-nowhere decision usually traces to one of two causes.
Either a stale instruction sitting in a config file that no longer applies, or
something misread early in the session that then got carried forward and followed
for the rest of the run without being re-checked.
