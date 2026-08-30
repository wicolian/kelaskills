---
name: graph-engineering
description: Use when a job has many similar subtasks, when a plan is about to be written as "first X, then Y, then Z" across more than about four steps, when work spans 10 or more files or sources, when a previous run went out of context or thinned out toward the end, or when a plan ends in an irreversible action that needs a gate. Also use when asked to set up agent orchestration, parallel subagents, a review fleet, or a multi-agent workflow, and when an agent loop is fast but never gets smarter.
argument-hint: "[-why] [-ask] [-whatwillmattdo] [-obsidian]"
---

# Graph engineering

One sentence holds the whole discipline:

**A loop makes one unit of work correct without you. A graph decides which units
exist at all.**

The loop lives inside a node. The graph lives between nodes. You do not choose
between them. A graph with no loop inside its nodes produces unverified work in
parallel, which is worse than doing it serially because there is more of it. A
loop with no graph around it is one very good step in a queue nobody designed.

This skill is the second thing. It turns a request into a dependency graph, then
runs that graph in phases, with a check that can fail at every node and one human
approval at the end.

Five reference files sit beside this one. Read them when the pointer says to, not
before:

| File | Read it when |
|---|---|
| [references/verifiers.md](references/verifiers.md) | Writing the check. The missing-compiler framing, the verifier ladder, and why an agent reviewing an agent is theatre. |
| [references/node-catalogue.md](references/node-catalogue.md) | Writing a node. Dispatch-prompt templates, output contracts, splitter dimensions. |
| [references/claude-code-mechanics.md](references/claude-code-mechanics.md) | Wiring it in Claude Code. Agent tool, `.claude/agents/`, the Workflow tool, hooks, headless CLI, worktrees. |
| [references/other-runtimes.md](references/other-runtimes.md) | The runtime is not Claude Code, or the user asks to set one up. Codex, Cursor, Pi, Hermes, LangGraph, Google ADK, plus the setup interview to run first. |
| [references/patterns.md](references/patterns.md) | Picking a topology. Six worked graphs, their costs, and the failure each one is built to stop. |
| [references/plan-schema.md](references/plan-schema.md) | The plan goes to a scheduler or another agent, not a human. |

---

## Rule zero: build the gate first

Before a single node, write the check.

A loop is four parts: produce, check, correct, repeat until green. **The check is
the whole thing.** Without something that can fail the work while nobody is
watching, you do not have a loop. You have a scheduler.

Almost nobody writes the check first. They build the work, bolt a review onto the
end, and the review is another model asked to look at the output. Two optimists
agreeing.

Write the condition so a program could evaluate it:

| | Condition |
|---|---|
| **GREEN** | The test suite exits 0 |
| **GREEN** | `tsc --noEmit` exits 0 and the diff touches only the files in the plan |
| **GREEN** | Every claim in the report carries a file path and a line number |
| **GREEN** | The exported symbol count before and after the refactor is identical |
| **NOT A CHECK** | The output looks good |
| **NOT A CHECK** | The model says it is confident |
| **NOT A CHECK** | No errors were raised |

That last row catches careful people. **Absence of an error is not evidence of
correctness.** Build a graph on it and you get a system that repeats a mistake in
parallel until the budget runs out, with a clean log the whole way.

Two traps specific to shells:

- `$?` after a pipe is the exit code of the last command in the pipe. `tsc | tail`
  is always 0. A failing type-check looks green. Use `set -o pipefail`, or capture
  the status before you pipe.
- A green unit test is not evidence that a UI renders. If the claim is visual,
  the check has to look at pixels or say plainly that the evidence is tests only.

If you cannot write a failing condition for a node, that node has no gate, and
its output has to be treated as a draft that a human reads.

---

## Is this even a graph job?

Most work is not. Reaching for a graph before the work forces you is how a
two-hour task becomes a two-day framework project.

| Signal | A loop is enough | Reach for a graph |
|---|---|---|
| Shape | One job, one finish line | Splits into specialties that hand off |
| Parallelism | Steps are sequential and each feeds the next | Fan out many, then join |
| Tools or model per step | The same throughout | A different model or toolset per step |
| Control flow | One agent can roam safely | You need explicit, auditable routing |
| Failure isolation | A bad step just retries | One bad node must not poison the rest |
| Who verifies | The agent checks its own output | A separate reader checks another node's work |
| Context | It all fits | Item 47 would be degraded by 46 items of state |

