---
name: right-question
description: Use when a task is under-specified and the agent is about to either guess or interrogate. Triggers on the `-ask` tag, and on "what do you need from me before you start", "ask me first, don't guess", "one question not twenty", "batch your questions", "the fleet has six questions", "clarify the requirements", "should I check with the user on this", or "stop asking me one thing at a time". The `-ask` lens auto-answers every question it can from the repo, the git history and prior runs, then asks the human one batched round containing only the questions that change what happens next.
kind: lens
tag: -ask
phase: before
order: 20
ask_budget: 1
---

# Right question

An under-specified task pushes an agent into one of two failures. It guesses, and
does the wrong work at scale. Or it interrogates, and turns an unattended run into
an interview. This lens does neither. It answers everything it can from evidence,
then takes one batched round of real decisions to the human.

The interview machinery here is adapted from Matt Pocock's published skills,
`grilling` and `to-questionnaire`, at https://github.com/mattpocock/skills (MIT).
The auto-answer pass and the fleet merge are this lens.

| File | Read it when |
|---|---|
| [references/question-formats.md](references/question-formats.md) | Writing the round, the async questionnaire, or an assumption record. Three worked before-and-after examples. |
| [references/auto-answer.md](references/auto-answer.md) | Running the four-source ladder. Exact commands, and how to tell "no evidence" from "I searched wrong". |

## The auto-answer pass

This runs before any question reaches a human. For every candidate question, try
these in order and stop at the first that answers it.

| Order | Source | Kills the question when |
|---|---|---|
| 1 | The repo: code, tests, config, types, README, existing conventions | The codebase already decided, and consistency is the answer |
| 2 | Version control: log, blame, pickaxe, reverts, pull request threads | It was decided before, or tried and reverted |
| 3 | `-why` output if `context-archaeology` ran, and the `-obsidian` vault if one exists | A decision recorded last month is not a question this month |
| 4 | A cheap parallel worker sent to find the fact | The answer is a fact somebody can go and look up |

Only what survives all four is a real question.

State beside each auto-answer **where the answer came from**, so the human can
check your reasoning instead of trusting it. An auto-answer with no source is a
guess wearing a costume.

Never block on source 4. A running fact-finder is an unsettled prerequisite, so
only the questions downstream of it wait. Ask the rest of the frontier now.

## The design tree, worked in rounds

Model the work as a tree: every decision branches into the decisions that hang off
it. The **frontier** is every decision whose prerequisites are already settled,
meaning the questions you can ask now without guessing at answers you have not
heard yet.

Ask the whole frontier in one round. A question whose answer depends on another
question still open in this round belongs to a **later** round, not this one.

Each answered round reshapes the tree. Settled decisions push the frontier outward
and unblock what depended on them. Recompute, ask the next round.

**Target shape: question count high, round count low.** That is the entire
optimisation. Thirteen questions in two rounds is a good run; thirteen questions in
thirteen rounds is an interview.

The format is load-bearing. Reproduce it exactly:

```
Q1 - Cutover: dual-write for one release, or delete the old writer in the same
commit? Dual-write costs a feature flag and a reconciliation job.

-> Dual-write. The reconciliation job pays for itself the first time a row
   disagrees.

---

Q2 - Backfill window: everything, or only rows touched in the last 90 days?

-> Everything. A partial backfill makes every later bug ambiguous.
```

Three details, and why each one is there:

1. **Numbered**, so a tired human can reply "1: yes, 2: option B, 3: skip".
2. **Every question carries your recommended answer on its own line.** This lets a
   human ratify instead of compose. It is the highest-leverage detail in the format.
3. **A horizontal rule between questions**, so consecutive ones do not run together.

## Is it worth an interruption at all

A question is worth an interruption only if the answers lead to **materially
different work**.

The test: write the next concrete action under each answer. If the two lines are
the same, it was never a question. Delete it and proceed.

| Candidate | Branch A action | Branch B action | Verdict |
|---|---|---|---|
| "Should I add tests?" | Write tests | Write tests anyway, the repo requires them | Not a question |
| "Drop the old table, or keep it?" | Irreversible drop | Two-phase, keep a rollback | Real question |

## Merging a fleet's questions

