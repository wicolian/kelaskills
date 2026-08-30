# Fill-in templates

Two skeletons. **A** is the global file that applies to every repository you
touch. **B** is the project file that ships in one repository.

How to use them:

1. Copy the block. Keep the section order.
2. Fill every `[bracket]`. **Delete any section you cannot fill with something
   specific.** An empty section is worse than a missing one, because it looks
   answered.
3. Delete the `<!-- -->` notes once the section is written. They exist to tell
   you what belongs there, not to ship.
4. Read the result top to bottom and delete every line whose failure you cannot
   name.

---

## A. The global file

Goes in your agent's user configuration directory. Target: under 60 lines.

````markdown
# Working with me

<!-- Two or three first-person sentences. Who you are, how you like to build.
     This sets tone, and models tone-match. Not a job title. Not a bio. -->

I am [role, in plain words]. I work mostly on [domains].
I build complex things as simply as possible, and I like finding ways to
[reduce complexity / remove code / delete features].
[One more sentence of taste, if you have one worth stating.]

## Precedence

<!-- Say it out loud. Agents need the ordering spelled out. -->

A project's own instructions file wins over this one. A direct instruction from
me wins over both. Everything here is a default, not a rule.

## How to talk to me

<!-- Output preferences. Length, format, what to lead with.
     Not: "be helpful". Not: "be accurate". Those are free. -->

- Lead with what changed and whether it works. Details after.
- [Target length, e.g. "under ten lines unless I ask for more"].
- When I have to decide something: [N] options, the context to pick fast, and
  which one you would take.
- Give exact paths and exact commands. No paraphrased shell.

## How I like work done

<!-- Working agreements. Each line should change what the agent does.
     Delete anything the model already does by default. -->

- Done means done. [N] things asked is [N] things delivered. If one is blocked,
  finish the rest and name the specific blocker in one sentence.
- Reversible and cheap: do it, then tell me. Ask first only for [the things you
  actually want asked about].
- A question is a question. When I ask "should we X", answer. Do not do X.
- [Anything else that has cost you a correction more than twice.]

## Things I do not want

<!-- Keep this short. Prefer stating the target behaviour above.
     A ban keeps the banned thing available. -->

- [Specific output habit you keep correcting.]
- [Specific over-building habit you keep correcting.]
````

---

## B. The project file

Goes in the repository root, committed. Target: under 200 lines. Push depth into
linked documents rather than growing this one.

````markdown
# [Project name] - working in this repository

<!-- One or two sentences of orientation, no more. Enough to disambiguate
     the domain nouns below. This is NOT the README. No pitch, no install
     instructions, no feature list, no file tour. -->

[What this is, in one sentence.] [Who it is for, in one sentence.]

## Precedence

<!-- The three-line ordering. Do not skip line 3 or contributors get an agent
     that argues with them. -->

1. A direct instruction from the person prompting you wins over everything here.
2. This file wins over global or user-level agent instructions.
3. These are good defaults, not hard rules. If the person asks for something
   else, do that, and do not argue with them about this file.

## Words we use

<!-- Say what a thing IS, in one or two sentences. Pronouns first: they collide
     constantly in an agent-facing document. Then the domain nouns. Pick one
     word per concept and list the rejected synonyms.
     Not a data dictionary. Not every type in the codebase. -->

- **you** - the agent reading this file.
- **we**, **us** - the maintainers of this repository.
- **the user** - the person [the product] serves. Not the person prompting you.
- **the operator** - the person prompting you right now.
- **[domain noun]** - [what it is]. Not "[rejected synonym]" or "[rejected synonym]".
- **[domain noun]** - [what it is].
- **[domain noun]** - [what it is].

## What we never compromise on

<!-- Two to five. One sentence each, each one falsifiable. This tells you what
     to REFUSE. If a change would damage one of these, stop and say so.
     Not a values statement. If you cannot check it, cut it. -->

