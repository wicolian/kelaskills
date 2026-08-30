# Question formats

Three formats. The batched round for a human who is present, the questionnaire for
a human who is not, and the assumption record for when nobody is.

Adapted from Matt Pocock's `grilling` and `to-questionnaire` skills,
https://github.com/mattpocock/skills (MIT).

---

## 1. The batched round

One round is one interruption. It contains the whole frontier: every decision whose
prerequisites are already settled, and nothing that depends on another question in
the same round.

### Shape

```
Round 1 of ?   |   4 questions   |   9 auto-answered, listed below

Q1 - <short title>: <body. May be several paragraphs. May offer options,
labelled A/B/C so the reply can be one letter.>

-> <your recommended answer, on its own line, one line where possible>

---

Q2 - <short title>: <body>

-> <your recommended answer>

---

Q3 - <short title>: <body>

-> <your recommended answer>

Auto-answered, so not asked:
- <question>  ->  <answer>   [repo:src/db/schema.ts:41]
- <question>  ->  <answer>   [git:9f21c0a, reverted once in #482]
- <question>  ->  <answer>   [vault:decisions/queue-choice.md]
```

### Why each part is there

| Part | Why |
|---|---|
| Numbering | The reply can be "1: yes, 2: B, 3: skip". No quoting questions back. |
| `->` recommendation on its own line | A tired human ratifies instead of composes. This is the single highest-leverage detail in the whole format. |
| `---` between questions | Consecutive questions run together without it, and the reader loses the boundary. |
| Short title before the colon | Skimmable. The human decides what to read closely. |
| The auto-answered list | Shows the work. The human can challenge a source instead of trusting it. |
| Round counter | Round 4 of an unknown total is the signal that the scope is too big. |

### Rules for the body

- One idea per question. Never compound. "Should we migrate and also drop the old
  table?" is two questions with two different risk profiles.
- Offer options only when the options are real. Three labelled choices where one is
  obviously correct is padding.
- The recommendation may argue **against** the question as worded. When it does,
  say so, because agreeing with the recommendation then means answering "no".
- A question that surfaces an implicit decision the human has not noticed is the
  best kind. Success looks like the human ending up somewhere unexpected.

---

## 2. The async questionnaire

Use when the human cannot answer either, and the answers live with somebody else.
Do not interview the human about the topic. Not knowing the topic is why they are
asking somebody else.

Interview them about the **send**, which they can always answer:

1. **Who is it going to?** Role, expertise, relationship. One exchange. This fixes
   tone and how much context the document must carry.
2. **What do you need back?** The specific decisions or facts they cannot resolve
   alone. One exchange. Done when you have a concrete list.

Then aim every question in the document at the gap between those two.

### Shape

```markdown
# <Questionnaire title>

**Purpose:** why this exists and the decision riding on it.

**From:** <sender>  **To:** <recipient>  **Answers will be used for:** <where they go>

## Context

One paragraph for a recipient who was not in the room. Enough to answer well, not
a page.

## How to answer

Deadline and rough effort. Partial answers and "I don't know" are useful. Flag
anything you are unsure of rather than skipping it.

## <Theme heading>

### <One question, one idea, never compound>

_Why this matters: <one line, only where the question could be misread or invite a
throwaway answer>._

>

### <Next question>

>

## Anything else?

Anything we did not ask that we should know?
```

### Rules

- **Most important first.** Async means you may get one pass. Assume the reader
  stops halfway.
- One idea per question, never compound.
- An answer stub (`>`) directly under every question, so the reply lands in place.
- The "why this matters" line only where it earns its space. On every question it
  becomes noise.
- Group under `##` themes once there are more than a handful.

---

## 3. The assumption record

Written when the ask budget is spent, or the human is unavailable, or the fork is
reversible and cheap. The lens does not stall and does not silently guess.

```
ASSUMED    New endpoints stay on the v1 auth middleware.
BECAUSE    Human unavailable, overnight run, no v2 middleware in the repo yet.
BLAST      Three route files. If wrong, the fix is one import swap per file plus
           re-running the auth integration suite. Roughly 20 minutes.
REVISIT    ASSUMPTION:auth-middleware-v1
```

Rules:

- **BLAST is what breaks and what it costs**, in files and minutes. "Might need
  rework" is not a blast radius.
- **REVISIT is a literal marker**, written into the artefact it affects as a code
  comment, a note line, or a report line. One grep finds every open assumption.
- If the blast radius is "irreversible" or "cannot be measured", it is not an
  assumption. It is a stop.

---

## Worked examples

### A. A migration