**Rough threshold: fewer than about six subtasks with no real fan-out, skip the
formal plan.** Do the dependency audit in your head and get on with it.

The tell that a graph earns its keep: every node is doing work a single loop
could not, and you can still explain the whole thing in one breath. If you can
collapse five nodes back into one agent's loop and lose nothing, collapse them.

---

## The five layers

Graph is the outermost layer, which also makes it the one to reach for last.

| # | Layer | What you engineer | The question |
|---|---|---|---|
| 1 | Prompt | The single request | Am I asking well? |
| 2 | Context | What the model sees | Does it have the right information? |
| 3 | Harness | Tools, memory, scaffolding | Can it act on the world and remember? |
| 4 | Loop | The cycle one agent repeats | When does it check its work and stop? |
| 5 | **Graph** | Coordination between nodes | Who does what, in what order, sharing what state? |

The stack is cumulative, not a ladder you climb away from. A graph is full of
nodes. A good node is a well-designed loop. A good loop needs a real harness.
Skip a lower layer and the graph on top fails in a more elaborate way. Weak
agents wired into an org chart give you a weak org.

---

## Step 1: the dependency audit

This is the part that matters most. Everything else follows from it.

For every pair of steps you were about to sequence, ask one question:

> **Does step B literally read the output of step A?**

If B only needs the *same inputs* A had, they are independent. If B needs A's
*result*, there is a real edge.

The concrete version: **name the variable that crosses.** If you cannot name it,
there is no edge, and the wait is pure waste.

People systematically over-connect, because "and then" is how we narrate work,
not a dependency. "Analyse the auth module and then analyse the payments module"
has no edge. "Analyse the auth module and then write a report on it" has one.

Work through the list explicitly rather than eyeballing it:

```
Step: Summarise each of 40 support tickets
  Reads prior output? No. Each ticket is independent input.
  -> parallel

Step: Cluster the summaries into themes
  Reads prior output? Yes. Needs all 40 summaries. Variable: summaries[]
  -> depends on the summarise group

Step: Draft recommendations
  Reads prior output? Yes. Needs the clusters. Variable: themes[]
  -> depends on clustering
```

Run this on every arrow in a pipeline you already have. Most chains carry two or
three arrows that were never edges. Finding them is usually the single largest
speedup available, and it costs nothing.

### Hidden edges

Data flow is not the only thing that creates an edge. These are the ones that
cause real failures:

- **Shared writes.** Two nodes editing the same file must be ordered, even though
  neither reads the other. This is the most common way a parallel run corrupts
  itself. Split by non-overlapping file boundaries or serialise the writers.
- **Rate limits and quotas.** Twenty concurrent calls to an API that allows five
  will fail. The tasks are logically independent and the constraint is still real.
  Cap the batch instead of removing the parallelism.
- **Schema or interface changes.** Anything that renames a symbol, changes a
  signature, or alters a data format must complete before work that consumes it.
- **Shared runtime.** One dev server, one database, one browser profile, one
  port. Four agents that each want `:3000` are not independent.
- **Machine load.** Self-verifying workers that each spawn a test runner will
  fight for CPU. Gates run in the orchestrator, once, not in every worker.
- **Cost or destructiveness.** Anything irreversible sits behind a verification
  node *and* a human approval gate. That edge exists regardless of data flow.

**If you find no hidden edges, say so explicitly.** Silence here almost always
means the check was not done.

---

## Step 2: split by blast radius, not by folder

The splitter sits at the front and decides more than any other node, because
splitting on the wrong dimension wastes everything downstream.

Cut a repository by folder and four workers audit the same three shared files.
Cut by blast radius and each worker sees something the others cannot.

| Dimension | Use it when | Fails when |
|---|---|---|
| Blast radius | Mixed reversibility. Migrations next to copy changes. | Everything is equally safe. |
| Ownership / import graph | Refactors, ports, dependency work. | Modules are tangled with no seams. |
| Failure class | Audits, reviews. One lens per worker. | The lenses overlap heavily. |
| Entity | Per customer, per endpoint, per document. | Entities share mutable state. |
| Time slice | Log analysis, incident timelines. | Order does not matter. |

Whatever you cut on, the slices must not overlap in writes. That is not a
preference. Two agents editing one file is data loss.

More in [references/node-catalogue.md](references/node-catalogue.md).

---

## Step 3: four kinds of node, and one of them is not a model

Splitter, worker, code node, gate. That is the whole vocabulary.

