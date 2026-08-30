# Node catalogue

Read this when writing an actual node: what its prompt says, what it returns,
and how the splitter cuts the work.

Four kinds. Splitter, worker, code node, gate.

---

## 1. Splitter

Sits at the front. Decides more than any other node, because splitting on the
wrong dimension wastes everything downstream. **Always runs in the orchestrator.
Never delegated.**

### Choosing the dimension

Cut a repository by folder and four workers audit the same three shared files.
Cut by blast radius and each one sees something the others cannot.

| Dimension | Slice looks like | Use when | Fails when |
|---|---|---|---|
| **Blast radius** | "reversible + contained", "reversible + wide", "hard to reverse" | Mixed reversibility in one job | Everything is equally safe |
| **Ownership / import graph** | One module and its direct dependents | Refactors, ports, dependency work | Modules are tangled with no seams |
| **Failure class** | "security", "correctness", "performance", "accessibility" | Audits and reviews, one lens per worker | The lenses overlap heavily |
| **Entity** | One customer, one endpoint, one document, one ticket | Naturally itemised work | Entities share mutable state |
| **Time slice** | One hour of logs, one release window | Incident work, log analysis | Order does not matter |
| **File set** | Explicit, disjoint file lists | Any job with writes | You cannot enumerate the files up front |

### Non-negotiables

- **Slices must not overlap in writes.** Two agents editing one file is data
  loss, not a race you can retry. If two slices need the same file, order them or
  merge them.
- **Enumerate the slice.** "Everything under src/" is not a slice. A list of 23
  paths is. The gate needs the list to check that the diff stayed in scope.
- **Read the constraints file first.** The learning edge lands here. If a
  previous run derived "adapters preserve keyword args exactly", the brief for
  every later slice carries it.

### The brief the splitter writes

Every worker gets the same shape, differing only in its slice:

```
CONTEXT      <the shared background, pasted in full, not referenced>
CONSTRAINTS  <accumulated rules from previous runs>
YOUR SLICE   <the enumerated unit>
YOUR LENS    <the one question this worker answers>
OUTPUT       <the exact schema, with an example>
OUT OF SCOPE <what to leave alone even if it looks wrong>
```

The last line is not politeness. Without it, a worker that notices an adjacent
problem fixes it, and your one-slice change becomes a diff nobody reviewed.

---

## 2. Worker

One unit, one lens, its own context.

### The prompt is self-contained or it is broken

A worker that has to ask a question is a worker that has blocked. Paste the
context in. Do not write "see the plan above"; there is no above. Do not write
"the usual conventions"; state them.

### One lens per worker

Give four auditors a shared window and they converge. The first writes a finding,
the rest read it, and all four reports centre on the same thing. You paid four
times for one opinion with three echoes.

Even with separate contexts, four workers given the same open-ended brief return
overlapping findings. Assign the lens explicitly:

```
Worker 1  lens: correctness. Wrong output, off-by-one, unhandled null, race.
Worker 2  lens: contracts. Public API changes, type widening, breaking callers.
Worker 3  lens: resource. Leaks, unbounded growth, N+1, missing cleanup.
Worker 4  lens: reuse. Code that duplicates something that already exists here.
```

Then say, in each prompt: **"Report only findings in your lens. If you notice
something outside it, ignore it. Another worker owns it."**

### The output contract

Same shape for every worker in the group. Ragged outputs push reconciliation work
into the fan-in step, which is where quality is already thinnest.

```json
{
  "unit": "src/utils/date.ts",
  "status": "ok" | "findings" | "error",
  "findings": [
    {
      "file": "src/utils/date.ts",
      "line": 88,
      "severity": "high" | "medium" | "low",
      "claim": "one sentence",
      "evidence": "the failing input and the wrong output",
      "confidence": "high" | "medium" | "low"
    }
  ],
  "notes": "anything that does not fit the schema"
}
```

Two fields earn their place:

- **`evidence` is not optional.** A finding with no concrete failure case is an
  impression. Impressions do not compose upward and cannot be verified.
- **`status: "error"` is a valid result.** A worker that hit a missing file should
  report that, not invent an answer. Errors travel as data.

### Batch size

| Per-item work | Shape |
|---|---|
| Substantial: read and analyse a file, research a company | One item per worker |
| Small: classify a line, extract a field | Batches of items per worker |

