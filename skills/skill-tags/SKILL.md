---
name: skill-tags
description: Use when a skill invocation carries a trailing -tag, such as "/graph-engineering -whatwillmattdo", "/overnight-dev -why", "fix this -ask", or "audit the repo -why -obsidian". Also use when writing a new lens, when two tags give conflicting instructions, when deciding whether something should be a new skill or a tag on an existing one, or when a run needs historical context, a question pass, an opinionated reviewer, or a learning write-back layered on top of work it already knows how to do.
---

# Skill tags

A tag is a lens. It changes **how** a skill runs. It never changes **what** the
skill is for.

```
/graph-engineering                      plan the work as a graph
/graph-engineering -why                 ...after finding out why the code is like this
/graph-engineering -why -whatwillmattdo ...and hold every gate to a stricter bar
```

The base skill still owns the job. The lens sits on top and intervenes at named
points. This is the difference between a lens and a skill: a skill can run alone,
a lens cannot run at all without a host.

## The rule that keeps this from becoming soup

**A lens may only add constraints, questions, evidence, or gates. It may never
add scope.**

If a lens makes the agent do a different job than the bare skill would have done,
it is not a lens. It is a second skill pretending to be one, and it will fight
the host for control on every run. Send it back and make it a skill.

Concretely, a lens may:

- require evidence before a decision the host would have made on a guess
- raise the bar on a gate the host already has
- add a human question the host would have skipped
- record something after the host is finished

A lens may not:

- add a deliverable
- change the definition of done
- re-order the host's phases
- decide the host's exit condition

## The four lenses

| Tag | Skill | What it adds | Runs at |
|---|---|---|---|
| `-why` | [context-archaeology](../context-archaeology) | The historical reason the code is the way it is, pulled from PRs, incidents, threads, telemetry and meetings | Before |
| `-ask` | [right-question](../right-question) | The few questions only the human can answer, after auto-answering the rest | Before decisions |
| `-whatwillmattdo` | [whatwillmattdo](../whatwillmattdo) | A stricter engineering bar at every design decision and every gate | At decisions and gates |
| `-obsidian` | [obsidian-graph](../obsidian-graph) | A typed-edge note written back so the next run starts where this one ended | After |

Full registry, including how to add one, is in [TAGS.md](../../TAGS.md).

## Order is fixed, not typed

Lenses do **not** apply in the order the user typed them. They apply in phase
order, always:

```
-why          gather evidence          nothing can depend on it yet
   |
-ask          resolve the unknowns     needs the evidence to know what is still unknown
   |
[base skill]  do the work
-whatwillmattdo   ...intervening at each decision and gate
   |
-obsidian     write back what was learned    needs the outcome
```

`-obsidian` after `-why` is the loop that makes the system get smarter: this
run's archaeology becomes next run's starting context, so the second time nobody
pays for the same dig.

This is a dependency graph, and it is the same one
[graph-engineering](../graph-engineering) describes. `-why` feeds `-ask` feeds
the work feeds `-obsidian`. Typing `-obsidian -why` changes nothing. The
resolver sorts them.

## Conflict resolution

Two lenses will eventually disagree. Resolve in this order and stop at the first
rule that decides it:

1. **Hard rules beat soft ones.** Every lens declares a `## Hard rules` section.
   Anything in it is non-negotiable and overrides advice elsewhere.
2. **Narrower scope wins.** A rule about this exact file beats a rule about the
   repo, which beats a rule about work in general.
3. **Evidence beats opinion.** `-why` found a real incident; `-whatwillmattdo`
   has a principle. The incident wins. State the override out loud.
4. **The conservative option wins.** Fewer irreversible actions, more human
   gates, smaller blast radius.
5. **Still tied? Ask.** One question, both options, your recommendation.

Never resolve a conflict silently. One line in the output: what disagreed, which
rule decided it.

## The ask budget

Lenses add questions. Three lenses each adding "just a couple" is how a run that
should have been unattended turns into an interview.

Every lens declares an ask budget in its frontmatter. The run's total is the sum,
and it is a cap, not a target:

```yaml
ask_budget: 2
```

- Over budget? Drop the lowest-value questions, do not batch them into one
  giant question with six parts.
- A question that the archaeology already answered is not a question. Delete it.
- `-ask` is the only lens allowed to spend another lens's unused budget, because
  triaging questions is its whole job.
- Zero budget means the lens must proceed on a stated assumption instead of
  asking. That is a legitimate design, not a failure.

## Cost

Lenses are not free and the bill is not obvious.

| Tag | Typical added cost | Worth it when |
|---|---|---|
| `-why` | Several minutes, many read-only calls across services | The code looks wrong and you do not know if it is load-bearing |
| `-ask` | One round trip to a human, sometimes zero | The work has a fork in it that a wrong guess makes expensive |
| `-whatwillmattdo` | 20 to 40 percent more tokens, more rework loops | The output is going to be merged, shipped, or read by other people |
| `-obsidian` | Small, and it is at the end | Anything that will be done again |

`-why` on a greenfield file is waste. The file has no history. Say so and skip it
rather than performing a dig that was always going to come back empty.

## Writing a lens

A lens is a normal skill folder with a constrained shape. Frontmatter:

```yaml
---
name: your-lens
description: Use when ... (the trigger sentence, same as any skill)
kind: lens
tag: -your-lens
phase: before | decisions | gates | after
ask_budget: 0
---
```

`phase` is what the resolver sorts on. If your lens genuinely acts at two points,
declare the earlier one and say so in the body; do not invent a compound phase.

The body must contain these four sections, with these exact headings, because
the resolver and the host agent read them by name:

**`## Intervention points`** is a table. One row per moment the lens acts.
Column 1 is a *host-independent* moment, not a step number. Good: "before the
first irreversible action". Bad: "at step 4".

**`## Hard rules`** is the short list that overrides everything. Keep it under
about six. A lens with twenty hard rules has no hard rules.

**`## When to skip`** is the conditions under which this lens should decline to
act. A lens that never declines is a tax.

**`## Handoff`** is what this lens leaves behind for the next one, in a stated
shape. `-why` leaves findings. `-ask` leaves answers and assumptions.
`-obsidian` reads both.

Then register it in [TAGS.md](../../TAGS.md).

## Resolving an invocation

`scripts/tag-resolve.sh` does the mechanical part. It finds the skill and the
lenses, rejects unknown or non-lens tags, sorts by phase, sums the ask budget,
and prints the composed brief and reading order.

```bash
skills/skill-tags/scripts/tag-resolve.sh graph-engineering -obsidian -why
skills/skill-tags/scripts/tag-resolve.sh --list
skills/skill-tags/scripts/tag-resolve.sh overnight-dev -why -ask -whatwillmattdo --brief
```

It prints a plan. It does not run anything. Read its output, load the files it
names in the order it names them, then start the host skill.

Run it when three or more lenses are stacked, or when you are unsure a tag
exists. For a single familiar lens, just read the lens and go.

## When there is no tag

Do not volunteer one. A bare `/graph-engineering` means the user wants graph
engineering, not graph engineering plus a research project.

Two exceptions, and both are a sentence, not an action:

- The work is about to touch code whose intent is genuinely unreadable. Say
  "this looks deliberate but I cannot tell why, `-why` would find out" and carry
  on with your best reading.
- The run is about to do something irreversible on a guess. That is not a tag
  suggestion, that is a stop.

## Anti-patterns

**Tag soup.** Four lenses on a two-file change. The lenses cost more than the
work. One lens, or none.

**The tag that became a skill.** If you keep writing "and then the lens does the
thing", it is a skill. Lenses constrain; they do not perform.

**Silent lensing.** Applying `-whatwillmattdo` because the code looked sloppy,
without being asked. The user gets output shaped by rules they did not opt into
and cannot see. Announce every lens in effect, once, at the top.

**Budget laundering.** Merging six questions into one numbered list to stay
inside a budget of one. The budget is on the human's attention, not on your
message count.
