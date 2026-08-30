---
name: agents-md
description: Use when writing, fixing or auditing the instructions file an agent reads before it changes a codebase - AGENTS.md, CLAUDE.md, or a per-project equivalent. Triggers on "write an AGENTS.md", "my CLAUDE.md is bad", "set up agent instructions for this repo", "init this repo for agents", "the agent keeps breaking my dev server", "why does my agent ignore my preferences", "the agent only fixed one of the places", "our agent instructions are just a README", or "add a glossary for agents". Also use when an agent argues back citing a file the person did not write, when its reports use words nobody on the team uses, or when a feature keeps shipping on one path only.
---

# Writing the file an agent reads first

Most agent instructions files are bad in exactly one way: **they are a README
with a different name.**

A README helps a human decide whether to use the code. An agent instructions
file helps an agent change the code without breaking it. If more than a quarter
of your file describes what the project *is*, you wrote the wrong document.

The test for every line: **can you name the failure it prevents?** If not, delete
it. An instruction the model already obeys pays context and buys nothing.

| File | Read it when |
|---|---|
| [references/template.md](references/template.md) | Writing one now. Fill-in skeletons for both the global and the project file. |
| [references/glossary-and-surfaces.md](references/glossary-and-surfaces.md) | Writing the glossary, or deriving a surface checklist for a codebase you did not write. |
| [scripts/propose-surfaces.sh](scripts/propose-surfaces.sh) | You want a first draft of the surface checklist from the repo layout. Read-only. |

## Two files, and they do different jobs

| | Global | Project |
|---|---|---|
| Lives in | Your agent's user config directory | The repository root, committed |
| Audience | Every repo you touch | Everyone in this repo, human or agent |
| Carries | Who you are, how you work, output preferences | This codebase's shape, its non-negotiables, the ways an agent hurts itself here |
| Changes when | Your taste changes | The code changes |
| Target length | Under 60 lines | Under 200 lines |

### Write the precedence into the file

Agents need this spelled out. Near the top of the project file:

```markdown
## Precedence
1. A direct instruction from the person prompting you wins over everything here.
2. This file wins over global or user-level agent instructions.
3. These are good defaults, not hard rules. If the person asks for something
   else, do that. Do not argue with them about this file.
```

That third line matters more than it looks. Without it, a contributor who never
wrote this file gets an agent that quotes it back and refuses. **An instructions
file that overrides the human is a bug.**

## Introduce yourself, in the global file

Two or three first-person sentences saying who you are and how you like to
build. This changes behaviour, for two separate reasons.

**Models tone-match.** Write in short plain sentences and you get short plain
sentences back. Write a 40-bullet policy document and you get a 40-bullet report.

**Stated preference is a brake.** A line like *"I build complex things as simply
as possible, and I like finding ways to remove complexity"* pulls harder against
over-building than any list of prohibitions. Two sentences of who you are beat
ten bans.

---

## The glossary, which almost nobody writes

Define the words your team uses. One or two sentences each. Say what a thing
**is**, not what it does.

**Start with the pronouns.** This sounds silly. It is not. In a document written
by maintainers, for an agent, about a product, three referents collide on every
line:

```markdown
- **you** - the agent reading this file.
- **we**, **us** - the maintainers of this repository.
- **the user** - the person the product serves. Not the person prompting you.
- **the operator** - the person prompting you right now.
```

Then the ten to twenty domain nouns that appear in your issues and your code.

**The point is not comprehension.** Models infer intent well enough. The point is
that the agent **describes things back to you in your words**, which is the
difference between a report you skim and one you translate.

**Be opinionated.** One word per concept, and list the rejected synonyms so the
agent stops rotating through them:

```markdown
- **record** - one stored item a user created. Not "entry", "row" or "item".
```

How to pick the words, and what to do with a term that means two things:
[references/glossary-and-surfaces.md](references/glossary-and-surfaces.md).

## What we never compromise on

Two to five properties that must survive any change. One sentence each, each one
falsifiable. This reads like marketing and is not: it tells the agent **what to
refuse.** If a change would damage one of these, the agent stops and says so
rather than proceeding and mentioning it at the end. Shapes that work:

- A performance budget. *"Cold start stays under N milliseconds."*
- A compatibility guarantee. *"Existing stored data keeps loading, with no migration a user has to run."*
- An openness commitment. *"Every dependency stays under a permissive licence."*
- An accessibility floor. *"Every interactive control is reachable by keyboard."*
- A stability promise. *"The public interface does not break in a minor release."*

If you cannot check it, it is a slogan. Cut it.

## The ways an agent hurts itself here

**This section pays for the whole file.** It is also the one you cannot invent.

| Trap | What goes wrong |
|---|---|
| Killing a process by name | The pattern matches the session the agent is running inside. It kills itself. |
| A package-manager subcommand | The obvious form quietly does something different from what it looks like. |
| Starting a dev server | It clobbers the one already running, or takes a port another service holds. |
| Writing test data | It lands in a real store instead of a scratch one. |

Write each one as **the wrong move, why it is tempting, the right move.**

