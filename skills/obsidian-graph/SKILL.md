---
name: obsidian-graph
description: Use when a run should leave behind what it learned instead of paying to discover it again next week. Triggers on the -obsidian tag, "write that to my vault", "remember this for next time", "save what we found to Obsidian", "check my notes before you start", "we worked this out last month and lost it", or any run that ends with a confirmed cause, a decision worth its reason, or a constraint born from a failure. Adds typed-edge notes (supersedes, depends_on, decided_by, caused, implements, references) written back to an Obsidian vault, and a cheap read of what is already known before the work starts.
kind: lens
tag: -obsidian
phase: after
ask_budget: 0
---

# Obsidian graph

This is the learning edge from [graph-engineering](../graph-engineering), made
durable. A correction edge fixes the run you are in. A learning edge fixes every
run after it, and it only works if the constraint outlives the session.

The lens has two sides and they run at opposite ends:

- **Read, at the very start.** One grep. Costs almost nothing, and it is the half
  that actually saves money, because it stops the second dig before it starts.
- **Write, after the host reports done.** One note per confirmed fact, with typed
  edges, appended, never overwritten.

`phase: after` because that is when it writes, and the resolver sorts on the
write. Do the read anyway, first, before the host reads its first file.

## Intervention points

| When | What this lens does |
|---|---|
| Before the host reads its first file | Grep the vault for the subject of the run. Put anything current in front of the host as prior context, with its confidence and its date. Say "vault: nothing on this" out loud when the answer is empty. |
| At any decision where the vault already holds a `constraint` note | Surface the constraint before the decision, not after. A constraint found afterwards is an archaeology report, not a lens. |
| After the host reports done | Write one note per confirmed fact. Nothing provisional, nothing already in git. |
| After a fact contradicts a note already in the vault | Write a new note that `supersedes` the old one. Never edit the old claim, never delete it. |
| When no vault is reachable | Write the same notes to a local directory in the repo and print where. Never silently skip the write. |

## Two transports, and the default is not the interesting one

| Path | Works when | Use it for |
|---|---|---|
| **Filesystem** | Always. Plain `.md` files in a folder. | **The default.** Read and write, attended or not. |
| **MCP over the vault plugin** | Only while the Obsidian **desktop app is open** on that vault | Semantic search, backlinks, broken and orphaned link checks, opening a note in the UI for a human |

The single operational fact that decides the design:

**There is no headless Obsidian.** The plugin that serves the vault over MCP is a
desktop-only plugin. Its HTTP server lives inside the running app. The bundled
`obsidian-cli` binary is a remote control for an app that is already running, not
a launcher: with the app closed it fails with "The CLI is unable to find
Obsidian. Please make sure Obsidian is running." There is no service, no daemon,
no launchd job that starts it.

So at 03:00, in the middle of the unattended run that most needs to record what
it learned, **the MCP path is down**. Build on the filesystem and treat MCP as
the nicer thing you get when a human is at the desk.

Two more facts worth carrying:

- The plugin exposes a Dataview-style query tool using its own reader. That tool
  existing does **not** mean the Dataview community plugin is installed. Never
  write notes whose readability depends on Dataview.
- The plugin's search index only rebuilds while the app runs. Notes written while
  the app is closed are on disk and correct, and they are **not** findable over
  MCP search until the vault is reopened. Grep finds them immediately.

### The config file is a secret

The plugin stores its live port and its bearer token in plaintext, in
`.obsidian/plugins/<plugin-id>/data.json` inside the vault.

- Never commit that file. Never paste it, or any part of it, into a prompt.
- Never echo the token or the port into a log, a report, or a note.
- Read it at run time into an environment variable, use it, and let it die with
  the process.
- If the vault itself is a git repo, `.obsidian/plugins/*/data.json` belongs in
  `.gitignore` before anything else happens.

Also leave `.obsidian/workspace.json` alone. It is UI state, it is rewritten by
the app constantly, and touching it does nothing except create conflicts.

## The note shape

One fact, one note, one file. Frontmatter carries the machine-readable part,
the body carries the claim in a sentence a human can read in a file list.

