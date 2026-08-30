# Routing

Where to send the work when Matt Pocock's skills are installed, and what to do
when they are not.

Source: [github.com/mattpocock/skills](https://github.com/mattpocock/skills), MIT
licensed. Installed, the skills carry a `mattpocock-skills:` prefix.

**This lens is a distillation. The originals are better.** When they are present,
route out and stop paraphrasing. The one-liners in
[decision-gates.md](decision-gates.md) exist for the case where they are not.

---

## Two hard constraints on how you route

Both come from his own repo, and both are silent failures when broken.

### One skill per call

**The Skill tool takes one skill per call.** A step that needs two skills is two
calls.

```
Correct:   Call the Skill tool with "mattpocock-skills:grilling".
           Call the Skill tool with "mattpocock-skills:domain-modeling".

Wrong:     Call the Skill tool with "grilling" and "domain-modeling".
```

The wrong form reads as a single call taking two names, and it does not fire.
When a step genuinely needs both, say so in words: "call the Skill tool twice,
for X and then for Y".

### A user-invoked skill can never be called by another skill

Skills split on one axis: who can reach them. A **model-invoked** skill can be
called by the model or the human. A **user-invoked** skill is reachable **only by
the human typing its name**, and no skill, including this lens, can fire it.

When a flow needs one, **tell the human to type it**. Do not attempt the call and
do not report it as done.

Phrase every handoff as an explicit tool instruction, never as a bare slash
name in prose:

```
Correct:   Call the Skill tool with "mattpocock-skills:grilling".
Wrong:     Run /grilling.
```

The bare form gets read as text and silently does nothing. Naming the tool is
what actually fires it. Router prose that lists skills for a human to choose
from is a different thing and can use plain names as labels.

---

## The routing table

Every skill below is model-invoked, so every row is a Skill tool call.

| Situation in the host run | Route to | What it owns |
|---|---|---|
| A plan, decision or idea needs stress-testing before anything is built | `mattpocock-skills:grilling` | The interview. Rounds, the frontier, one recommended answer per question, facts found by the agent and decisions left to the human. |
| Something is broken, throwing, failing or slow | `mattpocock-skills:diagnosing-bugs` | Six phases: build the loop, reproduce and minimise, hypothesise, instrument, fix with a regression test, clean up. |
| A feature or a fix is about to be written | `mattpocock-skills:tdd` | The red to green loop, what a good test is, seams, mocking, the three anti-patterns. |
| A diff is ready and needs reviewing | `mattpocock-skills:code-review` | The two axes, standards and spec, in parallel workers, reported side by side and never merged. |
| The shape of a module or the placement of a seam is in question | `mattpocock-skills:codebase-design` | The vocabulary. Module, interface, depth, seam, adapter, leverage, locality. Plus deepening and design-it-twice. |
| A term is fuzzy, a word is doing three jobs, or a hard decision needs recording | `mattpocock-skills:domain-modeling` | The glossary discipline and the decision-record format. |
| A design question is easier to settle by building something rough | `mattpocock-skills:prototype` | Throwaway code that answers one question. Logic branch or UI branch. |
| A fact from outside the working directory is blocking a decision | `mattpocock-skills:research` | A background agent, primary sources only, findings written to a cited file. Keep working while it reads. |
| A merge or rebase conflict is already in progress | `mattpocock-skills:resolving-merge-conflicts` | Hunk by hunk, resolved by intent traced to each side's primary source, then finish the operation. Never abort. |
| A skill, an agent-facing instruction file, or any document an agent will read is being written | `mattpocock-skills:writing-for-agents` | The information hierarchy, context pointers, completion criteria, leading words, pruning. |
| A human has to click through a dashboard, provision infrastructure, or set credentials | `mattpocock-skills:wizard` | A bash script that walks the human stage by stage and captures what it collects. |

### The one route with a warning on it

**`codebase-design` is a reference with no stopping rule.** It has no loop, no
artifact and no checkpoint. It gives you the language and stops.

Do not point a session at it and say "go". A skill with no process and no
stopping rule will improvise one, invent a scope nobody asked for, and burn the
window. Call it **at a decision**, take the vocabulary, and return to the host.

Say this out loud when you route to it, in one line, so nobody expands it into a
session.

### Do not route these here

These are user-invoked in his set. Naming them to the Skill tool does nothing.
If the flow needs one, write a line telling the human to type it.

```
/ask-matt   /grill-with-docs   /grill-me   /implement   /to-spec
/to-tickets   /triage   /wayfinder   /improve-codebase-architecture
/handoff   /teach   /setup-matt-pocock-skills
```

---

## When his skills are not installed

Two moves, in this order.

**1. Say so once, at the top.** One line, not a paragraph:

> Running on the distilled bar. `mattpocock-skills` is not installed, so the
> one-line versions in `references/decision-gates.md` are standing in for the
> full processes. Install with `npx skills add mattpocock/skills` for the real
> thing.

**2. Use the standing-in section, and name which one you used.** Every routed
process has a compressed version:

| Routed skill | Standing in for it |
|---|---|
| `grilling` | The posture: batch the whole frontier into one round, carry a recommended answer on every question, dispatch a worker for facts. In [SKILL.md](../SKILL.md), "Intervention points" row one. |
| `diagnosing-bugs` | [decision-gates.md](decision-gates.md) section 3, the red loop protocol. |
| `tdd` | [decision-gates.md](decision-gates.md) section 4, before writing code. |
| `code-review` | [decision-gates.md](decision-gates.md) section 6, the two-axis review. |
| `codebase-design` | [decision-gates.md](decision-gates.md) sections 1 and 2. |
| `domain-modeling` | [decision-gates.md](decision-gates.md) section 5, plus "name things once" in [SKILL.md](../SKILL.md). |
| `writing-for-agents` | [decision-gates.md](decision-gates.md) section 8. |
| `prototype` | No standing-in version. Throwaway code that answers one question, kept as a primary source on a branch off main, with only the validated decision folded into real code. |
| `research` | No standing-in version. Dispatch a background worker, primary sources only, one cited file back. |
| `resolving-merge-conflicts` | The hard rule: resolve by traced intent, finish the operation, never abort. |
| `wizard` | No standing-in version. Say plainly that a human has to do this part. |

Write the substitution on the `ROUTED` line of the handoff block, so a later
reader can tell a full process from a one-liner:

```
ROUTED   not installed, decision-gates.md section 3 used in place of diagnosing-bugs
```

**Never claim a routed skill ran when it did not.** A handoff that says
`code-review` when a paragraph of this file was used instead is the single most
expensive lie this lens could tell, because everything downstream trusts it.
