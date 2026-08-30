# Lens template

Copy this into `skills/<your-lens>/SKILL.md`, fill it in, then add a row to
`TAGS.md`. Delete every instruction comment before you commit.

```markdown
---
name: your-lens
description: Use when ... Trigger phrases go here, the same as any skill. Say what the lens adds, not what the host does.
kind: lens
tag: -your-lens
phase: before
order: 50
ask_budget: 0
---

# Your lens

One or two sentences. What does this lens make the host notice that it would
otherwise have walked past?

## Intervention points

| When | What this lens does |
|---|---|
| Before the first file is read | ... |
| At any decision with more than one defensible answer | ... |
| Before the first irreversible action | ... |
| After the host reports done | ... |

Moments must be host-independent. "Before the first irreversible action" works
on every host. "At step 4" works on none.

## Hard rules

Under six. These override the host and every other lens.

1. ...
2. ...

## When to skip

The conditions under which this lens should say "not applicable here" and get
out of the way. A lens that never declines is a tax on every run.

- ...

## Handoff

What you leave behind, in a stated shape, for the next lens and for the host.

```
FINDING   <one line>
SOURCE    <where it came from, so it can be checked>
CONFIDENCE high | medium | low
```
```

## Checks before you commit

- [ ] `phase` is one of `before`, `decisions`, `gates`, `after`.
- [ ] `order` is set only if another lens in your phase must run before or after
      you. Lower runs first. Leave it out otherwise.
- [ ] The lens adds no deliverable and changes no definition of done.
- [ ] `ask_budget` is a number, and you can defend it. Most lenses want 0 or 1.
- [ ] All four required headings are present, spelled exactly.
- [ ] `skills/skill-tags/scripts/tag-resolve.sh --list` shows your tag.
- [ ] Registered in `TAGS.md`.
- [ ] Your lens does NOT declare `argument-hint`. It is a tag, it does not take
      tags. Instead, add it to the `argument-hint` of each host skill it
      genuinely improves, and only those.

## Is it a lens or a skill?

Answer one question: **can it run alone?**

If a user could sensibly type `/your-thing` with no host skill and get value,
it is a skill. If the invocation is meaningless without "...while doing what?",
it is a lens.

Second check, when the first is ambiguous: does it produce an artefact the host
was not going to produce? A lens that writes the deliverable has taken over the
host. Split it.
