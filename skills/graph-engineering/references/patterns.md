# Worked graphs

Six topologies, the failure each one stops, and the cost. Read this when picking
a shape. Start from the closest one rather than drawing from scratch.

Notation: `->` is an edge, `=>` is a fan-out, `<=` is a fan-in, `<--` is a return
path.

---

## 0. The chain (the honest baseline)

```
A -> B -> C
```

Five steps where each genuinely feeds the next gains nothing from a graph. Say
"this is a chain", say why, and get on with it. Dressing a chain up as a DAG is
the single most common way this skill gets misapplied.

**Use when:** fewer than about six subtasks, no fan-out, every arrow has a
nameable variable crossing it.

---

## 1. Parallel review

The canonical starter. Three to five reviewers, one lens each, then a merge and a
gate.

```
                 => review:correctness =>
                 => review:contracts   =>
splitter --------=> review:resource    =>------ merge (code node) -> gate -> ship
                 => review:reuse       =>                              |
                                                                       +--> fix <-- (unit only)
```

**Stops:** the serial review that costs three cycles of wall clock, and the
single reviewer that finds only the class of bug it happened to look for first.

**Cost:** N contexts per cycle instead of one. Wins on wall clock immediately.
Wins on total cost above roughly a 50% pass rate.

**Gotchas:**
- Assign the lens explicitly and tell each reviewer to ignore findings outside
  it. Otherwise all four return the same top finding.
- The merge is a **code node**: dedupe by `(file, line, claim-hash)`, rank by
  severity. Not a model.
- The gate returns **one finding's fix**, not the whole review.

**Claude Code:** four `Agent` calls in one turn, then a merge inline. Or the
`Workflow` tool with `pipeline` so each lens's verification starts as soon as that
lens lands.

---

## 2. Fan-out audit with layered fan-in

The shape for "look at all N of these", where N is 20 to 500.

```
splitter => 100 workers => 4 batch summaries (25 each) => 1 synthesis -> verify -> report
                                  ^
                           completeness check (code node): 100 expected, N received
```

**Stops:** the synthesis that reads 100 outputs and goes thin after the first
twenty, silently. And the run that loses two items with nobody noticing.

**Cost:** N + N/25 + 1 contexts. The layering costs about 4% more and is the
difference between a usable report and a plausible one.

**Gotchas:**
- **Count before you consolidate.** Name the missing items, do not synthesise
  over the gap.
- **Batch summaries carry file paths and counts, not impressions.** "Several files
  had issues" gives the final synthesis nothing.
- Batch the workers when per-item work is small. 100 subagents to classify 100
  strings is worse than 4 subagents given 25 each, and much worse than a regex.

---

## 3. Port and verify (migration)

The shape for a migration: TypeScript upgrade, npm to pnpm, framework version
bump, moving a module.

```
                      +-------------------- constraints.md (learning edge) ---+
                      v                                                       |
splitter (by import graph, disjoint files)                                    |
   => port:utils    -> test -> gate -+--> accepted --------------------------+
   => port:handlers -> test -> gate -+--> accepted
   => port:api      -> test -> gate -+
                                     |
                                     +--> red: return UNIT only, with SCOPE
```

**Stops:** the batch return that rewrites three correct slices to fix one, and
the migration that relearns the same adapter quirk on every slice.

**Cost:** one context per slice plus retries. The learning edge pays for itself
by about the fourth slice.

**Gotchas:**
- **Split by the import graph, not by folder.** Folders share files. Import order
  gives you slices that can actually be verified one at a time.
- **The gate's strongest input is the diff scope**, not the tests. A slice that
  passes its tests while touching four files outside its list is a fail.
- **The learning edge lands in the splitter's brief**, not in the worker's
  instructions. It shapes how later work is cut.
- Worktree isolation per slice if any two slices could touch a lockfile or a
  barrel export.

