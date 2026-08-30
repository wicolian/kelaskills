# Testing a skill

Almost nobody does this, which is why so many installed skills quietly never
fire. The whole procedure takes about fifteen minutes.

Four passes, in order. Stop and fix at the first failure, because a broken
description makes every later pass meaningless.

| Pass | Question | Fix lives in |
|---|---|---|
| Trigger | Does it fire when it should? | The description |
| False-fire | Does it stay quiet when it should? | The description |
| Body | Does the agent follow what is inside? | The body |
| Gate | Does the repo accept it? | Frontmatter, scripts |

## Pass 1: trigger testing

**Write down five phrasings a real user might type.** Not five ways you would
describe the skill. Five ways someone with the problem would ask.

Rules that make this pass honest:

- **A fresh session for each.** Anything already in context poisons the result.
  If the skill was discussed a minute ago, it will fire on anything.
- **Type the phrasing exactly.** No hints, no "use the X skill".
- **Include at least two bad phrasings.** Vague, misspelled, or frustrated. That
  is how people actually arrive.
- **Record fired or not, per phrasing.** Four out of five is not a pass. Find the
  word the fifth needed.

## Pass 2: false-fire testing

**Write down three adjacent tasks that should not summon it.** Adjacent is the
word that matters. A skill about pull requests should be tested against other
git work, not against baking.

If it fires on an adjacent task, the description is too broad. It is now taxing
every conversation in that neighbourhood, and it may be crowding out the skill
that was actually right.

Three sources of a false fire, in order of how often they cause it:

1. **A shared noun doing the matching.** "pull request" appears in four of your
   skills. The discriminating verb has to come first.
2. **A category word.** "code", "development", "frontend", "testing". These match
   everything.
3. **A trigger phrase borrowed from a neighbour.** See anti-pattern 4 in
   [description-patterns.md](description-patterns.md).

## Worked example

Skill: `babysit-pr`. Watches an open pull request through review and CI until it
is green.

### Five phrasings that must fire

| # | Phrasing | Why it is in the list |
|---|---|---|
| 1 | "watch this PR and get it green" | The clean, obvious one |
| 2 | "babysit PR 412" | The name people who know the skill use |
| 3 | "CI keeps failing on my PR, keep retrying until it passes" | Describes the problem, never names the skill |
| 4 | "the bot left 6 comments on my pull request, deal with them" | An adjacent duty inside the same job |
| 5 | "is 412 mergeable yet" | Short, lazy, real |

Phrasing 5 is the one that usually fails. Nothing in it says watch, monitor, or
CI. The fix is to add "mergeable" and "is it ready" to the trigger list, not to
tell users to phrase it better.

### Three adjacent tasks that must not fire

| # | Task | Which skill should win |
|---|---|---|
| 1 | "open a PR for this branch" | `file-pr` |
| 2 | "rebase my branch on main" | Nothing. Plain git work. |
| 3 | "review this diff before I push" | A review skill, or nothing |

Task 1 is the dangerous one, because `file-pr` and `babysit-pr` share every noun.
If `babysit-pr` fires there, its description is carrying "pull request" too early
and "watch" too late. Move the verb to the front of both.

### The result table to keep

Paste this into the pull request that adds the skill:

```
FIRE     1 y  2 y  3 y  4 y  5 n -> added "mergeable", "is it ready", now 5 y
QUIET    1 y  2 y  3 y
BODY     ignored the "check the base branch moved" step -> moved above the loop
GATE     ./scripts/check-skills.sh  PASS
```

## Pass 3: body testing

Run the skill on one real task. Watch which instructions the agent actually
follows. Every ignored instruction is one of three things, and the fix differs:

| Why it was ignored | Fix |
|---|---|
| It is default behaviour already | Delete the whole sentence |
| It is buried below where the decision happens | Move it above that point |
| It conflicts with an earlier instruction | Pick one, delete the other |

The test for the first case: remove the sentence, run the same task, see if the
behaviour changes. If nothing changes, it was decoration.

## "The description is wrong" versus "the model is wrong"

This is the judgement call that decides whether you edit or shrug. It is almost
always the description. Use the table before you conclude otherwise.

| Symptom | Diagnosis | Action |
|---|---|---|
| Fails on one phrasing, fires on four | Description. A missing word. | Add the word from the failing phrasing |
| Fails on all five | Description. The whole framing is from your side, not the user's. | Rewrite from the user's problem |
| Fires, but the agent stops halfway | Body. Weak completion criterion. | State what "done" is, checkably |
| Fires, then does something close but wrong | Body. A missing labelled bad-and-good pair. | Add the pair |
| Fires only when you say the skill's name | Description. It has no situational triggers at all. | Add situations, not just keywords |
| Fires on unrelated work | Description. Too broad. | Cut the category words |
| Everything passes, output is still poor | Body. | Prune no-ops, then add the examples |

**The one real "the model is wrong" case:** the same phrasing fires in a fresh
session sometimes and not others, with no other skill competing, and the
description already carries that exact phrasing. That is variance. Sharpen the
first six words of the description and retest. If it persists, note it in the
skill and move on. Do not rewrite a working description around one flaky run.

**Two traps that look like model failure and are not:**

- **Context contamination.** You tested in a session that already mentioned the
  skill. Everything fires. Always start fresh.
- **A neighbour winning.** The skill did not fail to fire, a different one fired
  first. Check what loaded before you blame the description.

## Checklist before you commit

- [ ] Five phrasings written down, all five fire from a fresh session.
- [ ] Three adjacent tasks written down, none of them fire.
- [ ] The description passes the strip test: nothing left teaches the method.
- [ ] No trigger word is shared with a neighbouring skill's first six words.
- [ ] The skill ran once on a real task, start to finish.
- [ ] Every instruction the agent ignored was moved or deleted.
- [ ] Every requirement is stated, with what to do when it is missing.
- [ ] Every script in `scripts/` has been executed, and is read-only or gated.
- [ ] `scripts/lint-descriptions.sh` reports nothing on your skill.
- [ ] `./scripts/check-skills.sh` passes.
- [ ] The results table is in the pull request.
