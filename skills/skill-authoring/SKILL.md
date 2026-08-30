---
name: skill-authoring
description: Use when writing a new skill, when a skill never fires or the agent ignores it, when fixing a skill's description, when deciding whether something should be one skill or two, or when reviewing a set of skills for what they cost. Triggers on "write a skill", "my skill never fires", "the agent ignores my skill", "should this be one skill or two", "fix this skill's description", "review my skills".
argument-hint: "[-whatwillmattdo]"
---

# Writing a skill

A skill has to do two things: fire when it should, and be worth the context it
costs when it does. Almost every broken skill is broken at the first one.

Writing a **lens** instead? A lens modifies how another skill runs and cannot run
alone. Stop here, read [skill-tags](../skill-tags) and [the lens
template](../skill-tags/references/lens-template.md). Everything below is about
ordinary skills.

## The description is a trigger, not a description

This is the thing to get right. Everything else is second.

Here is the mechanic. **Every installed skill's description sits in context all
the time, used or not. The body loads only when the skill fires.** So the
description is not there to explain the skill. It answers exactly one question:

> When should this be pulled in?

Two things follow, and both bite.

**A description that explains the method taxes every conversation that does not
use the skill.** Twenty skills installed, nineteen wrong for this task, and you
pay for all twenty on every turn.

**Worse: a description detailed enough to be useful on its own stops the body
from ever loading.** The model reads it, decides it already has what it needs,
and acts. The skill is now permanently half-firing and it looks like it works,
because there is no error. This failure is common and badly underrated.

So write triggers. Keywords the user would really type, plus the situations that
should summon the skill.

```
Too much:
  "Monitor a pull request through review and CI, rebasing when the base moves,
   verifying automated review findings against the source, replying with reasons
   when dismissing false positives, and looping until green."

Right:
  "Use when the user asks to monitor, watch, or babysit a pull request, or to
   get one green."
```

The first is a summary of the body. It is also, accidentally, a usable set of
instructions, which is why the body never loads.

**The strip test.** Cut the description down to the triggering situations and the
words a user would actually type. Read what is left. If it still teaches the
method, cut more.

Before-and-after descriptions across skill types, plus the four anti-patterns:
[references/description-patterns.md](references/description-patterns.md).

## One skill or two

**Split when a skill has two triggers and you often want one without the other.**

Worked example, both in this repo: [file-pr](../file-pr), [babysit-pr](../babysit-pr).

| | file-pr | babysit-pr |
|---|---|---|
| Trigger | "open a PR", "write the PR description" | "watch this PR", "get it green" |
| Wanted alone? | Often. You file and walk away. | Often. The PR already exists. |

As one skill it fires on both and you always pay for both halves. Split it, put
sharp trigger keywords on each, and each fires reliably alone.

**Do not split when the second half is meaningless without the first.** If you
cannot write a trigger for the second piece that a user would type on its own,
you have not found a skill. You have found a lens, and lenses belong in
[skill-tags](../skill-tags).

## Seed a labelled bad and a labelled good

When an agent keeps producing something you dislike, a rule usually fails and a
pair of examples usually works. Show one bad output and one good output, **for
the same input**, labelled as such.

```markdown
Input: summarise this incident for the status page.

Bad:
  We experienced a partial degradation of service availability affecting a
  subset of users, and are working to identify contributing factors.

Good:
  Checkout was down for 40 minutes for about 1 in 5 users. Fixed. Cause was a
  bad cache config. Full writeup Friday.
```

Prose about quality does not transfer taste. A labelled pair does, because the
model pattern-matches the difference. Use it wherever you were about to write "be
concise" or "keep the tone professional".

## Prompt the positive

Where you would write a prohibition, state the target behaviour instead. A ban
keeps the banned thing in context, and a thing in context is more available, not
less. Say what to do, and the wrong version never gets spoken.

| Instead of | Write |
|---|---|
| "Do not write long commit messages." | "One line, under 60 characters." |
| "Never guess at the API shape." | "Read the type definition, then write the call." |

A prohibition earns its place only as a hard guardrail with no positive phrasing,
such as "never force-push to main". Even then, pair it with the target.

## Delete instructions the model already follows

An instruction that matches default behaviour costs context and buys nothing.

**The test.** Remove the sentence. Run the case. Did the behaviour change? If it
did not, the sentence was decoration. When a sentence fails, **delete the whole
sentence** rather than trimming its words. A shorter no-op is still a no-op. The
test is about the model, not about you: two people arguing over whether a line is
needed are arguing about the default, so settle it by running it.

