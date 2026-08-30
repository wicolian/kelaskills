---
name: context-archaeology
description: Use when code looks wrong and you cannot tell whether it is a mistake or a scar. Triggers on the -why tag, and on "why is this code like this", "is this load-bearing", "who decided this", "find the incident that caused this", "is this safe to delete", "what was this hack for", "there must be a reason someone wrote it this way", "check the pull request before you touch it", or "did we already try this". The -why lens recovers the recorded reason from commits, pull requests, incidents, chat threads, telemetry and meeting transcripts, before the host skill acts on a guess.
kind: lens
tag: -why
phase: before
ask_budget: 0
---

# Context archaeology

An odd line of code has two readings and they demand opposite actions. It is a
mistake, and you fix it. Or it is a scar, and touching it re-opens the wound that
put it there.

**The repository cannot tell you which.** The reason is almost never in the code.
It is in the pull request discussion, the commit that caused it, the incident that
forced it, the thread where it was argued, the metric that regressed, or the
meeting where it was decided. This lens goes and gets it, before the host acts.

`ask_budget: 0` is deliberate. Archaeology finds facts, and a fact is never a
question for a human. When the reason was not recorded, say so plainly and let the
host proceed with that stated.

| File | Read it when |
|---|---|
| [references/sources.md](references/sources.md) | Calling a source. Exact calls, exact parameter names, syntax that works, syntax that silently does not, and a failure table per source. |
| [references/no-evidence.md](references/no-evidence.md) | About to write "no evidence". The control-query protocol, and which sources give an honest zero. |
| [scripts/why-line.sh](scripts/why-line.sh) | Starting a dig. Runs wave 1 and wave 2 for one file and one line. |

## Four waves, and most digs end in the second

Fire everything inside a wave at once. Move to the next wave only when the current
one has not answered it.

### Wave 1: local, free, instant

```bash
SHA=$(git blame -L 28,28 --porcelain -w -M -C path/to/file.ts | head -1 | cut -d' ' -f1)
git show -s --format=%B "$SHA"
gh api "repos/<owner>/<repo>/commits/$SHA/pulls" --jq '.[0].number'
```

**Read the full commit message before any network call.** It answers the question
outright maybe a third of the time and costs nothing. Agents skip it because it
feels too easy.

Blame hygiene, every time: pass `-w -M -C` (ignore whitespace, follow moves and
copies) and check the repo root for `.git-blame-ignore-revs`. Landing on a squash
or merge commit is fine; `commits/$SHA/pulls` still resolves it.

### Wave 2: the pull request

```bash
gh pr view "$PR" --repo <owner>/<repo> --json title,url,body,closingIssuesReferences
gh api "repos/<owner>/<repo>/pulls/$PR/comments" --jq '.[] | "\(.user.login) @\(.path):\(.line): \(.body)"'
gh api "repos/<owner>/<repo>/pulls/$PR/reviews"  --jq '.[] | {user:.user.login,state:.state,body:.body}'
```

**`closingIssuesReferences` lies by omission.** On a traced pull request it came
back `[]` with zero cross-reference events in the timeline, and the real reason was
prose in the body linking a prior pull request. Always grep the body yourself:

```bash
gh pr view "$PR" --repo <owner>/<repo> --json body --jq '.body' \
  | grep -oE '(#[0-9]+|https://github\.com/[^ )]+/(issues|pull)/[0-9]+)' | sort -u
```

**Stop here when the body or a review comment states the reason.** Most of the
time it does. `scripts/why-line.sh <file> <line>` runs both waves and prints all
of it, and it names what it could not reach rather than reporting silence.

### Wave 3: branch on what the code looks like

Do not fan out to everything. **Read the line, then pick.** Seed whatever you pick
with the same terms: the pull request title, its merge date, the symbol on the
line, and the file path.

| The code looks like | Go to | It answers |
|---|---|---|
| A feature-flag or experiment branch | Product analytics | Who flipped it, when, and whether the metric moved |
| Defensive work: a retry, an odd timeout, a guard clause, a clamp, a try/catch | Error tracking | The incident that forced it |
| UI, with a visual or behavioural oddity | Bug recordings, filtered by page URL | The report that started it |