Source them from real incidents, not imagination. The `agent-retro` skill in this
repository mines agent transcripts for exactly these. Run it, take the recurring
failures, write them down. An imagined trap is noise. A real one already cost you
an hour.

## Hit every surface

The most common defect in a multi-surface project is a change that works on the
path that got tested and is missing everywhere else. The fix is a checklist in
the file, plus one instruction: **walk the list and say which entries apply
before calling the work done.** Saying it out loud is what makes it happen.

```markdown
## Surfaces a feature must reach
Before you call frontend work done, walk this list and state which entries apply.

- [ ] Every entry point: menu, command palette, keyboard shortcut, settings,
      context menu, deep link
- [ ] Every client and platform we ship
- [ ] Every adapter or provider implementation. Each needs a decision, even if
      the decision is "not supported here"
- [ ] The shared contracts or types that cross a boundary
- [ ] The reverse of any state you added
- [ ] The docs
```

**Call out the reverse state specifically.** If you added a way to mute, snooze,
hide or archive, the un-mute path needs the same care and is almost never built.
It is the most commonly missed item and the easiest to check for. Repeatable
audit: [references/glossary-and-surfaces.md](references/glossary-and-surfaces.md).

`scripts/propose-surfaces.sh` drafts the list from the repo layout. A starting
point, not the answer.

## Split the docs, and say which is which

Two doc roots, two audiences, both named in the instructions file: `docs/` for
people who use the product, with no internal names, no file paths and no
implementation detail, and `docs/internal/` for people who work on it. Without
the split, agents leak implementation detail into user-facing documentation.
Small structural change, large effect, because the agent now has somewhere
correct to put what it learned.

## Commands, and the traps

Name the package manager. Give the exact commands for install, test, lint, type
check and build. Then give any command whose obvious form is wrong, because
otherwise the agent uses the obvious form forever.

```markdown
Traps
- `<obvious command>` does <wrong thing>. Use `<correct command>`.

Running a dev instance
Never use the default port or the default state directory. Another instance is
probably already running.
  <command with a separate state directory and a different port>
Record the process id when you start it. Stop that id later. Never kill by name.
```

That last line is short and prevents a genuinely bad failure: a kill pattern
that matches the agent's own session.

## Verification, and the scope of it

Say what is expected before done, **and say what is not wanted.** The second half
is the half people skip, and it is why agents produce test suites nobody asked
for.

| Wanted | Not wanted |
|---|---|
| The test command and the type check, both green | Smoke tests that assert a module imports |
| Focused tests on behaviour you changed | A regression test for every deletion |
| A one-line statement of what you verified | Rewriting passing tests so they read differently |

State the security posture proportionally too. On a local development or
maintainer-only surface, hardening against untrusted input adds complexity and
buys nothing. Name where untrusted input actually enters and say the local
surface already runs as the operator, so the agent stops defending the wrong
line.

## Blast radius

Short, blunt, and easy to find. Never without asking first:

- Production data, or anything that writes to it
- Live credentials, tokens, or the files that hold them
- Anything that costs money
- Anything that reaches a user: a send, a deploy, a publish, a push

## What does not belong

| Leave out | Why |
|---|---|
| Marketing copy | The agent is not deciding whether to adopt your project. |
| Install instructions for end users | That is the README's job. |
| A file tour | Stale in a week, and the agent can read the tree. |
| Anything the code says | The type system and `--help` are already correct and never drift. |
| Anything true by default | It costs context and changes nothing. |
| A restatement of good engineering | "Write clean code" is not an instruction. |

## Prompt the positive

Where you would write a prohibition, write the target behaviour.

| Instead of | Write |
|---|---|
| "Do not add comments everywhere" | "Comment only where the reason is not obvious from the code." |
| "Never use an escape-hatch type" | "Type every boundary. Widen inward if you must." |

A ban keeps the banned thing in context and makes it more available, not less.
Keep hard bans for the blast-radius list, where the cost of a miss is real.

---

## How to write one, and keep it honest

**Do not write it from scratch in one sitting.** You will write what you imagine
goes wrong, which is a different set from what actually goes wrong.

1. Draft the skeleton from [references/template.md](references/template.md).
2. **Audit your own agent history.** Find the places you had to correct the
   agent, the things it broke, the things it missed. That list is the real
   contents of the file.
3. Add a line only when you can name the incident it prevents.
4. Delete a line when the failure stops happening. Files rot by accretion.
5. Re-read it after any month of heavy agent use.

**The anti-pattern is copying someone else's file wholesale.** A borrowed file
aims at someone else's failures. The value was never in the lines, it was in the
reasoning that produced each one, and that does not transfer. Borrow the section
headings. Write your own contents.

## Audit a file you already have

| Check | Fail looks like |
|---|---|
| What fraction describes what the project is? | Over a quarter. Cut it. |
| Can you name the incident behind each line? | You cannot, for most of them. |
| Is precedence stated? | The agent argues with contributors. |
| Is there a surface checklist? | Features ship on one path only. |
| Would deleting half of it change any behaviour? | If no, delete half of it. |

The most useful edit available to most of these files is a deletion.