- [Property]. [The measurable form, e.g. "under N ms", "no user-run migration"].
- [Property]. [Measurable form.]
- [Property]. [Measurable form.]

If a change you are asked for would damage one of these, stop and say so before
you write it.

## Ways you can hurt yourself here

<!-- The section that pays for this file. Source it from real incidents, not
     imagination. Format: the wrong move, why it is tempting, the right move.
     Generic shapes to look for: killing a process by name, a package-manager
     subcommand that is not what it looks like, a dev server that clobbers a
     running one, test data written to a real store. -->

- **[Wrong move].** [Why it looks correct.] Do [right move] instead.
- **[Wrong move].** [Why it looks correct.] Do [right move] instead.
- **[Wrong move].** [Why it looks correct.] Do [right move] instead.

## Surfaces a feature must reach

<!-- Walk this list and STATE which entries apply before calling work done.
     Saying it out loud is what makes it happen.
     Derive the list from the repo, not from this template. -->

- [ ] Entry points: [menu, command palette, keyboard shortcut, settings, deep link]
- [ ] Clients and platforms: [list them]
- [ ] Adapters or providers: [list them]. Each needs a decision, even if the
      decision is "not supported here"
- [ ] Shared contracts or types: [where they live]
- [ ] **The reverse of any state you added.** [If you added a way to mute, hide,
      snooze or archive, the un-do path needs the same care.]
- [ ] Docs: [which root]

## Commands

<!-- Exact. Include any command whose obvious form does the wrong thing.
     Do not list what `--help` already says. -->

Package manager: **[name]**. Do not use another one.

| Task | Command |
|---|---|
| Install | `[exact]` |
| Test | `[exact]` |
| Lint | `[exact]` |
| Type check | `[exact]` |
| Build | `[exact]` |

Traps:

- `[obvious command]` [does the wrong thing]. Use `[correct command]`.
- `[obvious command]` [does the wrong thing]. Use `[correct command]`.

### Running a dev instance

Never use the default port or the default state directory. One is probably
already running and you will clobber it.

    [command with a separate state directory and a non-default port]

Record the process id when you start it, and stop that id later. Never stop a
process by matching its name.

## Docs

<!-- Two roots, two audiences, named. Without this, internal detail leaks into
     user-facing pages. -->

- `[user docs root]` - for people who use [the product]. No internal names, no
  file paths, no implementation detail.
- `[maintainer docs root]` - for people who work on it. Architecture, decisions,
  traps.

## Before you call it done

<!-- What verification is expected, AND what is not wanted. The second half is
     the half people skip, and it is why agents write test suites nobody asked
     for. -->

- Run `[test command]` and `[type check]`. Both green.
- Write focused tests for the behaviour you changed.
- Say in one line what you verified and what you did not.

Not wanted:

- Smoke tests that assert a module imports.
- A regression test for every deletion.
- Rewriting passing tests so they read differently.

## Security posture

<!-- Proportional. Over-hardening a local or maintainer-only surface adds
     complexity and buys nothing. Name the real boundary. -->

The real trust boundary is [where untrusted input enters]. Everything inside
[local or maintainer-only surface] already runs as the operator. Do not add
auth, input sanitising or rate limiting there.

## Never without asking first

<!-- Blast radius. Short and blunt. -->

- Production data, or anything that writes to it
- Live credentials, tokens, or the files that hold them
- Anything that costs money
- Anything that reaches a user: a send, a deploy, a publish, a push
````

---

## What did not make it into either template, on purpose

| Left out | Why |
|---|---|
| A project pitch | The agent is not deciding whether to adopt the project. |
| End-user install steps | The README's job. |
| A directory tour | Stale in a week. The agent can read the tree. |
| A style guide the linter enforces | The linter is already correct and never drifts. |
| "Write clean code", "be careful" | Not instructions. They change nothing. |
| A changelog or roadmap | Not needed to change code safely. |

## After you fill it in

Run the audit table at the end of the parent `SKILL.md` over the result. The most
common finding is that half of it can go.