Spawn cost is real. Twenty subagents to classify twenty strings is worse than one
subagent given twenty strings, and much worse than a regex.

---

## 3. Code node

**The one people forget exists.**

Merging results, ranking them, deduplicating, comparing every export before and
after a refactor, counting whether 40 of 40 came back, diffing two lists,
grouping by file: none of that is reasoning. Each has exactly one correct answer,
each is a few lines of code, and putting it through a model adds cost, latency
and variance to a step that had none.

**The test: if you can describe the transformation without the words judge,
decide, assess or summarise, it is code.**

Common code nodes, in rough order of value:

| Node | Why it must be code |
|---|---|
| **Completeness check** | expected vs received. A model will synthesise over a gap. A script cannot. |
| Dedupe findings by (file, line, claim-hash) | Deterministic. A model will merge two distinct findings or split one. |
| Rank by severity then file | Deterministic. A model reorders on re-read. |
| Diff public exports before/after | An anchor. This is the thing that catches a broken API. |
| Diff scope: files touched vs files planned | The gate's strongest input. |
| Group by owner / module | Deterministic. |
| Count suppressions added (`@ts-ignore`, lint disables) | The Goodhart pair for "types are clean". |
| Token/byte budget of the fan-in payload | Stops the synthesis node overflowing silently. |

The completeness check is worth stating on its own:

```bash
expected=40
received=$(ls results/*.json | wc -l | tr -d ' ')
if [ "$received" -ne "$expected" ]; then
  echo "INCOMPLETE: $received/$expected"
  comm -13 <(ls results | sed 's/.json//' | sort) <(cat units.txt | sort)
  exit 1
fi
```

A synthesis that silently drops items is worse than one that reports a hole.

---

## 4. Gate

Pass, fail, or return with a reason. Runs **once, in the orchestrator**, not in
every worker.

That last point is operational, not stylistic. Four self-verifying workers that
each start a test runner will saturate the machine, and the run gets slower than
the serial version it replaced.

### Evidence order

1. **Deterministic results.** Tests, types, lint, diff scope, counts, export
   diff. If any of these is red, the gate is red. No discussion.
2. **Trajectory.** Did the worker thrash? Did it widen scope? Did it disable a
   check to get green? Read the path, not only the answer it landed on.
3. **History.** How often has work from this node been rolled back?
4. **The model's own assessment.** Last, and never alone. It is the only input
   the model can influence.

### The three lanes

| Lane | Gate | Opens |
|---|---|---|
| Reversible and contained | Deterministic checks only | Automatically |
| Reversible but wide | Deterministic checks + clean trajectory + independent reader | Automatically, on all three |
| Hard to reverse | Human approval, action executed inline | **Never automatically** |

Thresholds get adjusted under pressure. Closed lanes do not. Keep the third row a
lane, not a very high threshold.

### The return payload

When the gate says no, five fields travel back, and each is doing a job:

```
UNIT       handlers slice
VERDICT    red
REASON     test_auth_redirect failed
EVIDENCE   expected 302, got 200, handlers/auth.py:88
SCOPE      fix this file only, do not touch other slices
```

- Without **REASON** the worker guesses at what was wrong.
- Without **EVIDENCE** it fixes a different bug.
- Without **SCOPE** the correction grows into a diff nobody reviewed.

**Return the unit, not the batch.** Four slices ported, one red: sending all four
back rewrites three correct slices into different-but-not-better versions, then
makes you re-verify all four. One failure becomes four uncertain outcomes. Do it
twice and the run never converges. From outside this looks like the model failing
repeatedly. It is the return path destroying correct work.

**Cap at three attempts.** If a unit fails three corrections, the problem is in
the plan that produced it, and the loop cannot see the plan. Stop, re-plan, and
say what changed.

---

## Node sizing

| Nodes | Verdict |
|---|---|
| 1 | A loop. Correct for most work. |
| 3 to 5 | The right size for a first graph. Splitter, workers, merge, gate. |
| 6 to 15 | Fine if every node is a real specialty and you can explain it in one breath. |
| 15+ | Almost always over-built. Collapse the nodes that were steps. |

Start at 3 to 5. Add a node only after you have measured the bottleneck it is
supposed to relieve.