```markdown
---
type: constraint
status: current
confidence: high
source: "run 2026-01-14 /graph-engineering -why; evidence: ci log line 412, worker.ts:88"
date: 2026-01-14
tags: [agent/learned, type/constraint, domain/queue]
supersedes: ["[[queue-worker-retry-cap-is-3]]"]
depends_on: ["[[upstream-rate-limit-policy]]"]
decided_by: ["[[retry-policy-decision]]"]
caused: ["[[nightly-batch-ban-incident]]"]
references: ["[[queue-worker-module]]"]
---

# queue worker retry cap is 5

The queue worker caps retries at 5. The upstream raised its failure allowance
from 5 to 10 per minute, so the old cap of 3 is now costing throughput for no
safety.

**Source.** run 2026-01-14; evidence: upstream changelog, `worker.ts:88`

**Wrong when.** The upstream publishes a lower failure allowance, or the client
starts sharing a quota with another service.
```

| Field | Values | Why it exists |
|---|---|---|
| `type` | `constraint`, `decision`, `cause` | Three kinds of thing are worth keeping. Everything else is a log. |
| `status` | `current`, `superseded` | The only field ever edited in place, and only on the one direct predecessor. |
| `confidence` | `high`, `medium`, `low` | `high` means it was observed. `low` means it was inferred once and never retested. |
| `source` | free text | Run, date, and the evidence: a file and line, a log line, a changelog. A claim with no source is a rumour. |
| `date` | `YYYY-MM-DD` | When it was believed, not when it was true. |
| `tags` | `agent/learned`, `type/<type>`, plus a domain tag | Hierarchical, so an existing vault's tag pane does not fill up with strangers. |

**`agent/learned` on every note without exception.** It is the one handle that
lets a human select, review, or delete everything an agent has ever written,
without hunting.

## Edge syntax: frontmatter, not inline fields

Six edge types, and no others. Do not invent a seventh.

| Edge | Reads as | Use for |
|---|---|---|
| `supersedes` | this note replaces that one | The fact changed. This is the only way a note becomes wrong. |
| `depends_on` | this is only true while that is | A constraint that rests on another constraint. |
| `decided_by` | this exists because of that decision | A constraint or behaviour traced to the call that created it. |
| `caused` | this produced that outcome | A confirmed cause pointing at the failure it caused. |
| `implements` | this is the code shape of that decision | A module, a config, a policy in practice. |
| `references` | related, no direction claimed | The weak edge. Everything you cannot justify as one of the five above. |

The syntax is a **wikilink inside a frontmatter field**, flow style, one line:

```yaml
supersedes: ["[[queue-worker-retry-cap-is-3]]"]
caused: ["[[nightly-batch-ban-incident]]", "[[oncall-page-2026-01-11]]"]
```

Not the inline `key:: value` form. The reasoning:

- Dataview **is not guaranteed installed**. Without it, `key:: value` renders as
  literal junk in reading view and queries nothing. A frontmatter field renders
  as a native property in every Obsidian install since properties shipped.
- Obsidian resolves wikilinks in frontmatter. The edges appear in the graph view,
  in backlinks, and in the plugin's `get_outgoing_links`, with no plugin at all.
- Flow style keeps one edge type on one line, so a plain `grep` is a one-liner
  rather than a multi-line parse.
- One canonical place. Repeating the edges in the body as prose guarantees the
  two copies drift.

Body prose may contain ordinary `[[wikilinks]]`. Those are untyped and count as
context, not as edges.

## Temporal truth: never delete, always supersede

Facts expire. A vault that handles that by editing the wrong note in place
destroys the only interesting part: that somebody once believed the other thing,
for a reason, and what changed.

The mechanism is one rule:

> **A fact that turned out wrong is never deleted or rewritten. A new note is
> written that `supersedes` it, and the old note's `status` flips to
> `superseded`.**

That single field flip is the one in-place edit this lens is allowed. Everything
else is append-only.

How a reader knows what is current:

```bash
# every fact still believed
grep -rl --include='*.md' '^status: current$' "$VAULT_DIR/$VAULT_SUBFOLDER"

# what replaced this note, and why
grep -rn --include='*.md' 'supersedes:.*queue-worker-retry-cap-is-3' "$VAULT_DIR"
```

Two belts, deliberately. `status` is the fast read. The `supersedes` chain is the
one that is still correct if a status flip was ever missed, because it is derived
from the notes themselves. When they disagree, the chain wins.

Read a chain backwards and you get the reasoning trail: cap of 3, because of a
ban; cap of 5, because the upstream allowance moved. The second note alone would
have told the next run *what*, and left it to rediscover *why* the first number
was ever chosen.

## What is worth writing

A vault that records everything is a vault nobody reads, and an unread vault is
worse than none, because it still costs a read at the start of every run.

One test:

> **Would the next run make a worse decision without this note?**

If the answer is no, do not write it. Then the second test: **is it already
recorded by the repo, the git history, the PR, or the issue tracker?** If yes,
the vault copy is a stale duplicate the day it is written.

