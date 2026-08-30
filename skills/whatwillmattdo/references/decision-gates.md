# Decision gates

The long form behind [SKILL.md](../SKILL.md). Read a section when the pointer
that names it fires, not before.

Everything here is distilled from Matt Pocock's published skills at
[github.com/mattpocock/skills](https://github.com/mattpocock/skills), MIT
licensed. Where those skills are installed, call them instead. This file is the
standing-in version.

---

## 1. The deep-module vocabulary

Use these words exactly. Do not substitute component, service, API or boundary.
Consistent language is the whole point, and drift here is how two people design
two different things while agreeing out loud.

| Term | Meaning | Avoid |
|---|---|---|
| **Module** | Anything with an interface and an implementation. Scale-agnostic on purpose: a function, a class, a package, a tier-spanning slice. | unit, component, service |
| **Interface** | Everything a caller must know to use the module correctly. | API, signature |
| **Implementation** | What is inside the module. | internals |
| **Depth** | Leverage at the interface. Behaviour exercised per unit of interface learned. | complexity |
| **Seam** | A place you can alter behaviour without editing in that place. Where the interface lives. | boundary |
| **Adapter** | A concrete thing satisfying an interface at a seam. Names a role, not a substance. | implementation |
| **Leverage** | What callers get from depth. One implementation pays back across N call sites and M tests. | reuse |
| **Locality** | What maintainers get from depth. Change, bugs and verification concentrate in one place. | cohesion |

### The interface is bigger than the type

The interface is not the type signature. It is every fact a caller must know to
use the module correctly:

- the signature
- the invariants
- the ordering constraints
- the error modes
- the required configuration
- the performance characteristics

A module whose types are tidy and whose ordering constraint lives only in a
maintainer's head has a large interface that is mostly undocumented. That is a
shallow module pretending to be deep.

### Depth is leverage, and the ratio is rejected

**Deep** is a lot of behaviour behind a small interface. **Shallow** is an
interface nearly as complex as the implementation behind it.

Explicitly reject depth measured as a ratio of implementation lines to interface
lines. That metric rewards padding the implementation, which is the opposite of
the thing you want. Measure leverage: how much a caller or a test can exercise
per unit of interface they have to learn.

Depth is a property of the interface, not the implementation. A deep module can
be internally composed of small, swappable parts. They are simply not part of the
interface. A module can have **internal seams**, private to its implementation
and used by its own tests, as well as the **external seam** at its interface. Do
not expose an internal seam through the interface just because a test reaches for
it.

### The deletion test

Imagine deleting the module.

| What happens | Verdict |
|---|---|
| Complexity vanishes | It was a pass-through. Delete it for real. |
| Complexity reappears across N callers | It was earning its keep. Keep it, and consider deepening it further. |

Run this before adding a module too. If you cannot name the callers whose
complexity it absorbs, you are adding indirection and calling it architecture.

### The seam count

**One adapter is a hypothetical seam. Two adapters is a real one.**

Do not introduce a seam unless something actually varies across it. Production
plus test is the usual honest pair. A single-adapter port is indirection wearing
a design pattern's name.

Classify the dependency before you decide how the seam gets tested:

| Category | What it is | Seam treatment |
|---|---|---|
| In-process | Pure computation, in-memory state, no I/O | No adapter. Merge and test through the new interface. |
| Local-substitutable | Has a local stand-in (an embedded database, an in-memory filesystem) | Internal seam. Run the stand-in in the suite. No port at the external interface. |
| Remote but owned | Your own services across a network | Define a port at the seam. Transport adapter for production, in-memory adapter for tests. |
| True external | Third-party services you do not control | Injected port. Mock adapter in tests. |

### Replace, do not layer

When you deepen a cluster, the old unit tests on the shallow pieces become waste
once tests exist at the deepened interface. Delete them. Two layers of tests over
one behaviour means every change costs twice and the shallow layer is the one
that will break for no reason.

---

## 2. Design it twice

Reach for this only when the shape is genuinely open. Your first idea is unlikely
to be the best one, and the cost of finding out later is a rewrite.

**Do not run this on a decision with an obvious default.** Three parallel workers
on a settled question is theatre that produces a menu.

### The process

1. **Frame the problem space first.** Write the constraints any interface must
   satisfy, the dependencies and their category, and a rough sketch that makes
   the constraints concrete. The sketch is grounding, not a proposal. Show this
   to the human, then start the workers immediately. They read while the workers
   run.

2. **Spawn three or more workers in parallel, each with a different constraint.**
   Each must produce a radically different interface.

   | Worker | Constraint |
   |---|---|
   | 1 | Smallest interface. One to three entry points. Maximise leverage per entry point. |
   | 2 | Most flexible. Support many use cases and extension. |
   | 3 | Easiest for the commonest caller. Make the default case trivial. |
   | 4, when it applies | Ports and adapters around the cross-seam dependencies. |

   Give each a self-contained technical brief: what sits behind the seam, the
   coupling, the dependency category, and both the vocabulary above and the
   project's own glossary, so all of them name things the same way.

   Each returns: the interface including invariants, ordering and error modes; a
   usage example; what the implementation hides; the dependency and adapter
   strategy; and where leverage is high and where it is thin.

3. **Compare on three axes and then commit.** Depth, locality, seam placement.
   Present the designs one at a time so each can be absorbed, then contrast them.

**Then be opinionated.** Say which one is strongest and why. Propose a hybrid
where elements combine well. The human wants a strong read, not a menu. A
comparison that ends in "any of these could work" wasted three workers.

---

## 3. The red loop protocol

The loop is the skill. Everything after it is mechanical. With a tight pass/fail
signal that goes red on this bug, you will find the cause: bisection, hypothesis
testing and instrumentation all just consume the loop. Without one, no amount of
staring at code saves you.

Spend disproportionate effort here. Be aggressive, be creative, refuse to give
up.

### The gate

**No theory until you can name one command you have already run that goes red on
this exact symptom.**

If you catch yourself reading code to build a theory before that command exists,
stop. That is the exact failure this prevents.

The command must be:

- **Red-capable.** It drives the actual bug code path and asserts the user's
  exact symptom. "Runs without erroring" is not red-capable.
- **Deterministic.** Same verdict every run.
- **Fast.** Seconds, not minutes.
- **Runnable unattended.** A human in the loop only through a structured script
  that feeds its output back.

Show the invocation and its output, redacted.

### Ways to build one, in rough order

1. A failing test at whatever seam reaches the bug.
2. An HTTP script against a running dev server.
3. A CLI invocation on a fixture, diffed against a known-good snapshot.
4. A headless browser script asserting on DOM, console or network.
5. A replay of a captured trace: save a real payload to disk, replay it through
   the code path in isolation.
6. A throwaway harness: a minimal subset of the system, one function call.
7. A property or fuzz loop, when the symptom is "sometimes wrong output".
8. A bisection harness, when the bug appeared between two known states.
9. A differential loop: same input through two versions or two configs, diffed.

### Treat the loop as a product

Once you have a loop, tighten it. Three questions:

- Can I make it faster? Cache setup, skip unrelated init, narrow the scope.
- Can I make the signal sharper? Assert the specific symptom, not "did not
  crash".
- Can I make it more deterministic? Pin time, seed randomness, isolate the
  filesystem, freeze the network.

A 30-second flaky loop is barely better than no loop. A 2-second deterministic
one is a superpower.

**For a flaky bug the target is a higher reproduction rate, not a clean repro.**
Loop the trigger a hundred times, parallelise, add stress, narrow the timing
window, inject sleeps. A 50 percent flake is debuggable. A 1 percent flake is
not. Keep raising the rate until it is.

### Minimise

Once it is red, shrink to the smallest scenario that still goes red. Cut inputs,
callers, config, data and steps **one at a time**, re-running after each cut.

Done when **every remaining element is load-bearing**: removing any one of them
turns the loop green. A minimal repro shrinks the hypothesis space and becomes
the regression test later.

### Hypothesise, then probe

**Generate three to five ranked falsifiable hypotheses before testing any of
them.** Generating one at a time anchors you on the first plausible idea.

Each must state its prediction: "if X is the cause, then changing Y makes the bug
disappear."  If you cannot state the prediction, it is a vibe. Sharpen it or
discard it.

**Show the ranked list to the human before testing.** They re-rank it instantly
more often than you would expect, because they know what shipped yesterday. This
is the one ask this lens budgets for. Do not block on it: proceed with your own
ranking if nobody is there.

Then probe. Each probe maps to one prediction. **Change one variable per probe.**
A debugger breakpoint beats ten logs. Targeted logs at the boundaries that
distinguish hypotheses beat logging everything and grepping.

**Tag every temporary probe with a unique marker**, for example `[DEBUG-a4f2]`,
so cleanup is one search. Untagged probes survive into main.

For a performance regression, logs are usually the wrong tool. Establish a
baseline measurement first, then bisect. Measure first, fix second.

### When you cannot build a loop

Say so, specifically, and stop. List what you tried. Name exactly what you need:
access to an environment that reproduces it, a redacted captured artifact, or
permission to add temporary instrumentation. **Do not proceed to hypothesise.**

---

## 4. Before writing code

### Confirm the seams

Write down the seams you will verify at and confirm them before any test exists.
**No test at an unconfirmed seam.** You cannot test everything, so agreeing the
seams up front is how effort lands on critical paths and complex logic instead of
on every edge case someone thought of.

The interface is the test surface. Callers and tests cross the same seam. If you
want to test past the interface, the module is the wrong shape.

### Mock only at system boundaries

Mock: external APIs, time, randomness. Sometimes the filesystem. Sometimes the
database, though a real test database is usually better.

Never mock your own modules or internal collaborators. A test that mocks a
collaborator asserts that today's call graph exists, which is exactly the thing a
refactor is allowed to change.

### The three test anti-patterns

| Anti-pattern | The tell | The fix |
|---|---|---|
| **Implementation-coupled** | The test breaks on a refactor with no behaviour change. Mocks internal collaborators, tests private methods, or verifies through a side channel such as querying the database instead of using the interface. | Assert observable outcomes through the interface. |
| **Tautological** | The expected value is recomputed the way the code computes it, so it passes by construction and can never disagree with the code. | Expected values come from an independent source of truth: a known-good literal, a worked example, the spec. |
| **Horizontal slicing** | All the tests, then all the implementation. Verifies imagined behaviour, commits to test structure before the implementation is understood, and goes insensitive to real change. | One test, one implementation, repeat. |

### Slice vertically

Each slice is a narrow but complete path through every layer, demoable on its
own, sized to fit one fresh context window. Each slice responds to what the last
one taught you.

**The one exception is a wide mechanical change** whose blast radius fans across
everything: a column rename, a retyped shared symbol. One edit breaks thousands
of call sites and no vertical slice can land green. Do not force it into a slice.
Sequence it instead:

1. **Expand.** Add the new form beside the old. Nothing breaks.
2. **Migrate.** Move call sites in batches sized by blast radius, per package or
   per directory. Each batch is its own unit, blocked by the expand, green batch
   to batch because the old form still exists.
3. **Contract.** Delete the old form once no caller remains, blocked by every
   migrate batch.

Where even the batches cannot stay green alone, keep the sequence but let them
share an integration branch that all block a final integrate-and-verify step.
Green is promised only there, and you say so.

### Refactoring is not part of the loop

It belongs to review. The implementer is carrying the most context pressure in
the run and is the worst-placed person to judge the shape of what they just
built. The reviewer sees only a diff, which is exactly the vantage the judgement
needs.

---

## 5. Recording a decision

Record it only if **all three** hold:

1. **Hard to reverse.** The cost of changing your mind later is meaningful.
2. **Surprising without context.** A future reader will look at it and wonder why
   on earth it was done this way.
3. **The result of a real trade-off.** There was a genuine alternative.

If it is easy to reverse, you will just reverse it. If it is not surprising,
nobody will wonder. If there was no alternative, there is nothing to record
beyond "we did the obvious thing".

**One to three sentences is a complete record.** If any of the three tests fails,
do not write it. A decision log padded with obvious decisions is a decision log
nobody reads, which is the same as not having one.

---

## 6. The two-axis review

Run two reviews. Keep them apart.

| Axis | The question |
|---|---|
| **Standards** | Does the code follow this project's documented standards? |
| **Spec** | Does the code do what was actually asked? |

Run them as separate workers so neither pollutes the other's context. Report them
under separate headings. **Never merge or re-rank the findings**, and never pick a
single winner across the two axes. Re-ranking is the exact thing the separation
exists to prevent.

A change can pass one and fail the other, and each failure is invisible from the
other axis:

- Follows every standard, implements the wrong thing. Standards pass, spec fail.
- Does exactly what was asked, breaks every convention. Spec pass, standards
  fail.

A blended verdict lets the passing axis hide the failing one, and a blended
verdict is what a tired reader will produce by default.

### The rules around the review

- **Never self-review.** The context that produced the work cannot bless it.
  Fresh context, or a separate worker.
- **Reviews do not converge.** Treat every finding as a lead, not a defect. Do
  not loop a review until it comes back clean, because it will not. Decide which
  leads to act on and say which you are declining.
- **Always state what is out of scope**, explicitly, so nobody gold-plates. This
  costs one line and saves an afternoon.
- **Verification must sit at a real seam.** A correct seam exercises the real
  pattern as it occurs at the call site. A single-caller test for a bug that
  needs multiple callers gives false confidence. **If no correct seam exists,
  that absence is the finding.** Say it. The architecture is preventing the
  behaviour from being locked down, and that is worth more than a test that
  cannot fail for the right reason.
- **Nothing durable references a file path or a line number.** They go stale the
  week after they are written. Describe interfaces, types and behavioural
  contracts. Behavioural, not procedural.

---

## 7. The phase-boundary tree

A **phase** is a chunk of work inside a session: the interview, the
implementation, the QA. The definition is fuzzy on purpose. A phase ends when you
think "right, that is done".

The **phase boundary** is the gap between two phases, and it is the only place
this decision belongs. Mid-phase there is no decision to make: continue, or split
what is left into workers. Compressing mid-phase makes the agent lose the thread.

Work the tree **top down. The first yes wins.**

| # | Question | If yes |
|---|---|---|
| 1 | Can you continue in this session? | **Continue.** |
| 2 | Is everything in this context irrelevant to what comes next? | **Clear.** |
| 3 | Does the work have to travel? | **Handoff.** |
| 4 | Can the task run with nobody at the keyboard? | **Delegate.** |
| 5 | Otherwise | **Compress.** |

**1. Continue** is yes when the next phase needs this one as a primary source, or
when enough of the window is left for the next phase to fit. An interview
followed by an implementation is the standard yes: the implementation wants the
reasoning verbatim, not a summary of it. Continue costs nothing and loses
nothing, so rule it out before anything else.

**2. Clear** is the cheapest move on the board. It takes no time and hands back
the whole window, and the old session stays resumable. The cost of getting it
wrong is one-way: clear a relevant context and you lose the reasoning behind what
you built, and reading the diff back does not return it.

**3. Handoff** is narrow. You need it only when something is travelling: a new
harness, a new directory or repo, another person, or a side task found mid-phase
that you do not want to derail the current work. If nothing travels, you do not
need it. What it buys is portability.

**4. Delegate** applies when the task is scoped tightly enough to run with no
steering. An automated review is the standard case: it reads the diff and
reports, and nobody is needed while it does. The current session stays untouched.

**5. Compress** is the **default, not the first reach.** It sits at the bottom
because the four above it are all cheaper or more precise. Pass it an instruction
so the summary keeps what the next phase needs. The failure mode when people
start here is a fresh session that is confidently wrong about a decision the
summary flattened.

Every move except continue turns a primary source into a secondary one: the
session as it happened, replaced by a summary of it. That is why question 1 comes
first. You pay the lossiness only when staying costs more than it saves.

These are judgement calls. The same boundary can go two ways on two days. The
value is in asking them in order, at the boundary rather than in the middle of
the work.

---

## 8. Writing anything an agent will read

### Place it on the information hierarchy

Three rungs, ranked by how immediately the agent needs the material:

1. **In-file step.** What the agent does, in order. The primary tier.
2. **In-file reference.** Consulted on demand. Often a legitimately flat set of
   peers, which is a fine arrangement and not a smell.
3. **Disclosed reference.** Pushed into a separate file behind a pointer, loaded
   only when the pointer fires.

**Branching is the disclosure test.** Inline what every branch needs. Push behind
a pointer what only some branches reach.

Push too little down and the top bloats. Push too much and you hide material the
agent actually needs. That tension is the whole decision.

The pointer's wording, not its target, decides whether the material gets reached.
A must-have target behind a weakly worded pointer is a variance bug. Sharpen the
wording first; inline the material only if sharpening fails.

### Prune

- **Hunt no-ops sentence by sentence.** An instruction the model already obeys by
  default pays load to say nothing. The test is model-relative, not
  reader-relative: two people disagreeing about a no-op are disagreeing about the
  default, and they settle it by running the document, not by arguing. **When a
  sentence fails, delete the whole sentence** rather than trimming words from it.
- **Beware sediment.** Stale layers settle because adding feels safe and removing
  feels risky, until you have to core down through them to find what is still
  live. Shorter documents are easier to keep relevant.
- **Keep each meaning in one place.** Duplication costs maintenance and tokens,
  and it inflates a meaning's apparent rank past its real one.
- **The environment is a source of truth.** A document that restates the task
  runner's scripts or a config file is a cache of a lookup, and it earns its load
  only when the lookup is expensive. Cache the unwritten convention, the reason
  behind a choice, the gotcha no config confesses. Leave one-command lookups to
  the environment, where they cannot go stale.

### Choose words that already exist

Prefer a compact pretrained word to a coinage. A made-up word recruits no priors,
so you pay in definition tokens what an existing word gives free. Repeat the word
as a token, never as a restated sentence, and it accumulates a distributed
definition that anchors a whole region of behaviour cheaply.

Look for passages begging to collapse into one token:

- "fast, deterministic, low-overhead" becomes **tight**.
- "a loop you believe in" becomes **red**, which turns a fuzzy gate into a binary
  observable state.

### Prompt the positive

Steering by prohibition drags the forbidden behaviour into context and makes it
more available. Think of an elephant, and the elephant is all there is. The
negation is a weak modifier that the strongly activated concept overruns, so the
ban half-reads as an instruction to do the thing.

State the target behaviour so the banned one is never spoken. A prohibition earns
its place only as a hard guardrail you cannot phrase positively, and even then it
travels beside the positive target.