**Companion skills:** `stacked-prs` for landing the result, `sync-main` for
keeping the branch current while it runs.

---

## 4. Research, write, critique (the reflection loop)

Andrew Ng's agentic pattern, drawn as a graph. Nobody writes an essay from the
first word to the last with no backspace, and neither should an agent.

```
plan -> research => sources <= -> generate -> [enough?] -> ship
                                    ^              |
                                    |              v
                        research_critique <---- reflect
```

**Stops:** the one-shot generation that reads like a first draft, because it is
one.

**Cost:** `revisions * (generate + reflect + research)`. Two revisions is usually
the knee of the curve.

**Gotchas:**
- **`max_revisions` is a frozen node.** Without a hard bound the critique loop
  never exits, because a critic can always find something.
- The critique node needs a **rubric**, not "make it better". "Better" is
  unbounded and the loop will chase it.
- The research fan-out inside `research` is a graph in its own right. Do not let
  it become a third nested level.
- Sources accumulate across revisions. In LangGraph terms, `content` is
  annotated with `operator.add`; the draft is not.

---

## 5. Splitter, lanes, gate, human

The production shape. Everything above, plus the blast-radius split and one
human.

```
splitter (by blast radius)
   => lane A: reversible + contained  => workers -> deterministic gate ----------+
   => lane B: reversible + wide       => workers -> gate + independent reader ---+
   => lane C: hard to reverse         => workers -> gate ---------> HUMAN -------+
                                                                                 v
                                                                        merge -> ship
```

**Stops:** the run that treats a copy change and a database migration as the same
risk, and the human who ends up reviewing every intermediate output and becomes
the slowest node in the graph.

**Cost:** the same as the underlying fan-out, plus one human decision.

**Gotchas:**
- Lane C **does not open automatically**, at any confidence. It is a closed lane,
  not a high threshold, because thresholds get adjusted under pressure.
- The human sees one request, decidable in seconds: exact action, scope, cost.
- The irreversible action **executes inline**, never in a subagent.
- If the human says no, the reason goes into state and only the affected nodes
  redo.

---

## 6. Cross-runtime verify

The shape when the verdict has to be trustworthy.

```
worker (Claude, sonnet, writes) -> artifacts
                                      |
                                      v
                      verifier (different vendor, read-only, given SOURCES not the report)
                                      |
                                      v
                                    gate
```

**Stops:** two optimists agreeing. A reviewer that shares the worker's framing
produces an echo, and the echo reads exactly like a verdict.

**Cost:** a second vendor's tokens on the verification node only.

**Gotchas:**
- The verifier gets the **source and the raw output**, never the worker's
  summary. A critique pass over a summary agrees with the summary.
- Constrain the verifier's tools so it physically cannot go and find justifying
  context.
- Make it **re-derive at least one claim from source**.

Wiring in [other-runtimes.md](other-runtimes.md).

---

## Choosing

| The job | Start from |
|---|---|
| Fewer than six steps, each feeds the next | 0. Chain |
| One artifact, several kinds of wrong | 1. Parallel review |
| Many similar items | 2. Fan-out audit |
| Move a codebase from A to B | 3. Port and verify |
| Produce a document that has to be good | 4. Research / write / critique |
| Mixed risk, something ships | 5. Lanes and a human |
| The verdict has to hold up | 6. Cross-runtime verify |

They compose. A real migration is 3 with 1 inside its gate and 5 around the
whole thing. Draw it before you build it. If it will not fit on a napkin, it is
too complex.

---

## Over-engineered, for contrast

> "Summarise this PDF." Five nodes: fetcher, chunker, summariser, reviewer,
> formatter, with conditional edges and a shared state object.

It works. It is slower to build, harder to debug and more expensive to run than
the one thing it should have been: an agent in a loop that reads the file and
writes a summary. That is engineering an org chart to answer an email.

The tell is always the same question. **Is any node doing work a single loop
could not?** If not, collapse it.
