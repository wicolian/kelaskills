---
name: whatwillmattdo
description: Use when a run needs a stricter engineering bar than the host skill sets on its own, invoked as a trailing tag, such as "/graph-engineering -whatwillmattdo", "/stacked-prs -whatwillmattdo", "fix this -whatwillmattdo", "hold this to a higher bar", "be opinionated about this design", "what would a strict reviewer say", or "stop me shipping something sloppy".
kind: lens
tag: -whatwillmattdo
phase: decisions
ask_budget: 1
---

# What will Matt do

A stricter bar at every design decision and every gate the host already has. It
adds constraints, evidence and questions. It writes no deliverable and it never
changes what the host skill is for.

**Credit, first.** This is a distillation of Matt Pocock's published skills at
[github.com/mattpocock/skills](https://github.com/mattpocock/skills), MIT
licensed. It compresses someone else's judgment into a lens. It is not a
replacement for his skills, and it is thinner than they are on purpose. Where
they are installed, this lens routes to them and gets out of the way. Where they
are not, it carries the one-line version and says which one-liner is standing in
for which process.

Announce the lens once at the top of the run, then act only at the points below.

## Intervention points

| When | What this lens does |
|---|---|
| Before a question goes to a human | Check the question is a decision, not a fact. Facts are yours. Dispatch a parallel worker for anything the environment can answer, and do not block the rest of the frontier on it. |
| Before any command or output is shown | Redact every secret, write `<REDACTED>` in its place, and rebuild the loop against environment variables so the credential stays in the environment. |
| At any design decision with more than one defensible answer | Run the interface check, the depth check, the deletion test and the seam count. If the shape is genuinely open, design it twice before choosing. See [references/decision-gates.md](references/decision-gates.md). |
| Before the first line of code | Name the seams you will verify at and get them confirmed. Slice vertically. State what is out of scope. |
| Before the first theory about something broken | Demand one command you have already run that goes red on this exact symptom. No red command, no hypothesis. |
| At a phase boundary | Work the boundary tree top down, first yes wins: continue, clear, handoff, delegate, compress. Never mid-phase. |
| Before the host reports done | Run the two axes separately, standards and spec, in a context that did not produce the work. Never merge or re-rank them. |
| Before anything durable is written | Strip every file path and line number. Describe interfaces, types and behavioural contracts instead. |
| When writing anything an agent will read | Place each piece on the information hierarchy, hunt no-ops sentence by sentence, and prompt the positive. |
| At every decision worth recording | Apply the three-way test. Two of three is not a record. One to three sentences is a complete one. |

## Standing posture

These hold for the whole run, not at one moment.

- **Name things once.** Use the project's glossary words verbatim. When you avoid
  a synonym, say which one and why. Language drift is how two people end up
  building two things.
- **Prompt the positive.** A prohibition drags the banned behaviour into context
  and makes it more available, not less. State the target behaviour instead. A
  ban earns its place only as a guardrail you cannot phrase positively, and even
  then it travels with the positive target.
- **No em-dashes, ever.** Not by blind character substitution either. Rewrite the
  sentence with the punctuation it actually wanted.
- **Primary sources over summaries.** Follow every claim back to the thing that
  owns it. A critique of a summary mostly agrees with the summary.
- **Config is death.** Prefer a plain-language instruction to a new flag or
  option. A preference belongs in the project's instructions, not in a switch.
- **Never `git merge --abort`.** Always finish the operation. Resolve each hunk
  by traced intent, preserving both sides where they are compatible.

## Inline or route out

Cheap judgments stay here because they cost one line. Whole processes go out,
because reimplementing them here would make this a skill wearing a lens costume.

| Judgment | Where it lives |
|---|---|
| The deletion test | Inline |
| One adapter is hypothetical, two is real | Inline |
| Vertical slicing, and the wide-refactor exception | Inline |
| The record-a-decision three-way test | Inline |
| Nothing durable carries a path or a line number | Inline |
| Redact before you show | Inline |
| Prompt the positive | Inline |
| Mock only at system boundaries | Inline |
| The full interview, rounds and frontier | Route to `grilling` |
| The full diagnosis loop, phases 1 to 6 | Route to `diagnosing-bugs` |
| The red to green loop and its test rules | Route to `tdd` |
| The two-axis review with parallel sub-agents | Route to `code-review` |
| The deep-module vocabulary and design-it-twice | Route to `codebase-design` |
| The glossary and ADR discipline | Route to `domain-modeling` |
| Writing a document an agent will read | Route to `writing-for-agents` |

Full table, the two hard constraints on how to route, and what to do when his
skills are not installed: [references/routing.md](references/routing.md).

Two constraints that bite immediately. **The Skill tool takes one skill per
call**, so two skills means two calls, never one call naming both. And phrase a
handoff as `Call the Skill tool with "mattpocock-skills:grilling"`, because a
bare `/grilling` in prose is read as text and silently does nothing.

## Hard rules

These override the host and every other lens.

1. **No theory before a red loop.** You must be able to name one command you have
   already run that goes red on this exact symptom. Reading code to build a
   theory before that command exists is the exact failure this prevents. Stop.
2. **Never self-review.** The context that produced the work cannot bless it.
   Fresh context, or a separate worker, or it is not a review.
3. **Facts are yours, decisions are theirs.** Never ask a human anything the
   environment can answer. Never decide anything only the human can.
4. **No seam without two things at it.** One adapter is a hypothetical seam and
   just indirection. Introduce a seam only when something actually varies across
   it.
5. **Nothing durable carries a path or a line number.** Paths and lines go stale
   the week after they are written. Describe the interface, the type, the
   behavioural contract.
6. **Zero em-dash characters.** Rewrite, never substitute.

## When to skip

This lens is expensive: roughly 20 to 40 percent more tokens, and more rework
loops on top. It declines here, in one sentence, and gets out of the way.

- **Throwaway spikes and prototypes meant to be discarded.** A prototype is
  throwaway code that answers one question. Holding it to a merge bar destroys
  the only thing it was fast at. The verdict folds into real code later, and that
  is where the bar applies.
- **Work nobody will review and nobody will read again.** A one-off script, a
  local scratch file, a query run once. There is no second reader to protect.
- **Anything the host skill already gates harder.** If the host demands a
  program-evaluable failing condition and a human approval node, this lens has
  nothing to add and says so rather than restating it in different words.
- **A change small enough that the lens costs more than the work.** Two lines in
  one file with a green test beside it. Say "skipped, below the bar" and move on.
- **When his skills are installed and the host is already routing to them.** The
  distillation is the fallback, not a second opinion layered on the original.

Declining is a stated line in the output, never silence.

## Handoff

Leave this behind for the next lens and for the host. One block per intervention
that actually fired. An intervention that changed nothing does not get a block.

```
POINT      design decision | pre-code | broken | phase boundary | pre-done | durable doc
CALL       <the stricter thing you required, one line>
EVIDENCE   <the command you ran, the seam you named, the source you traced>
ROUTED     <skill you called, or "inline", or "not installed, one-liner used">
RESIDUAL   <what is still unverified, or "none">
SCOPE OUT  <what you deliberately did not touch, so nobody gold-plates it>
```

Two rules on the residual line. Reviews do not converge, so treat findings as
leads and never loop a review until it comes back clean, because it will not.
And if verification could not sit at a real seam, that absence is the finding:
write it on the residual line rather than testing at a seam that gives false
confidence.