Six workers each with a question is six stalls. This lens is the escalation valve
for that. The mechanism lives in
[agent-fleet](../agent-fleet/SKILL.md#escalate-one-question-not-six); do not repeat
its commands here.

The judgement is:

1. **Workers never ask a human.** A worker that hits a fork writes the question
   into its report and continues on a stated assumption.
2. **The orchestrator collects, auto-answers, and dedupes.** Most worker questions
   die at rung 1 or 2 of the ladder.
3. **Find the underlying decision.** Six surface questions usually collapse into
   one real fork.

To spot the collapse, look for different questions that share a **single upstream
unknown**. "Which colour token?", "should this border change?", "do I touch the
dark theme?" are one question: *are we allowed to change the palette, or only the
contrast ratio?* Ask that one. The other five fall out of the answer.

## Variants

**Breadth-first**, when charting unfamiliar territory. Fan out across the whole
space instead of going deep on one thread. If the sweep surfaces nothing unknown,
say a map is not needed rather than producing one.

**Grill the send, not the subject**, when the human cannot answer either. Not
knowing the topic is why they are asking somebody else, so do not interview them
about it. Interview them about **who it goes to** and **what they need back**, one
exchange each, then aim every question at that gap. Output a questionnaire, format
in [references/question-formats.md](references/question-formats.md).

**Re-pitch**, when the human is lost rather than undecided. Naming the output ("be
brief", "no fluff") makes a model clip words. Naming the **listener's state** asks
for fewer words and the missing context at once, which is what was actually wanted.

## How it stops

The frontier is empty: every branch visited, nothing silently assumed. It stops on
structure, not on a counter, and it stops on the human confirming shared
understanding, not on your own sense of completeness.

**There is no question cap, deliberately.** Some work needs three questions, some
needs fifty. A cap conflates two failures: genuinely under-specified work (working
as intended) and redundant low-value questions (a prompt-quality problem).
Natural-language steering is the control surface, not a number. But **round count
past three or four is a real signal**: the scope is too big. Say so and propose a
split.

## Intervention points

| When | What this lens does |
|---|---|
| Before the host reads its first file | Draft the candidate questions, then run the auto-answer ladder over all of them |
| Before the first decision with more than one defensible answer | Ask the whole frontier in one numbered round, each question with a recommendation |
| When a worker or subagent reports a question | Collect it, auto-answer it, merge it into the pending round; never let it interrupt on its own |
| Before the first irreversible action | Re-run the worth-an-interruption test on that one action. An irreversible fork with no answer is a stop, not an assumption |
| When the budget is spent or the human is unavailable | Write an assumption record and proceed; do not stall and do not silently guess |

## Hard rules

1. **Never ask a human anything you could look up.** Facts are your job. Only
   decisions go to a human.
2. **One round, not one question.** The budget counts interruptions. Ten questions
   in one batch is one interruption; ten questions one at a time is ten.
3. **Every question carries your recommended answer, and every auto-answer carries
   its source.** No exceptions for either.
4. **If both answers lead to the same next action, it was not a question.** Delete
   it.
5. **Budget spent or human away means a written assumption, never a silent guess
   and never a stall.**
6. **A question that provokes no disagreement was not worth asking.** Forty
   questions answered "agreed, agreed, agreed" feel productive because they were
   long, and nothing was decided.

## When to skip

- The work is fully specified. Every fork already has a stated answer.
- The human is unavailable and the assumption is cheap to revert. Write the
  assumption record and go.
- The host skill already runs its own interview. Two interviews is worse than
  none; let the host own it and only contribute the auto-answer pass.
- The task is reversible and small enough that doing it is cheaper than asking
  about it. Do it, and say what you assumed.

Say the skip out loud, in one line. A silent skip looks like a failure.

## Handoff

Leave this behind. `-obsidian` consumes it and the host skill acts on it.

```
ANSWERED   <the decision, as settled>
SOURCE     human | repo:<path> | git:<sha> | why-lens | vault:<note> | worker:<id>
ROUND      <round number it was settled in, or 0 for auto-answered>

ASSUMED    <the assumption, stated as a decision>
BECAUSE    <budget spent | human unavailable | reversible and cheap>
BLAST      <what breaks and what it costs if this is wrong>
REVISIT    ASSUMPTION:<slug>   <- the exact marker left in code or notes
```

Every assumption gets its `ASSUMPTION:<slug>` marker written into the artefact it
affects, so one grep finds it. An assumption nobody can find is a guess with better
paperwork.

Report the round count too. Past three or four, the scope was too big: name the
split you would make.
