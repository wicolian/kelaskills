---
name: work-order-report
description: Use when an audit, review or sweep must produce something an agent can ACT on rather than read - "give the HTML to an agent and it fixes everything", a findings report with screenshots and a built-in tracker, a self-contained audit deliverable, or turning a fleet's markdown reports into one browsable file. Covers the field shape that makes a finding executable, pulling real source at build time, inlining screenshots, the localStorage tracker, and stating coverage honestly so silence is never read as clean.
---

# Work-order reports

A **report** says what is broken. A **work order** says what to change, where, to what, and how
to know it worked. Only the second one can be handed to an agent.

The acceptance test, and it is the whole skill:

> **An agent will be given this file and nothing else** — no repo tour, no conversation, no you.
> If it must ask a question, the finding has failed.

Output is one self-contained HTML file, generated from per-lane markdown, never hand-edited.

## The field shape

Every finding carries these. The four in bold are what separate a work order from a report.

```
### <surface> — <element>
severity:   blocker | major | minor | opportunity
mechanism:  <the shared cause, if this is one instance of it — else "local">
where:      path/to/file.tsx:1234        ← real, openable, the ACTUAL line
current:    <what it does now, quoted or measured>
**target:** <the exact value/component/token it should use, WITH its path>
**fix:**    <concrete enough to make without further investigation>
**donot:**  <the wrong fix — the shortcut someone will reach for>
**verify:** <an exact check: a command, or "open X, footer should be #18181b">
blast:      <every other call site this same change touches, counted — or "this one only">
shot:       `shots/L1/03-x-dark.png` dark · `shots/L1/04-x-light.png` light
```

**`blast` is what makes the file safe to hand over.** An agent that fixes one call site of a
shared component thinks it is done and breaks the other twenty. Count it from a real inventory,
never estimate.

**`donot` saves the most time.** Every codebase has a shortcut that looks like the fix and is
not: hardcoding a colour when the token is the fix, widening a selector when the scope is wrong,
swapping a component that carries behaviour its replacement lacks.

**`verify` is what lets an agent stop.** Without it, it cannot tell done from nearly done.

## Mechanisms are findings; instances usually are not

When twenty symptoms share one cause, file **one** finding for the mechanism with `blast`
naming every site. File an instance separately only if it needs work *beyond* the mechanism fix.

An agent should fix one thing and watch twenty symptoms vanish — not grind through twenty
near-identical rows. Put `mechanism:` on every instance so the report can group them, and say in
the summary which mechanisms must land **before** which instances become checkable.

## Pull the code at build time — never ask for a paste

The highest-leverage trick here. The generator reads the repo and renders the real source around
every `file:line`, with the offending line highlighted.

It cannot go stale, cannot be mistyped, and regenerates against the current tree. It also forces
`where:` to be exact, because an unresolvable path renders nothing and that is visible.

Fall back to showing the file's matching lines when no line number is given — useful, but say in
the brief that a line number is better.

See `scripts/build_report.py`.

## Screenshots: every frame, labelled, click to zoom

- **Inline as `data:` URIs.** The file must travel alone. A report with broken image links a week
  later is worthless.
- **Extract every path on the `shot:` line**, not the first. Lanes write
  `` `a.png` dark · `b.png` light · closeup `c.png` `` and the closeup and the comparison pair are
  usually the most useful frames. A parser that takes only the first throws them away — this is
  the single most common bug in this pattern.
- **Both states**, where state matters (light/dark, empty/full, error/success). One frame cannot
  distinguish "broken in dark" from "broken always", and those are different fixes.
- **Click to zoom.** A 260px thumbnail cannot show a 4px radius difference.
- Cap each image (~3 MB) so one screenshot cannot bloat the file.

## The built-in tracker

Per-finding status the reader clicks: `Open / Doing / Fixed / Won't fix`, persisted to
`localStorage`, plus a "not fixed" filter so someone working through it can hide what is done.

Three things that are easy to get wrong:

1. **Seed the state from the file** so it opens populated, not blank.
2. **Version the storage key** (`myaudit::2026-08-27`). Anyone who opened an earlier build has
   stale state that will otherwise mask every verdict — the file says fixed, their screen says
   open, and you will not find out for days.
3. **Match the shape the paint code expects.** If it reads `state[k].status`, seed objects, not
   strings. Seeding the wrong shape renders every card as untouched.

## State coverage, not just findings

A report containing only what someone looked at cannot be told apart from one where they looked
at everything and it was fine.

So generate a **static inventory** — grep the whole tree for the signal, by construction complete
— and render it beside the findings, flagging any area with signals but **no finding** as
`not reached`. Silence must never read as clean.

End every lane report with `## Checked and clean` and `## Not reached, and why`.

## Parse on a field, not on heading depth

The lane that writes the best report will use a different heading level than the others.

Key the parser off a **required field** (`severity:`) and accept `##` through `####`. Keying off
`###` alone silently dropped an entire lane's 1,053-line report in a real run, and it looked like
that lane had simply found nothing.

Normalise enum values too — `opportunity (see below)` must fold to `opportunity` or your filter
chips fragment.

## Generated, never hand-edited

Same closed loop as any tracker: the markdown is the source, the HTML is the artifact. Edit a
lane report and rebuild. A hand-edit is lost on the next build, and worse, it makes the file and
its source disagree.

Ship a `README.md` beside it saying how to regenerate, what counts as a finding, and what the
severity words mean — the file will outlive the conversation that made it.

## Files

- `scripts/build_report.py` — the generator: parser, code extraction, screenshot inlining,
  tracker, inventory section. Adapt the `PAT`/`FIELDS` constants per audit.
- `scripts/inventory.py` — the static sweep that makes coverage claims honest.
