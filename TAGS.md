# Tags

A tag is a lens. It changes **how** a skill runs, never **what** the skill is for.

```
/graph-engineering -why                 plan the work as a graph, after finding out why the code is like this
/overnight-dev -why -obsidian           QA overnight, skip the known bugs, write the new ones back
/stacked-prs -whatwillmattdo            carve the stack, held to a stricter bar
/agent-fleet -ask                       six workers, one question to the human
```

The mechanism, the conflict rules and the ask budget are in
[skills/skill-tags](skills/skill-tags). Read that before writing a lens.

## The registry

| Tag | Skill | Phase | Ask rounds | What it adds |
|---|---|---|---|---|
| `-why` | [context-archaeology](skills/context-archaeology) | before | 0 | The historical reason the code is the way it is, recovered from pull requests, incidents, chat threads, telemetry and meeting transcripts |
| `-ask` | [right-question](skills/right-question) | before | 1 | Auto-answers what it can from evidence, then asks the human only the questions that change what happens next |
| `-whatwillmattdo` | [whatwillmattdo](skills/whatwillmattdo) | decisions | 1 | A stricter engineering bar at every design decision and every gate |
| `-obsidian` | [obsidian-graph](skills/obsidian-graph) | after | 0 | Writes what was learned back to a typed-edge vault, so the next run starts where this one ended |

Ask rounds are **interruptions, not questions**. One batched round of eight
questions is one. Eight questions asked one at a time is eight.

Phase is the order lenses apply in. It is fixed and it ignores the order you
typed them:

```
before  ->  decisions  ->  gates  ->  after
```

Inside a phase, an optional `order` breaks the tie. `-why` runs before `-ask`
because the question pass reads the archaeology and deletes every question the
evidence already answered.

`-why` then `-obsidian` is the loop that makes the system get smarter. This run's
dig becomes next run's starting context, so nobody pays for the same archaeology
twice.

## Advertising the tags a skill takes

A tag does nothing at runtime. Nothing parses it. It works because `skill-tags`
is installed and tells the model what a trailing `-tag` means. That makes it a
convention, not a feature, and a convention nobody can see is a convention
nobody uses.

So every host skill that a lens genuinely improves declares the tags worth using
with it:

```yaml
argument-hint: "[-why] [-ask] [-whatwillmattdo] [-obsidian]"
```

The slash menu then shows them at the moment someone is choosing.

Three rules:

1. **Only list a lens that changes what that host does.** `-why` on a skill with
   no history to dig is noise in the menu, which is the thing the hint exists to
   fix.
2. **Lenses do not declare one.** They are the tags; they do not take them.
3. **Every bracketed tag must be a registered lens.** `./scripts/check-skills.sh`
   fails on a hint that advertises a tag nobody implements, because that puts a
   broken invocation in front of the user at the worst possible moment.

## Resolving a stack

```bash
skills/skill-tags/scripts/tag-resolve.sh --list
skills/skill-tags/scripts/tag-resolve.sh graph-engineering -obsidian -why
skills/skill-tags/scripts/tag-resolve.sh overnight-dev -why -ask -whatwillmattdo --brief
```

It prints a reading order and the total number of times the run is allowed to
interrupt a human. It runs nothing.

## Adding one

1. Read [skills/skill-tags/SKILL.md](skills/skill-tags/SKILL.md), especially the
   rule that a lens may add constraints, evidence, questions and gates, and may
   never add scope.
2. Copy [the template](skills/skill-tags/references/lens-template.md).
3. Add a row above.
4. Run `./scripts/check-skills.sh`. It validates the frontmatter, the four
   required headings, and that you registered the lens here.

## The test for whether it should be a lens at all

**Can it run alone?**

If `/your-thing` on its own makes sense and produces something, it is a skill.
If the invocation is meaningless without "...while doing what?", it is a lens.

Second check when the first is ambiguous: does it produce an artefact the host
was not going to produce? A lens that writes the deliverable has taken over the
host. Split it.