| Node | Job | Runs as |
|---|---|---|
| **Splitter** | Cut the work into units and write the brief | Orchestrator, inline. Never delegated. |
| **Worker** | One unit, one lens, its own context | Subagent, parallel |
| **Code node** | Merge, rank, dedupe, diff, count | A script. Not a model. |
| **Gate** | Pass, fail, or return with a reason | Deterministic check first, model second |

**The code node is the one people forget exists.** Merging results, ranking them,
deduplicating, comparing every export before and after a refactor, counting
whether 40 of 40 came back: none of that is reasoning. Each has exactly one
correct answer, each is a few lines of code, and putting it through a model adds
cost, latency and variance to a step that had none.

The test: **if you can describe the transformation without the words judge,
decide, assess or summarise, it is code.**

A graph where every edge is an agent pays rent on its own wiring.

### Nodes that stay in the orchestrator, always

- The dependency audit and the rubric. Everything downstream depends on these.
- The final synthesis and prioritisation. That judgement is yours to own.
- **Any irreversible action.** Never delegate a send, a deploy, a delete, a
  migration or a push to a subagent. The subagent has less context than you and
  the action cannot be undone.

---

## Step 4: give every worker its own context

Give four auditors a shared window and they converge. The first writes a finding,
the rest read it, and all four reports centre on the same thing. You paid four
times for one opinion with three echoes.

Fresh context per worker is not a nice-to-have. It is the reason fan-out beats a
long loop: item 47 is not degraded by 46 items of accumulated state.

Rules for a fan-out phase:

- **Self-contained prompts.** Paste in the shared context the worker needs, its
  slice, and the exact output shape. A worker that has to ask a question is a
  worker that has blocked.
- **The same output shape for every worker in the group.** Ragged outputs push
  reconciliation work into the fan-in step, which is where quality is already
  thinnest. Use a schema.
- **Batch small items.** One subagent per item beats nothing when items are big.
  When items are small, batches of items per subagent win, because spawn cost is
  real.
- **Cap the width at whatever hidden edge binds.** Rate limit, machine load,
  spawn cost, or a configured concurrency ceiling. Name the binding constraint in
  the plan.
- **Report failures as data.** If item 12 errors, record it and finish the batch.
  Halting a 40-item phase because of one error throws away 39 results. Halt only
  when the failure invalidates the rest.

### Model tiering

Match the tier to the node, not to the plan.

| Tier | Use for | Why |
|---|---|---|
| Fast / cheap | Classification, extraction, mechanical checks, "does every expected item appear" | Misrouting here is recoverable |
| Standard | Per-item analysis and building | Most of the work |
| Strongest | Final verification of high-stakes output, in a fresh context that did not produce the work | The expensive failure is a false "looks good" |

Name the tier in the plan. Do not hardcode model ids; let the environment resolve
them.

---

## Step 5: fan-in is where quality is actually lost

A single synthesis step reading 100 outputs produces a worse result than a
layered one, and the degradation is quiet. The output looks fine. It is just thin
on everything after the first twenty items.

Consolidate in layers of **20 to 30 items**:

```
100 file analyses
  -> 4 batch summaries (25 each)
    -> 1 final synthesis
```

Two rules make this work:

1. **Count before you consolidate.** At every fan-in, check received against
   expected. If 38 of 40 came back, name the two that are missing rather than
   synthesising over the gap. A synthesis that silently drops items is worse than
   one that reports a hole. This is a code node, not a judgement.
2. **Preserve specifics upward.** Each batch summary carries file paths, line
   numbers, counts and names, not impressions. Impressions do not compose. "Several
   files had issues" gives the final synthesis nothing to work with.

---

## Step 6: open the gate on blast radius, not on confidence

Most write-ups build a confidence score, set a threshold, and let anything above
it through. That is the wrong variable. **Confidence is the weakest input in the
decision, because it is the only one the model can influence.**

The strong variable is what happens if the change is wrong. Sort work by how
expensive the mistake is to undo:

| Lane | Examples | Gate |
|---|---|---|
| **Reversible and contained** | A copy change, a test, an isolated function with coverage | Deterministic checks. Opens first. One bad merge costs a revert. |
| **Reversible but wide** | A shared utility, a schema addition, anything a dozen callers touch | Deterministic checks, plus a clean trajectory, plus an independent reader. |
| **Hard to reverse** | Migrations, deletions, production writes, sends, anything moving money | **Does not open.** Human approval, executed inline. |

That third row is not a threshold set very high. It is a lane that does not open.
The distinction matters because thresholds get adjusted under pressure and closed
lanes do not.