The best return per token on this page is in the first row. A flag's **`name`**,
not its key, is free text, and people write the rationale into it: what it gates,
the document it implements, the rollout, the default. One call. And a `status` of
`STALE` means the branch is dead code and the decision is already made.

Error tracking also runs backwards. An issue carries a stack trace **with source
context** and a `release` tag that is a 40 character commit sha, which makes an
incident a legitimate **entry point to wave 1**, not only a corroborator.

### Wave 4: the argument, and then the slow calls

Chat search belongs here, not in wave 3. It is where the **argument** lives, and
you want it when the pull request recorded the outcome and not the reasoning. Bound
it to the week before the merge, and read the thread by its **parent** timestamp.

Then, only on a specific lead: a channel time window when you know the date,
network requests and user events from a named recording, automated root-cause
analysis on one named issue. Meeting transcripts come **last**, because they are
the only source whose silence means nothing at all: search, then summary, then the
transcript region the summary timestamps point at.

## The stopping rule

**Stop as soon as one source gives an explicit statement of intent from a person.**
Do not run the rest to corroborate. A stated reason does not get more true because
a second system also mentions it, and you are spending someone's rate limit.

**A zero is not finished.** Chat search and meeting search cannot distinguish a bad
query from an empty one; their zeroes are byte-identical either way. Error tracking
looks the same but is not: it echoes the query it actually ran, so a zero there is
real **once you have read the echo and found your filter in it**. Code-host search
returns `[]` on syntax it dislikes, so query it through the API form that returns
`total_count`.

Run one control query per source that returned zero, per
[references/no-evidence.md](references/no-evidence.md), and only then write that
the reason was not recorded.

## What to fire speculatively, and what needs a lead

| Fire speculatively | Only on a specific lead |
|---|---|
| Local git: blame, `log -S`, `log -L`, `show`, `tag --contains` | Code-host search, which has a 30 per minute ceiling |
| Commit-to-pull-request, pull request view, inline comments (5000 per hour) | Reading a full chat thread, or a channel time window |
| Product analytics: flag definition and `name`, annotations, flag list | Error-tracking event aggregations, one of which timed out |
| Error tracking: issue search, issue detail | Automated root-cause analysis, which takes 2 to 5 minutes |
| Chat search, concise format, context off | Trend queries, and full meeting transcripts |
| Bug recordings: list, details, console logs | Recording network bodies, and user-event dumps |

Three calls can swallow a context window on their own: a recording tool's
user-event dump, which repeats full CSS class lists twice per event; a rangeless
blame, which returns a whole file when you wanted one line; and chat search with
its default context, which roughly triples the payload.

## Intervention points

| When | What this lens does |
|---|---|
| Before the host reads its first file | Run wave 1 on the lines the host is about to change. The commit message is free and often decisive. |
| Before the host calls any line a mistake | Produce the recorded reason, or state plainly that it is `absent`. A guess about intent is not allowed to stand unchallenged. |
| At any decision that rests on why the code is the way it is | Put the finding in front of the decision, with its source, so it can be checked instead of trusted. |
| Before the first irreversible action on old code | Confirm the change is not undoing a fix. A deletion with an `absent` finding is a smaller claim than a deletion with a stated one. |
| When the host is about to repeat an approach | Say if it was tried and reverted, and name the commit or thread that reverted it. |

## Hard rules

1. **Never write, send, comment, post, resolve or deploy from this lens.** It is
   read only, always, in every system it touches, with no exceptions. The write
   tools sit in the same list as the read ones, so
   [references/sources.md](references/sources.md) names them per source under
   "Never call". Read that list, do not rely on remembering this line.
2. **Always ask the error tracker to explain its query, and read the echoed query
   back.** An invalid field name is silently stripped and the search then runs
   unfiltered. If your filter term is missing from the echo, the results are not
   evidence, they are the default. Read the echo and a zero there becomes
   trustworthy; skip it and even a hit is unverified.
3. **Parse the thread timestamp out of the permalink. Never pass the matching
   message's own timestamp.** Both calls succeed. One returns the real thread, the
   other returns one reply and the words "no thread messages".