| Write it | Do not write it |
|---|---|
| A **confirmed** cause: you saw the failure, you saw the fix, you saw it go green | A hypothesis you did not test |
| A decision, its reason, and the option you rejected | A summary of the work you did |
| A constraint a failure taught you: a real rate limit, an ordering that must hold, a version floor | A restatement of what the code plainly says |
| Behaviour of an external system that has no home in this repo | Anything the git log, the PR body, or the issue already records |
| A number somebody measured | A number you estimated |
| A dead end, with the reason it is dead | "Refactored the auth module" |

Volume is the tell. **Three notes from a long run is normal. Ten means you
started logging.** If a fact does not survive the sentence "the next run will do
worse without this", it was a log line.

## The read side

Do this first, before the host reads anything. It is cheap enough that skipping
it is never the optimisation.

**Filesystem, always available:**

```bash
: "${VAULT_DIR:?set VAULT_DIR to the vault root}"
SUB="${VAULT_SUBFOLDER:-Agent/Learned}"

# what do we already know about X
rg -il --glob '*.md' 'retry|rate limit' "$VAULT_DIR/$SUB"

# current facts only, newest belief first
rg -l --glob '*.md' '^status: current$' "$VAULT_DIR/$SUB"

# every constraint, whatever the subject
rg -l --glob '*.md' '^type: constraint$' "$VAULT_DIR/$SUB"

# edges out of one note
rg -N '^(supersedes|depends_on|decided_by|caused|implements|references):' "$VAULT_DIR/$SUB/<slug>.md"

# backlinks without the app: who points at this slug
rg -n --glob '*.md' '\[\[<slug>\]\]' "$VAULT_DIR"
```

Swap `rg` for `grep -rn --include='*.md'` where ripgrep is not installed. Both
were run against a real vault built by the bundled script; both work.

**Over MCP, only when the desktop app is open:** `search_vault_simple` for text,
`get_backlinks` and `get_outgoing_links` for the typed edges, `get_vault_file`
or `get_vault_file_partial` to read one note, `find_orphaned_notes` to spot
learned notes nothing ever linked to. `execute_dataview_query` is available from
the plugin's own reader, so it works for reading even with no Dataview plugin
installed. Do not make writing depend on any of it.

Feed the host the result in one block, not as a file dump:

```
VAULT   3 current notes on this subject, 1 superseded
KNOWN   worker retries cap at 5 (constraint, high, 2026-01-14)
KNOWN   the nightly batch shares the upstream quota (cause, medium, 2025-11-02)
STALE   cap of 3 (superseded by the above)
```

## Hard rules

1. **Never write outside the configured vault subfolder.** One folder,
   `$VAULT_DIR/$VAULT_SUBFOLDER`, or the degraded directory. Never at the vault
   root, never into a human's own folders, never into `.obsidian/`.
2. **Never write a secret or a person.** No tokens, keys, ports, connection
   strings, customer names, employer names, personal data, or anything pulled out
   of a private chat or a support thread. If a fact cannot be stated generically,
   it does not get written.
3. **Append only.** One note per fact. Never bulk-rewrite, never delete, never
   reword an existing claim. The single permitted in-place edit is flipping
   `status: current` to `status: superseded` on the one direct predecessor.
4. **No source, no note.** Every note carries the run and the evidence that
   proves it. An unsourced claim is indistinguishable from a hallucination six
   weeks later, and it will be read as true.
5. **Never silently do nothing.** If the vault is unreachable, degrade to the
   local directory and print the path. A lens that quietly skipped its only job
   is worse than one that failed loudly.
6. **Confirmed only.** Nothing provisional, nothing assumed, nothing a lens
   upstream marked as an assumption rather than a finding.

## When to skip

- **No vault and no repo to fall back into.** Say so in one line and stop.
- **The run learned nothing.** A run that read three files and changed a string
  has no fact worth a note. Say "nothing worth writing" rather than manufacturing
  one, and get out of the way.
- **Everything learned is already in git.** The diff, the commit message and the
  PR body are the record. Do not shadow them.
- **The facts are unconfirmed.** The host guessed, or the work was reverted, or
  the test never went green. Write nothing. A wrong note read confidently next
  month costs more than the discovery you are trying to save.
- **The subject is a person, a customer, or anything private.** Skip the whole
  write. Do not attempt a redacted version.
- **A folder-level sync is mid-conflict.** iCloud, Dropbox or Obsidian Sync with
  the app closed can turn a bulk write into conflict copies. Write one note, or
  degrade locally, and say why.