Inside an open lane, the gate reads evidence in this order:

1. Deterministic results. Tests, types, lint, diff scope, counts.
2. The trajectory of this run. Did the worker thrash? Did it widen scope?
3. History. How often has work from this node been rolled back before?
4. The model's own assessment. Last, and never alone.

---

## Step 7: the two return paths, and the one everyone skips

A graph with no way back is a pipeline. It produces output and forgets. Next week
it starts from the same place with the same blind spots.

Working graphs have two return paths doing different jobs.

**The correction edge is short.** A gate rejects one unit back to the node that
produced it. It fixes the run you are in.

**The learning edge is long.** An accepted result goes back to the *splitter* as
a constraint. It fixes every run after.

Almost everyone builds the first and skips the second. The tell is a system that
is fast and never gets smarter.

The learning edge does not carry the output. It carries a constraint derived from
it:

```
ACCEPTED   utils slice ported, green on first pass
DERIVED    adapters preserve keyword args exactly
LANDS IN   the splitter's brief for every later slice
```

Notice where it lands. Not in the worker's instructions. In the brief that shapes
how the work gets cut. A confirmed cause becomes a rule, so the next break starts
where this one ended.

In practice the learning edge is a file: an append-only `constraints.md` the
splitter reads at the top of every run. If your project already has a durable
memory or a notes vault, that is where it goes.

### Return the unit, not the batch

This is the most expensive mistake on the return path.

Four slices were ported. One fails its tests. If the whole batch goes back, three
correct slices get rewritten. Their next version is different, not better,
because nothing was wrong with them. Now you re-verify all four, and any of the
three may fail this time for unrelated reasons. You converted one failure into
four uncertain outcomes and paid for the privilege. Do it twice in a run and it
never converges.

From the outside this looks like the model failing repeatedly. It is a return
path destroying correct work.

Five things travel with a return, and each one is doing a job:

```
UNIT       handlers slice
VERDICT    red
REASON     test_auth_redirect failed
EVIDENCE   expected 302, got 200, handlers/auth.py:88
SCOPE      fix this file only, do not touch other slices
```

**The SCOPE line matters more than it looks.** Without it a returned unit grows:
the agent opens the file, notices two adjacent issues, fixes those too, and your
one-slice correction becomes a four-file diff nobody reviewed.

**Cap it at three attempts.** If a unit fails three corrections, the problem is
in the plan that produced it, and the loop cannot see the plan. Stop, re-plan,
say what changed. If the same class of failure comes back twice, that is already
the signal: the rubric or the split is wrong.

---

## Step 8: verification, and the compiler the work never came with

Code is unusual in that the resistance arrives free. You write a type mismatch
and the compiler stops you cold, on its own terms, with a verdict anyone can
reproduce. That is the quiet reason coding agents work as well as they do.

Everywhere else, you build the closest thing you can. Graph engineering is what
you do when the compiler is missing at your level.

Three properties make a compiler trustworthy, and all three must be rebuilt by
hand:

| Property | What it is in a graph |
|---|---|
| **Resistance** | Tests, types, counts, diffs. Something that pushes back when the work is wrong. |
| **Independence** | A reader that did not produce the work and does not share its framing. |
| **A public verdict** | The diff, the commands run, the evidence, the risks named. A record someone outside the run can check. |

**Independence is the property that is easy to fake and the first one dropped.**
A second agent used as a reviewer emits crisp pass/fail verdicts and lives in the
same kind of head as the worker. The two can agree, confidently and quietly, on
the same blind spot. A verdict from something that shares your assumptions is
theatre dressed as verification.

So, for anything high-stakes:

- Run verification in a **fresh context** that did not produce the work.
- Give it the **claims and the sources**, not your synthesis. A critique pass over
  a summary mostly agrees with the summary.
- Make it **re-derive at least one claim from source** rather than re-read the
  report.
- Prefer a **different model** for the verifier where the environment allows it.
  Different failure modes catch more than the same failure mode twice.

And know where the replicas stop. A test suite only checks the cases you thought
to write. A reviewer only catches what it happens to notice. You get a
probabilistic shadow of the compiler's guarantee, and the craft is choosing the
cheapest sample of reality that still genuinely resists.

Above a certain height there is no external referent left. "Is this the right
strategy", "is this in good taste", "is this even the right question". Do not
keep stacking verifiers there. Surface the reasoning and the evidence completely,
and hand the judgement to a person.