4. **A zero from chat search or meeting search is inconclusive until a control
   query proves the path works.** Same for an unechoed error-tracking zero and for
   any `[]` from code-host search. Only a proven path turns a zero into `absent`.
5. **Never echo anything that looks like a credential**, and never quote an
   error-tracking issue title verbatim. One real title held a provider key masked in
   the middle and not at the ends. Write `[REDACTED]`, or cite the issue short id.
6. **Stop at the first stated reason from a person.** Corroboration is not
   evidence, it is spend.

## When to skip

- **The file has no history.** Greenfield code, a first commit, a generated file, a
  vendored dependency. There is no archaeology to do. Say "no history, skipping
  `-why`" and get out of the way rather than performing a dig that was always going
  to come back empty.
- **The commit message already answered it.** Wave 1 is the whole run. Report the
  finding and stop; do not open a single network call to confirm what you can
  already read.
- **The host is about to delete the code anyway,** and the deletion is agreed and
  reversible. Why dead code existed changes nothing about removing it.
- **The change is mechanical and intent-free.** A rename, a formatter pass, a
  dependency bump with no behaviour change.
- **A prior run already recorded it.** A current vault note on this file or this
  decision is the answer. Do not pay for the same dig twice.

Say the skip out loud, in one line. A silent skip looks like a lens that failed.

## Handoff

One block per finding. The host acts on it and `-obsidian` writes it back.

```
FINDING    <one line: the reason, stated as a fact>
SOURCE     <the exact permalink, PR url, issue id or commit sha>
CONFIDENCE stated | inferred | absent
DECIDES    <what this changes about the plan, or "nothing">
```

| Field | What it must hold |
|---|---|
| `FINDING` | The reason, in one sentence, as a fact and not as a hedge. "The retry cap is 3 because the upstream banned the service at 5" and not "it seems the cap may relate to rate limits". |
| `SOURCE` | One thing a reader can open: a permalink, a pull request url, an issue short id, a commit sha. Not "the team chat". A finding whose source cannot be opened is a rumour. |
| `CONFIDENCE` | How you know, not how sure you feel. See below. |
| `DECIDES` | What changes about the plan. `nothing` is legitimate and common, and writing it is what stops the lens inflating its own value. |

The three confidence values say **how you know**, which is more useful than a
level:

- **`stated`**: a person wrote the reason down and you are quoting them.
- **`inferred`**: you reconstructed it from evidence nobody wrote as a reason. A
  commit next to an incident, a flag flipped the same hour, a metric that recovered.
- **`absent`**: you looked properly, ran the controls, and it is not recorded
  anywhere you can reach.

**`absent` is a real finding and it must be reported, never swallowed.** It is the
difference between "this line is unexplained" and "nobody checked". The first makes
the host lower its confidence and widen its tests. The second lets the host change
the line believing nothing was there. Silence also sends the next run down the same
empty dig.

### Feeding the vault

`-obsidian` writes these back as typed-edge notes. Its edge vocabulary, its note
shape and its `--edge TYPE=SLUG` writer are defined in
[obsidian-graph](../obsidian-graph/SKILL.md), under "Edge syntax" and "The note
shape". Do not restate them; map onto them.

| Finding shape | Edge |
|---|---|
| The reason changed, and the old recorded reason is now wrong | `supersedes` |
| This behaviour holds only while another constraint holds | `depends_on` |
| A pull request, a review or a meeting made the call | `decided_by` |
| A commit or a change produced an incident or a regression | `caused` |
| This file or config is the code shape of a decision | `implements` |
| Related, and you cannot justify one of the five above | `references` |

Two mechanical details the two lenses must agree on. The writer takes a **bare
slug** in `--edge TYPE=SLUG` and rejects wikilinks. Its `--type` is `constraint`,
`decision` or `cause`, so **a finding that fits none of those three is not vault
material**; report it in the run and let it end there.

Confidence maps across like this:

| This lens | `-obsidian` |
|---|---|
| `stated` | `high` |
| `inferred` | `medium` |
| `absent` | **not written to the vault at all** |

`absent` stays out of the vault because a vault that records every dead end stops
being a signal and becomes a log of failed searches. It is reported in the run
output, where it does its job: the host learns the reason was never recorded, and
a future run learns not to repeat the dig blind.