## Handoff

**What this lens consumes.** From `-why` ([context-archaeology](../context-archaeology)),
records of this shape:

```
FINDING     <one line: the reason, stated as a fact>
SOURCE      <the exact permalink, PR url, issue id or commit sha>
CONFIDENCE  stated | inferred | absent
DECIDES     <what this changes about the plan, or "nothing">
```

`-why` says how it knows, not how sure it feels, which is the more useful thing.
Translate on the way in:

| From `-why` | Becomes |
|---|---|
| `FINDING` | the note body, and the title |
| `SOURCE` | `source:` |
| `CONFIDENCE: stated` | `confidence: high`. A person wrote the reason down. |
| `CONFIDENCE: inferred` | `confidence: medium`. Reconstructed from evidence. |
| `CONFIDENCE: absent` | **not written at all.** See below. |
| `DECIDES` | nothing in the note. It is for the host skill, not the vault. |
| (judgement) | `type:` is `constraint`, `decision` or `cause`. A finding that fits none of the three is not written. |

**Why `absent` does not become a note.** A vault that records every dead end
stops being a signal. `absent` means the dig was done properly, with controls,
and the reason was never recorded anywhere. That belongs in the run output so the
host knows it is acting without a recorded reason. It does not belong in a
knowledge base as a fact, because it is the absence of one.

The one exception is worth naming: if the dig was expensive and is likely to be
repeated, record the *search* rather than the finding. "Searched PRs, incidents
and threads for the reason behind X on <date>, found nothing" is a constraint on
future effort, and it is written as `type: constraint`, `confidence: low`.

From `-ask`, only the **answers** are eligible. A stated assumption is not a
fact. It gets written only if the run confirmed it, and then the confirmation is
the source, not the assumption.

**What this lens leaves behind**, one block at the end of the run:

```
WROTE     queue-worker-retry-cap-is-5   type=constraint confidence=high
EDGES     supersedes=queue-worker-retry-cap-is-3  caused=nightly-batch-ban-incident
LOCATION  <vault>/Agent/Learned            (or: degraded, ./.agent-notes)
SKIPPED   4 candidates: 3 already in git, 1 unconfirmed
```

The `SKIPPED` line is not padding. It is the evidence that the filter ran, and it
is the line that shows a vault getting a signal instead of a log.

## Writing a note

```bash
scripts/vault-note.sh \
  --claim "The queue worker caps retries at 5; the upstream raised its allowance to 10 per minute." \
  --type constraint --confidence high \
  --source "run 2026-01-14 /graph-engineering -why; evidence: upstream changelog, worker.ts:88" \
  --title "queue worker retry cap is 5" \
  --tag domain/queue \
  --edge caused=nightly-batch-ban-incident \
  --edge decided_by=retry-policy-decision \
  --falsified-by "the upstream publishes a lower failure allowance" \
  --supersede
```

It refuses to clobber. A second run with the same title exits 3 and tells you to
either pass `--supersede` or give the note its own title. With `--supersede` it
writes the next note in the chain and flips exactly one line in the predecessor.
It validates the edge vocabulary, so a typo cannot invent a seventh edge type.

## Degraded mode

No `VAULT_DIR`, or the path does not exist: the script writes the identical note
shape to `./.agent-notes/` in the repo and prints the path on stderr.

The notes are correct markdown with correct frontmatter and correct wikilinks.
Nothing about the format is downgraded, only the location. When a vault appears
later, move the folder into `$VAULT_DIR/$VAULT_SUBFOLDER` and every edge
resolves, because the edges are slugs and not paths.

Commit `.agent-notes/` or ignore it, your call, but decide once. Hard rule 2
means there is nothing in it that cannot be committed.

## Adopting this in a vault that already has conventions

Most vaults already have a shape, usually one of two:

- **The entity graph.** Notes are things (organisations, people, meetings) with
  `type` and `status` frontmatter, hierarchical tags like `#status/done`, and
  heavy wikilinking between them.
- **The numbered docs vault.** Ordered folders, an entrypoint note that tells an
  agent where to start, prose over properties.

Do not reshape either one. Take one subfolder, use the vault's existing
frontmatter keys where they mean the same thing, and add only what is missing.
Full detail in [references/vault-conventions.md](references/vault-conventions.md).

## Files

- `scripts/vault-note.sh` - write one typed-edge note, append-only, refuses to
  clobber, degrades to a local directory. Bash 3.2 clean.
- `references/vault-conventions.md` - the taxonomy, the folder layout, the tag
  scheme, and how to land this in a vault that already has its own conventions.
