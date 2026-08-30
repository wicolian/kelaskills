# Description patterns

Every description in this file is a **trigger**. It answers "when should this be
pulled in?" and nothing else.

Read [the SKILL.md](../SKILL.md) first for why. Short version: descriptions are
loaded on every turn whether the skill fires or not, and a description that
teaches the method stops the body from ever loading.

## Before and after, by skill type

### A procedure

Something with steps, run end to end.

```
Before
  Takes a large branch and splits it into a stack of dependent pull requests,
  ordering them so each one builds on the last, keeping the stack rebased as
  review lands, and merging bottom-up once every layer is green.

After
  Use when a branch is too big or too risky to land as one pull request. Triggers
  on "stacked PRs", "dependent PRs", "split this branch", "carve up this
  migration", "keep the stack rebased", "merge the stack".
```

**Changed:** the whole method left the description and stayed in the body. What
remains is the situation plus the words a user types. The "after" is longer in
places and still cheaper, because it stopped competing with the body.

### A reference

Facts consulted on demand. There are no steps to leak, so these fail the other
way: too vague to fire.

```
Before
  Design system reference.

After
  Use when picking a colour, a spacing value, a type size, a radius, or a shadow
  for this product's UI, or when checking whether a hard-coded value should be a
  token.
```

**Changed:** "design system reference" describes the artefact. The rewrite
describes the moments. A reference skill needs *more* trigger surface than a
procedure, not less, because nothing about the task announces that a lookup is
needed.

### A setup routine

Run once, or once per machine.

```
Before
  Installs the toolchain, configures the local database, seeds it, sets the
  environment variables and verifies the dev server boots.

After
  Use when setting up this project on a new machine, when onboarding someone, or
  when a fresh clone will not boot. Triggers on "set up the project", "get this
  running locally", "new laptop", "nothing works after cloning".
```

**Changed:** the step list went to the body. "Nothing works after cloning" was
added, because that is the phrasing people actually arrive with, and it never
appears in a description written from the author's side.

### A review pass

Applied to work someone already did.

```
Before
  Reviews a diff for correctness bugs, missing error handling, untested branches,
  security issues, and opportunities to reuse existing helpers.

After
  Use when asked to review a diff, a pull request, or a branch before it lands.
  Triggers on "review this", "check my changes", "is this ready to merge", "what
  did I miss".
```

**Changed:** the checklist is the body's job. Keeping it in the description was
the classic half-fire: the model reads five review dimensions, reviews along
those five, and never opens the file that had twenty.

### A formatting convention

The smallest kind, and the most often over-written.

```
Before
  Commit messages use the imperative mood, a subject under 60 characters, no
  trailing period, an optional body separated by a blank line, and a trailing
  issue reference.

After
  Use when writing a commit message, amending one, or writing a pull request
  title.
```

**Changed:** the convention itself is four lines in the body. In the description
it was a tax on every conversation in the repository, and it half-fired every
time, because the rules were right there.

## The four anti-patterns

### 1. It teaches the whole method

The one above, in every category. Symptom: you can follow the description without
opening the skill.

**Test:** read only the description and try to do the task. If you get a passable
result, the body is dead weight that will rarely load.

### 2. It is so vague it fires on everything

```
Bad   Use when working with code.
Bad   Best practices for development.
Bad   Helps with frontend tasks.
```

Symptom: it appears in runs that have nothing to do with it, and it crowds out
skills that were right for the task.

**Fix:** name the artefact and the moment. Not "frontend tasks" but "use when
building or changing a React component in `src/ui`".

### 3. It describes the implementation, not the situation

```
Bad   Wraps the GitHub CLI and the REST API to poll check runs with backoff.
Good  Use when waiting for CI on a pull request, or when checks look stuck.
```

Symptom: the description makes sense to whoever built the skill and matches
nothing a user would type. The user has a problem, not an implementation.

**Fix:** write from the user's side of the conversation. What is on their screen
when they need this?

### 4. It duplicates another skill's trigger

```
skill-a   Use when opening a pull request or reviewing pull request state.
skill-b   Use when reviewing a pull request or getting one to green.
```

Symptom: neither fires reliably. Sometimes both fire, and their instructions
fight. Sometimes the wrong one wins and the right one never loads.

**Fix:** find the word that separates them and put it first in each. Here:
`skill-a` owns "open, file, create, draft". `skill-b` owns "watch, monitor,
babysit, green". Delete every overlapping word from both. If nothing separates
them, they are one skill.

The linter catches this case. See below.

## The shape that works

Most good descriptions are one or two sentences in this shape:

```
Use when <situation>, <situation>, or <situation>. Triggers on "<phrase>",
"<phrase>", "<phrase>".
```

- **Situations** are what is true in the world when the skill should fire.
- **Phrases** are what the user types, in their words, including the frustrated
  and imprecise ones.

Two habits worth keeping:

- **Front-load the discriminating word.** The first few words do most of the
  matching. Put what makes this skill different there, not the shared noun.
- **Include the failure phrasing.** "It will not boot", "this is broken", "why is
  this so slow". People reach for a skill at the bad moment, not the tidy one.

One habit worth dropping: listing synonyms that name the same case. "Monitor,
watch, observe, track, follow, supervise" is one branch written six times. Keep
the two people really say.

## Running the linter

```bash
skills/skill-authoring/scripts/lint-descriptions.sh skills
MAXLEN=700 OVERLAP=0.5 skills/skill-authoring/scripts/lint-descriptions.sh skills
```

Read-only. Exit 0 clean, 1 with findings, 2 if the directory cannot be read.

| Tag | Means |
|---|---|
| `LONG` | Over `MAXLEN` characters. It is a summary of the body. |
| `VAGUE` | Under 45 characters. Too thin to match anything specific. |
| `NO-TRIGGER` | No "use when" or "triggers on" phrasing anywhere. |
| `STEPS` | Reads as instructions. Quoted trigger phrases are exempt. |
| `OVERLAP` | Shares that fraction of content words with another skill. |

Real output on a fixture with one deliberately good skill in it:

```
VAGUE       delta        25 chars. Too thin to match anything specific.
NO-TRIGGER  delta        no "use when" or "triggers on" phrasing.
NO-TRIGGER  gamma        no "use when" or "triggers on" phrasing.
STEPS       gamma        reads as instructions (step number). Move it to the body.
OVERLAP     alpha <-> beta   0.71 shared content words. One of them will not fire.

   5 skills read, 5 findings
```

`epsilon`, the one written as triggers, produced no finding.

The thresholds are opinions, not law. `LONG` in particular is a prompt to read
the description again, not proof it is wrong. What it cannot judge is whether a
trigger phrase is one a user would really type. Only pass 1 in
[testing-a-skill.md](testing-a-skill.md) answers that.