Full treatment in [references/verifiers.md](references/verifiers.md).

### Anchors and frozen nodes

A graph where every node reads another node's report is circular: an elaborate
network of mutual confirmation in which everything is consistent and nothing is
verified. It fails exactly as a single loop fails, only later, more expensively,
and with far more green lights on the way down.

So the graph needs two things no arrangement of edges supplies:

- **Anchors.** At least one measurement that cannot be argued with. A test that
  actually executed. A byte count. A rendered pixel. A row that landed in the
  database. If every input to your graph is another agent's prose, you have a
  rumour mill.
- **Frozen nodes.** Rules the graph is never allowed to tune, precisely because
  they are the rules an optimiser would be tempted to weaken. The held-out check.
  The closed lane. The approval gate. If a run "needs" to relax one of these, that
  is the finding, not the workaround.

---

## Step 9: the human node

Verification is a quality check, not an authorisation.

Anything irreversible or outward-facing gets its own human approval node after
verification passes, and the graph hard-stops there. Deploys, sends, deletes,
migrations, pushes, production writes, anything a customer sees.

Put the human on **one** step, at the point of highest consequence and lowest
reversibility. Approve the merge. Choose which fixes ship. Not reviewing
intermediate output, not confirming each step. A human in the middle of a graph
becomes the slowest node in it, and the graph then runs exactly as fast as a
person reading things.

The request has to be decidable in seconds: the exact action, its scope, its
cost.

> Merge 7 commits from `port/utils-slice` into `develop`. 23 files, all under
> `src/utils/`. Tests green, types green, no other slice touched. Diff below.

Not "ready to proceed?".

If the human says no, the reason goes into state and the affected nodes redo,
same as a failed gate. **The irreversible action itself always executes inline,
never in a subagent.**

---

## The output: write the phase plan before doing any work

Keep it short enough to read at a glance.

```markdown
## Goal
[One sentence.]

## Dependency audit
[Each step, whether it reads prior output, the variable that crosses, the verdict.
 Then hidden edges, or an explicit statement that none were found.]

## The check
[The GREEN condition, written so a program could evaluate it.]

## Phases
**Phase 1 - parallel (N items, batches of M, width capped at W because <constraint>)**
- [what runs, and why these are independent]

**Phase 2 - depends on Phase 1**
- [what runs, and which output it consumes]

## Consolidation
[Layer structure, and the completeness check: expected vs received.]

## Verification
[What gets checked, by whom, in what context, against what source.]

## Approval gate
[The exact action, scope and cost the human will see. Or "none, nothing irreversible".]

## Risks
[What could make this plan wrong.]
```

Then say what you are about to run, and start phase 1.

**Re-read the plan at each phase boundary.** By phase 3 the original plan has
scrolled well out of working attention. One line restating what this phase
depends on is enough to catch drift.

**Stop and re-plan when the graph is wrong.** Discovering mid-run that two
"independent" items conflict is normal. Revise the plan and say what changed.
Never quietly work around it.

For a plan handed to a scheduler or another agent rather than a person, the
machine-readable form is in [references/plan-schema.md](references/plan-schema.md).
Do not emit it by default. It is noise for a human reader.

---

## Running it

### In Claude Code

Three ways, in ascending order of how much structure you are buying:

| Mechanism | Use when | Cost |
|---|---|---|
| **Parallel `Agent` calls in one turn** | A fan-out phase of 2 to 20 items, one round | Free, immediate |
| **A named agent type in `.claude/agents/*.md`** | The same node recurs across sessions and needs a fixed tool surface and model | One file |
| **The `Workflow` tool** | Deterministic multi-phase orchestration, schemas, resume, live progress | A script, and explicit user opt-in |

Two rules that are not obvious:

- **Multiple independent `Agent` calls must go in a single assistant turn** to run
  concurrently. One per turn is a chain wearing a graph costume.
- **The `Workflow` tool requires the user to have opted in.** Do not reach for it
  because a task would benefit. Describe what it would do and what it would
  roughly cost, and let them ask.

The tool surface of an agent type is itself a gate. An agent defined with
`tools: Read, Write` physically cannot run a command to go find justifying
context. That constrains it more reliably than any instruction.

Full wiring, including hooks, headless `claude -p --output-format json`,
`--json-schema`, `--max-budget-usd`, worktree isolation and scheduled loops, is in
[references/claude-code-mechanics.md](references/claude-code-mechanics.md).

### Somewhere else