**Before, an interrogation.** Eleven turns, each one blocking:

```
> Do you want me to migrate the users table first?
> Should I use a new column or a new table?
> What about the nullable email field?
> Do we need a backfill?
> How far back should the backfill go?
> Should the old writer stay?
> Do you want a feature flag?
> What should the flag be called?
> Should I write a rollback script?
> Do we need a reconciliation job?
> Can I drop the old column when it's done?
```

**After.** The ladder kills six. The rest collapse into three real forks in one
round:

```
Round 1 of ?   |   3 questions   |   6 auto-answered

Q1 - Cutover: dual-write for one release, or delete the old writer in the same
commit? Dual-write costs a flag and a reconciliation job.

-> Dual-write. The reconciliation job pays for itself the first time a row
   disagrees.

---

Q2 - Backfill window: everything, or only rows touched in the last 90 days?

-> Everything. A partial backfill makes every later bug ambiguous.

---

Q3 - Dropping the old column: this release, or a release later? Dropping now is
irreversible without a restore.

-> A release later. Nothing is gained by dropping it today.

Auto-answered, so not asked:
- Migrate which table first?  ->  users, it is the only one with the pattern
  [repo:src/db/migrations/, grep for the legacy shape]
- New column or new table?  ->  new column, the last four migrations did this
  [git:log --oneline -- src/db/migrations | head]
- Nullable email?  ->  stays nullable, made nullable deliberately after an incident
  [git:pickaxe on "email NOT NULL", reverted in #311]
- Flag naming?  ->  repo convention is feature.<area>.<verb>  [repo:src/flags.ts]
- Rollback script?  ->  yes, every migration in this repo has one  [repo convention]
- Reconciliation job?  ->  follows from Q1, downstream, so a later round
```

Eleven interruptions became one.

### B. An accessibility fix

**Before.** Six workers, six questions, six stalls:

```
worker 1: which colour token for the failing button?
worker 2: does the border colour change too?
worker 3: do I touch the dark theme?
worker 4: the disabled state also fails, do I fix it?
worker 5: the brand blue is the problem, can I change it?
worker 6: should I update the Figma tokens as well?
```

**After.** All six share one upstream unknown. Ask that, and the rest fall out:

```
Round 1 of ?   |   1 question

Q1 - Palette or ratio: six contrast failures all trace back to the brand blue.
Two ways to clear them.

A. Change the brand blue itself. One token, every failure clears, and the brand
   colour changes everywhere including marketing.
B. Leave the palette. Fix each failing pair by darkening the foreground locally.
   Six local overrides, the brand is untouched, and the overrides will drift.

-> B for this pass, and raise A separately with the person who owns the brand.
   Changing a brand colour inside an accessibility ticket is a decision hiding
   inside a chore.

Auto-answered, so not asked:
- Dark theme in scope?  ->  yes, the audit covered both  [repo:audit/config.json]
- Disabled state?  ->  out of scope, disabled controls are exempt under the
  standard the repo targets  [repo:docs/a11y.md]
- Figma tokens?  ->  no, tokens are generated from code here  [repo:tokens/build.ts]
```

Six stalls became one decision, and the decision was not the one any worker asked.

### C. An API change

**Before.** A guess made at scale. No questions asked, and the wrong shape shipped
to forty call sites.

**After.** One round, two questions, and one of them surfaces a decision nobody
had noticed:

```
Round 1 of ?   |   2 questions   |   4 auto-answered

Q1 - Breaking or additive: the new filter argument can be a required third
parameter, or an optional options object. Required is cleaner and breaks 40 call
sites. Optional is uglier and breaks none.

-> Optional options object. Forty call sites is forty chances to get a mechanical
   edit wrong, and the ugliness is confined to one signature.

---

Q2 - Versioning: this endpoint is public. Adding a filter changes the default
result set for anybody who does not pass one. That is a silent behaviour change
for existing clients, not just a new feature.

-> Default the filter to the current behaviour, so existing clients see nothing
   change. Opting in gets the new behaviour.

Auto-answered, so not asked:
- Naming convention for the argument?  ->  camelCase options object
  [repo:src/api/*.ts, consistent across 12 endpoints]
- Do we need a changelog entry?  ->  yes, public endpoints always get one
  [repo:CONTRIBUTING.md]
- Is there a deprecation policy?  ->  two minor versions  [repo:docs/api-policy.md]
- Which test suite?  ->  the contract suite  [repo:package.json scripts]
```

Q2 is the point. Nobody asked it. It was an implicit decision hiding inside a
feature request, and it is the one that would have caused an incident.
