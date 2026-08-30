# Machine-readable plan

Read this only when the plan is handed to a scheduler, a runner, or another
agent. **Do not emit it for a human.** It is noise next to the markdown plan in
SKILL.md.

Use it when: a shell runner consumes the plan, a `Workflow` script is generated
from it, or a second agent has to execute a graph you designed and you need the
handoff to be lossless.

## Schema

```json
{
  "goal": "One sentence.",
  "check": {
    "green": "A condition a program could evaluate.",
    "command": "npm test && npx tsc --noEmit",
    "anchor": "the test process exit code, not an agent's report"
  },
  "constraints_file": "constraints.md",
  "nodes": [
    {
      "id": "split",
      "kind": "splitter",
      "runs_in": "orchestrator",
      "dimension": "import-graph",
      "reads": [],
      "writes": ["units.json", "briefs/"]
    },
    {
      "id": "port",
      "kind": "worker",
      "runs_in": "subagent",
      "fan_out_over": "units.json",
      "width_cap": 8,
      "width_cap_reason": "one dev server; slices share :3000",
      "model_tier": "standard",
      "tools": ["Read", "Edit", "Bash(npm test)"],
      "isolation": "worktree",
      "reads": ["briefs/{unit}.md"],
      "writes": ["out/{unit}.json"],
      "output_schema": "schemas/finding.json",
      "budget_usd": 0.5
    },
    {
      "id": "count",
      "kind": "code",
      "runs_in": "script",
      "command": "scripts/completeness.sh units.json out/",
      "reads": ["units.json", "out/"],
      "writes": ["complete.txt"],
      "on_fail": "halt"
    },
    {
      "id": "verify",
      "kind": "worker",
      "runs_in": "subagent",
      "model_tier": "strong",
      "independence": {
        "fresh_context": true,
        "different_model": true,
        "given": ["sources", "raw_test_output"],
        "not_given": ["the worker's report", "the orchestrator's synthesis"]
      },
      "reads": ["src/", "out/"],
      "writes": ["verdicts/{unit}.json"]
    },
    {
      "id": "gate",
      "kind": "gate",
      "runs_in": "orchestrator",
      "lane": "reversible-wide",
      "evidence_order": ["deterministic", "trajectory", "history", "model"],
      "max_attempts": 3,
      "on_fail": {
        "return_to": "port",
        "granularity": "unit",
        "payload": ["unit", "verdict", "reason", "evidence", "scope"]
      }
    },
    {
      "id": "approve",
      "kind": "human",
      "runs_in": "inline",
      "required_because": "merge to a shared branch",
      "request": {
        "action": "merge port/utils-slice into develop",
        "scope": "23 files, all under src/utils/",
        "cost": "irreversible without a revert commit"
      }
    }
  ],
  "edges": [
    { "from": "split",  "to": "port",    "type": "fan_out", "carries": "units[]" },
    { "from": "port",   "to": "count",   "type": "fan_in",  "carries": "results[]" },
    { "from": "count",  "to": "verify",  "type": "sequential", "carries": "results[]" },
    { "from": "verify", "to": "gate",    "type": "sequential", "carries": "verdicts[]" },
    { "from": "gate",   "to": "port",    "type": "correction", "carries": "one unit + scope" },
    { "from": "gate",   "to": "split",   "type": "learning",   "carries": "derived constraint" },
    { "from": "gate",   "to": "approve", "type": "sequential", "carries": "the diff" }
  ],
  "hidden_edges": [
    { "kind": "shared_write", "detail": "package-lock.json", "mitigation": "worktree per slice" },
    { "kind": "shared_runtime", "detail": "one dev server on :3000", "mitigation": "width cap 8" }
  ],
  "hidden_edges_checked": true,
  "frozen": [
    "lane hard-to-reverse never opens automatically",
    "max_attempts is 3",
    "the verifier never sees the worker's report"
  ],
  "risks": [
    "the import graph may not be acyclic; if it is not, the split is wrong"
  ]
}
```

## Field notes

- **`hidden_edges_checked`** is required and must be `true`. An empty
  `hidden_edges` array with this field absent means the check was skipped, not
  that there are none.
- **`width_cap_reason`** is required whenever `width_cap` is set. A cap with no
  named constraint is a guess, and guesses get raised under pressure.
- **`model_tier`** is a tier name, never a model id. The runner resolves it. Model
  ids in a plan go stale and get copied into the next plan.
- **`on_fail.granularity`** must be `"unit"` for any node that fans out.
  `"batch"` is the return path that destroys correct work.
- **`independence`** on a verify node is not documentation. A runner should refuse
  to schedule a verify node whose `given` includes the producing node's own
  output.
- **`kind: "human"` implies `runs_in: "inline"`.** A runner should reject any
  other value.
- **`frozen`** entries are assertions the runner checks before each phase, not
  comments. If a run needs one relaxed, that is the finding.

## Emitting it

Generate this from the markdown plan, not instead of it. The markdown is what a
person reviews and approves. The JSON is what a machine executes. If the two
disagree, the markdown is wrong and the run should stop, because a human said yes
to something other than what is about to happen.