If the runtime is Codex, Cursor, Pi, Hermes, LangGraph or Google ADK, or the user
asks to set orchestration up, read
[references/other-runtimes.md](references/other-runtimes.md) **before** writing
anything. It carries a short setup interview to run first, because the wrong
runtime choice is expensive to unwind, and picking a framework is one of the few
decisions here that is genuinely the user's.

A runnable minimal example lives in
[scripts/graph-run.sh](scripts/graph-run.sh): a fan-out, a code-node merge, a
deterministic gate, and a return that carries scope. It is about 120 lines of
shell and no framework, which is the point. Read it before installing anything.

---

## Cost

Graphs are faster in wall-clock and usually more expensive per cycle. Three
parallel reviewers finish in one cycle instead of three, and they cost three
contexts instead of one.

The break-even is the pass rate. Above roughly 50% per cycle, the parallel form
wins on both axes. Below about 30%, a failing graph re-runs every reviewer on
every retry, and the cost explodes while the loop's cost merely grows.

**Monitor cost per successful completion, not wall-clock time.** That is the
number that says whether the graph is paying for itself. If the pass rate is
low, the answer is a better gate or a better split, not more parallelism. More
parallelism on a low pass rate is just a faster way to spend money.

Cap the spend. A graph is many loops, and a weak verifier now burns tokens in
parallel.

---

## Failure modes

| Symptom | Cause | Fix |
|---|---|---|
| Four reports say the same thing | Workers shared a context | Own context per worker, own lens per worker |
| Synthesis is thin after the first 20 items | Single fan-in over too many outputs | Layer the fan-in, 20 to 30 per batch |
| The run "succeeded" but two items vanished | No completeness check | Count expected vs received, as a code node |
| A parallel run corrupted a file | Shared write, missed as a hidden edge | Split on non-overlapping write boundaries |
| The gate always passes | The check is "looks good" or "no errors" | Rewrite the check as a program-evaluable condition |
| Corrections never converge | The batch is returned instead of the unit | Return one unit with UNIT/VERDICT/REASON/EVIDENCE/SCOPE |
| A one-file fix arrives as a four-file diff | No SCOPE line on the return | Add it, and reject diffs outside scope at the gate |
| Fast, and never gets smarter | No learning edge | Derive a constraint, land it in the splitter's brief |
| Everything is green and the bug shipped | Circular verification, no anchor | Add one measurement that cannot be argued with |
| The graph is slower than the chain was | Nodes that were never real specialties | Collapse them back into one loop |
| Machine at 400% CPU, everything crawls | Every worker ran the gate | Gates run once, in the orchestrator |
| Cost tripled, quality flat | Model nodes doing code-node work | Merge, rank, dedupe and count in a script |

---

## Red flags

Any of these means stop and re-plan, not push on:

- You wrote "and then" and did not name the variable that crosses.
- You have not written the failing condition yet.
- A node's job is "review the output" with no rubric and no source.
- The verifier is the same agent, or the same context, that produced the work.
- Every input to the graph is another agent's prose.
- The same class of failure has come back twice.
- A unit is on its fourth correction attempt.
- You are about to let a subagent deploy, send, delete or push.
- You are about to relax a frozen rule so the run can finish.
- The plan has more than about 15 nodes and you cannot explain it in one breath.

---

## Honesty about the label

The mechanics are not new. Directed graphs of states and transitions are decades
of computer science. LangGraph shipped `StateGraph` with nodes, edges and shared
state before the phrase existed. Microsoft AutoGen's GraphFlow did multi-agent
graph orchestration (AutoGen is now in maintenance mode; Microsoft points new
users at the Agent Framework). Google's ADK ships sequential, parallel and loop
workflow agents as first-class pieces. A2A was already the cross-team delegation
layer. LangGraph's own author has said publicly that he is not sure the term
names anything new.

Concede all of it. Then separate the word from the shift.

The escalation is real: a single loop stops being the right shape for the work,
and you split it into coordinated units with state flowing between them and a
gate that can fail. That happens whether or not anyone calls it graph
engineering. **You can build every system in this file and never use the phrase.**

What is not optional is the discipline underneath: a check that can fail, an
independent reader, an anchor in something real, and a human on the one step that
cannot be undone. Those are the parts that stop a fast system from confidently
being wrong at scale.

Three lines hold it:

- Measure the path, not only the answer it landed on.
- A verdict that does not change what runs next is a report.
- Any failure you do not turn into a permanent constraint, you will meet again.
