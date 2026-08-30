---
name: work-order-report
description: Use when an audit, review or sweep must produce something an agent can ACT on rather than read - "turn this audit into something an agent can fix", "make the sweep actionable", "give the HTML to an agent and it fixes everything", a findings report with screenshots and a built-in tracker, one browsable HTML from a fleet's markdown reports, or a self-contained audit deliverable.
argument-hint: "[-obsidian]"
---

# Work-order reports

A **report** says what is broken. A **work order** says what to change, where, to what, and how
to know it worked. Only the second one can be handed to an agent.

The acceptance test, and it is the whole skill:

> **An agent will be given this file and nothing else.** No repo tour, no conversation, no you.
> If it must ask a question, the finding has failed.

Output is one self-contained HTML file, generated from per-lane markdown, never hand-edited.

## The field shape

Every finding carries these. The four in bold are what separate a work order from a report.

```
### <surface>: <element>
severity:   blocker | major | minor | opportunity
mechanism:  <the shared cause, if this is one instance of it, else "local">
where:      path/to/file.tsx:1234        <- real, openable, the ACTUAL line
current:    <what it does now, quoted or measured>
**target:** <the exact value, component or token it should use, WITH its path>
**fix:**    <concrete enough to make without further investigation>
**donot:**  <the wrong fix, the shortcut someone will reach for>
**verify:** <an exact check: a command, or "open X, footer should be #18181b">
blast:      <every other call site this same change touches, counted, or "this one only">
shot:       `shots/L1/03-x-dark.png` dark, `shots/L1/04-x-light.png` light
```

**`blast` is what makes the file safe to hand over.** An agent that fixes one call site of a
shared component thinks it is done and breaks the other twenty. Count it from a real inventory,
never estimate.

**`donot` saves the most time.** Every codebase has a shortcut that looks like the fix and is
not: hardcoding a colour when the token is the fix, widening a selector when the scope is wrong,
swapping a component that carries behaviour its replacement lacks.

**`verify` is what lets an agent stop.** Without it, it cannot tell done from nearly done.

Three optional fields the generator will render if a lane fills them in: `visible:` (yes means a
user can see it, no means it is wired in but paints nothing, which is debt rather than a defect),
`replacement:` (what the new system already has that covers this), and `looks like:` (the symptom
in plain words, which is what makes search useful).

## Mechanisms are findings; instances usually are not

When twenty symptoms share one cause, file **one** finding for the mechanism with `blast`
naming every site. File an instance separately only if it needs work *beyond* the mechanism fix.

An agent should fix one thing and watch twenty symptoms vanish, not grind through twenty
near-identical rows. Put `mechanism:` on every instance so the report can group them, and say in
the summary which mechanisms must land **before** which instances become checkable.

## Pull the code at build time, never ask for a paste

The highest-leverage trick here. The generator reads the repo and renders the real source around
every `file:line`, with the offending line highlighted.

It cannot go stale, cannot be mistyped, and regenerates against the current tree. It also forces
`where:` to be exact, because an unresolvable path renders nothing and that is visible.

A `where:` path is resolved against each `--src-root` in order, first hit wins. Pass the flag
once per candidate root, deepest first. That is the general mechanism; the list of roots is
yours.

When a lane gives no line number, `--highlight <regex>` decides which lines of the file are the
evidence worth marking. A good value is the same signal your pattern config hunts for, for
example `--highlight "from 'legacy/|withLegacyTheme"`. The default is no highlighting, which
shows the head of the file unmarked. Useful, but say in the brief that a line number is better.

See `scripts/build_report.py`.

## Screenshots: every frame, labelled, click to zoom

- **Inline as `data:` URIs.** The file must travel alone. A report with broken image links a week
  later is worthless.
- **Extract every path on the `shot:` line**, not the first. Lanes write
  `` `a.png` dark, `b.png` light, closeup `c.png` `` and the closeup and the comparison pair are
  usually the most useful frames. A parser that takes only the first throws them away. This is
  the single most common bug in this pattern.
- **Both states**, where state matters (light/dark, empty/full, error/success). One frame cannot
  distinguish "broken in dark" from "broken always", and those are different fixes.
- **Click to zoom.** A 260px thumbnail cannot show a 4px radius difference.
- Cap each image (`--max-image`, 3 MB by default) so one screenshot cannot bloat the file.

## The built-in tracker

Per-finding status the reader clicks: `Open / Doing / Fixed / Won't fix`, persisted to
`localStorage`, plus a "not fixed" filter so someone working through it can hide what is done.

Three things that are easy to get wrong:

1. **Seed the state from the file** so it opens populated, not blank.
2. **Version the storage key** (`--storage-key myaudit::2026-08-27`). Anyone who opened an
   earlier build has stale state that will otherwise mask every verdict. The file says fixed,
   their screen says open, and you will not find out for days.
3. **Match the shape the paint code expects.** If it reads `state[k].status`, seed objects, not
   strings. Seeding the wrong shape renders every card as untouched.

## State coverage, not just findings

A report containing only what someone looked at cannot be told apart from one where they looked
at everything and it was fine.

So generate a **static inventory**, grep the whole tree for the signal so it is complete by
construction, and render it beside the findings, flagging any area with signals but **no finding**
as `not reached`. Silence must never read as clean.

The signal is whatever proves an old system is still alive inside the new one. Define it for your
own codebase in a JSON pattern file, because it is different everywhere. `patterns.example.json`
ships four invented ones to show the shape: an import out of a legacy directory, a deprecated CSS
class prefix, a named compatibility shim, and a global that a newer API replaced. JSON cannot
carry comments, so here is what each key means:

| Key | Meaning |
|---|---|
| the object key | the kind name, used in the report's "by kind" table and in `mechanism:` |
| `regex` | a Python regex. One capture group if you want to count what leaked. |
| `means` | one line saying what a single hit means, rendered next to the count |
| `collect` | optional. True rolls the capture group into a "most-leaked" table. |

`--depth` sets how many path segments name a surface, and `--deepen pages,components` gives those
segments one extra level, because not every repo nests the same way. Get this wrong and every
finding collapses into one row called `src`.

End every lane report with `## Checked and clean` and `## Not reached, and why`.

## Parse on a field, not on heading depth

The lane that writes the best report will use a different heading level than the others.

Key the parser off a **required field** (`severity:`) and accept `##` through `####`. Keying off
`###` alone silently dropped an entire lane's 1,053-line report in a real run, and it looked like
that lane had simply found nothing.

Normalise enum values too. `opportunity (see below)` must fold to `opportunity` or your filter
chips fragment.

## Both scripts fail loudly

Silence is the enemy in both directions. A scan that read zero files and a scan that read
everything and found nothing print the same "0 findings" unless you make them differ:

- `inventory.py` exits non-zero when no file matched the extension filter, and says so. When it
  did read files and found nothing, it says that instead, and exits 0.
- `build_report.py` exits non-zero when lane reports exist but nothing parsed, because that is a
  parse failure, not a clean audit. A missing `inventory.json` or `--src-root` is a warning, and
  the report is built without the coverage claim.

## Generated, never hand-edited

Same closed loop as any tracker: the markdown is the source, the HTML is the artifact. Edit a
lane report and rebuild. A hand-edit is lost on the next build, and worse, it makes the file and
its source disagree.

Ship a `README.md` beside it saying how to regenerate, what counts as a finding, and what the
severity words mean. The file will outlive the conversation that made it.

## What this skill is not

**It is not the audit.** It does not find anything. It takes findings that already exist and
turns them into work an agent can execute without asking a question.

- To produce the findings by driving an app unattended and fixing what breaks, use
  **overnight-dev**. It leaves markdown behind; this skill turns that markdown into the
  deliverable.
- To fan an audit out over many surfaces in parallel and gate it, use **graph-engineering**. The
  lane reports it collects are exactly the input shape here.
- It is also not a bug tracker. The tracker in the file is for one pass through one audit. When
  the work outlives the audit, move the findings into whatever your team already uses.

## Files

- `SKILL.md` (this file).
- `scripts/build_report.py` - the generator: parser, code extraction, screenshot inlining,
  tracker, inventory section. Everything project-specific is a flag; adapt `FIELDS` per audit.
- `scripts/inventory.py` - the static sweep that makes coverage claims honest.
- `patterns.example.json` - four invented patterns showing the config shape. Copy it, replace
  every pattern with your own, and keep it in the repo you are auditing.

## Running it

```bash
# 1. what exists, repo-wide, by construction
python3 scripts/inventory.py \
  --root  src \
  --patterns patterns.json \
  --out   audit/inventory.json \
  --depth 1 --deepen pages,components

# 2. what the lanes found, turned into a work order
python3 scripts/build_report.py \
  --findings audit \
  --out      audit/work-order.html \
  --src-root src --src-root . \
  --highlight "from 'legacy/|withLegacyTheme" \
  --title "Legacy signal in the app shell" \
  --storage-key "legacy-signal::2026-08-30"
```

`--findings` expects `reports/*.md` (one file per lane, a leading `_` is ignored),
`shots/**/*.png`, and `inventory.json` from step 1.