The slow failure: files grow because adding feels safe and removing feels risky.
Left alone, a skill silts up with lines nobody has tested in a year, and the real
instructions get harder to find among them. Prune on every edit.

## Where content goes

Three tiers, and one clean test for choosing.

| Tier | Use for | Cost |
|---|---|---|
| Inline step | What the agent does, in order, on every run | Loaded whenever the skill fires |
| Inline reference | Rules and facts every path needs on demand | Same |
| Separate file behind a pointer | Depth only some paths reach | Only the pointer line |

**The test is branching.** Inline what every path through the skill needs. Push
behind a pointer what only some paths reach.

A 600-line body because one branch needed depth punishes every other branch. Move
that branch into `references/` and leave one line naming the file with the
condition for reading it, so the condition is impossible to miss: "Both sides
renamed the file? See `references/renames.md`."

## Requirements and graceful degradation

If the skill needs a binary, a credential, or a running service, say so and say
what to do when it is missing. **The rule: tell the user what is missing, rather
than guessing or silently doing half the job.** A skill that skips the deployed
check because the token was absent reports success it did not earn.

| Needs | Missing? |
|---|---|
| `gh`, authenticated | Say so and stop. There is no fallback. |
| `PREVIEW_URL` | Run the local checks only, and say the deployed check was skipped. |

Some ecosystems support a machine-readable requirements block in frontmatter, but
support varies by runtime. A human-readable requirements section in the body
works everywhere. Write that one first.

## Scripts

**House rule here: anything in `scripts/` has been run against something real.**
Written but never executed does not ship.

- **Read-only by default.** A script that writes, sends, deploys or deletes needs
  the human in the loop, and needs to say what it will touch before it touches it.
- **macOS ships bash 3.2.** No associative arrays, no `${x^^}`. Under `set -u`,
  guard array expansion as `"${arr[@]+"${arr[@]}"}"`.
- **Prefer `python3` over `jq`.** It is on the machine already.
- Keep it an accelerator, not a prerequisite. The skill still works without it.

`scripts/lint-descriptions.sh skills` flags descriptions that are too long, carry
no trigger phrasing, read as step-by-step instructions, or overlap heavily with
another skill. It changes nothing.

## Test the skill

The part everyone skips. Four passes, in this order.

**1. Trigger testing.** Write down five phrasings a real user might type. Start a
fresh session for each and check the skill fires. If it does not fire, the
description is wrong. It is not the user's job to guess your keywords.

**2. False-fire testing.** Write down three adjacent tasks that should *not*
summon it. If it fires on those, the description is too broad and it is taxing
work it cannot help.

**3. Body testing.** Run the skill on a real task and watch which instructions
the agent actually follows. The ignored ones are either badly placed or already
default. Move them or delete them.

**4. The repo gate.** `./scripts/check-skills.sh` checks frontmatter, the
folder-name match, the em-dash ban, and script syntax. Run it before opening a
pull request.

Full procedure, a worked example, how to tell "the description is wrong" from "the
model is wrong", and a pre-commit checklist:
[references/testing-a-skill.md](references/testing-a-skill.md).

## Maintenance

**A skill is written after a failure and should be revisited after the failure
stops.** The tool got better, the convention changed, the framework now prevents
that bug class. The skill still loads its description on every turn and now buys
nothing.

Use [agent-retro](../agent-retro) as the evidence source at both ends. Recurring
failures are what to write a skill about. Failures that went quiet are what to
retire.

**Retire by deleting.** Delete the folder, note what replaced it in the commit
message. A folder marked deprecated still installs, still loads its description,
still fires. Deprecation is a comment. Deletion is a change.

## Do not install someone else's whole skill collection

A collection encodes one person's failures with one set of projects and one set
of tools. Installing all of it buys real context cost aimed at problems you do
not have, plus false triggers on work that is not yours. It also skips the part
that produced the value: noticing your own failure and writing the smallest thing
that prevents it next time. That noticing is the skill. The file is only where it
got written down.

**Borrow techniques. Write your own skills.** Read
[Matt Pocock's skills](https://github.com/mattpocock/skills) (MIT) for the theory
of writing documents that agents consume, then write yours from your own receipts.

## Before you commit

- [ ] The description is triggers only. It passes the strip test.
- [ ] Five real phrasings fire it. Three adjacent tasks do not.
- [ ] Every branch-specific depth is in `references/`, behind a named condition.
- [ ] Every rule you were about to write as a ban is written as a target.
- [ ] Every instruction left in the file changed behaviour when you tested it.
- [ ] Requirements and their degradation paths are stated.
- [ ] Every script has been run.
- [ ] `./scripts/check-skills.sh` passes.
