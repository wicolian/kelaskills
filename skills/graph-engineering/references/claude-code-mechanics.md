# Wiring a graph in Claude Code

Read this when actually building the thing in Claude Code. Everything below was
checked against Claude Code **2.1.251** on macOS. Run `claude --help` and `/hooks`
to confirm against your version before trusting a flag or an event name.

Four mechanisms, in ascending order of structure. Pick the least one that works.

---

## 1. Parallel `Agent` calls: the default fan-out

The cheapest graph you can build. Nothing to install, nothing to write.

**The rule that decides whether it is a graph at all: multiple independent
`Agent` calls must go in a single assistant turn to run concurrently.** One call
per turn is a chain wearing a graph costume, and it is the single most common way
a "parallel" plan runs serially.

Parameters worth knowing:

| Parameter | Effect |
|---|---|
| `subagent_type` | Selects an agent definition. Omit for `general-purpose`. |
| `subagent_type: "fork"` | Forks you, inheriting the full conversation. Runs on your model; a `model` override is ignored. |
| `model` | `sonnet`, `opus`, `haiku`, `fable`. This is the tiering lever. |
| `isolation: "worktree"` | Gives the agent its own git worktree. Auto-cleaned if unchanged. |
| `isolation: "remote"` | Runs in a remote cloud environment, always in the background. |

Three properties that matter for graph design:

- **Each subagent gets a fresh context.** This is the whole reason fan-out beats a
  long loop. Item 47 is not degraded by 46 items of accumulated state.
- **Its tool output stays out of your context.** You keep the conclusion, not the
  file dumps. That is what makes a 40-file audit survivable.
- **Its final report is not shown to the user.** Relay what matters, in your own
  words. Never invent or predict a pending agent's result; wait for the
  notification.

Continue an agent with `SendMessage` addressed by name or id, and its context
stays intact. A fresh `Agent` call starts over. `ListAgents` shows what you can
address.

`isolation: "worktree"` is the correct answer to the shared-write hidden edge.
Two workers that both need to edit `package.json` are not independent, unless
each one is in its own worktree and you merge afterwards.

### Concurrency ceiling

```json
// ~/.claude/settings.json
{ "env": { "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": "40" } }
```

This is the width cap when nothing else binds. Usually something else does: an
API rate limit, a single dev server, or the machine. Name the binding constraint
in the plan rather than defaulting to the ceiling.

---

## 2. `.claude/agents/*.md`: a node that recurs

When the same node appears across sessions and needs a fixed tool surface and
model, define it once. Markdown with YAML frontmatter, in `.claude/agents/` at
project or user level.

```markdown
---
name: port-verifier
description: Verifies one ported slice against its source. Reads only. Cannot run commands, cannot browse, cannot edit. Given the source file, the ported file and the test output, returns a strict pass/fail verdict with evidence.
tools: Read, Write
model: opus
skills:
  - graph-engineering
---

You verify ONE ported slice. You have `Read` and `Write` only, by design.

You cannot run a command, curl anything, or grep the wider codebase. The tool
surface is the rationalization gate: the verdict must come from the artifacts
you were given, not from context you went looking for to justify a pass.

## Input
The dispatch prompt gives you: `source_path`, `ported_path`, `test_output_path`,
and the slice's acceptance criteria.

## Output
Write `result.json`:
{ "unit": "...", "verdict": "pass"|"fail", "reason": "...", "evidence": "..." }

`fail` needs a concrete failing case with a file and a line. A verdict with no
evidence is not a verdict. If the artifacts do not let you decide, write
`"verdict": "unverifiable"` and say what is missing. Never guess to be helpful.
```

Frontmatter fields in use today: `name`, `description`, `tools`, `model`,
`skills`. Anything not listed in `tools` is genuinely unavailable to that agent.

**The tool surface is your strongest gate.** An agent that physically cannot run
`grep` cannot go and find the context that would let it rationalise a pass. That
constrains behaviour more reliably than any instruction, because it is not
negotiable.

Ad-hoc alternative, no file needed:

```bash
claude --agents '{"reviewer":{"description":"Reviews code","prompt":"You are a code reviewer"}}'
```

---

## 3. The `Workflow` tool: deterministic orchestration

Use when you need real multi-phase structure: schemas, resume, live progress, and
a plan that does not drift because the model re-read it.

**It requires the user to have opted in.** Do not reach for it because a task
would benefit. Describe what it would do and roughly what it would cost, and let
them ask. It can spawn dozens of agents.

Every script starts with a pure literal `meta` block, then uses
`agent()`, `parallel()`, `pipeline()` and `phase()`:

```javascript
export const meta = {
  name: 'audit-changed-files',
  description: 'Review changed files across four lenses, verify each finding',
  phases: [{ title: 'Review' }, { title: 'Verify' }],
}

const LENSES = [
  { key: 'correctness', prompt: '...' },
  { key: 'contracts',   prompt: '...' },
  { key: 'resource',    prompt: '...' },
  { key: 'reuse',       prompt: '...' },
]

// pipeline: each lens verifies as soon as its own review lands.
// No waiting for the slowest reviewer before any verification starts.
const results = await pipeline(
  LENSES,
  l => agent(l.prompt, { label: `review:${l.key}`, phase: 'Review', schema: FINDINGS }),
  review => parallel(review.findings.map(f => () =>
    agent(`Adversarially verify: ${f.claim}`, {
      label: `verify:${f.file}`, phase: 'Verify', schema: VERDICT,
    }).then(v => ({ ...f, verdict: v }))
  ))
)

const confirmed = results.flat().filter(Boolean).filter(f => f.verdict?.isReal)
return { confirmed }
```

Notes that save time:

- **Pass the script inline via `script`.** Do not write it to a file first, and do
  not also set the tool's `name` input; that selects a saved workflow instead.
- **It is plain JavaScript, not TypeScript.**
- Every invocation persists its script under the session directory and returns
  the path. To iterate, edit that file and re-invoke with the same `scriptPath`
  rather than re-sending the whole thing.
- `resumeFromRunId` re-runs only edited or new `agent()` calls. Completed calls
  with unchanged `(prompt, opts)` return cached results instantly. Same session
  only, and stop the prior run with `TaskStop` first.
- `schema` on an `agent()` call is the output contract from
  [node-catalogue.md](node-catalogue.md), enforced.
- Load the `workflow-authoring` skill before writing one. It has the full API and
  the gotchas.
- Watch it with `/workflows`.

**`pipeline` over `parallel` then `parallel` whenever a downstream node depends on
one upstream item rather than all of them.** That is the same dependency audit
applied to scheduling: verification of lens A does not read lens B's output, so
it should not wait for it.

---

## 4. Headless CLI: a graph in shell, no framework

When the graph should survive a session, run in CI, or be reproducible, drive
`claude -p` from a script. This is also how you build a graph a *different* agent
can run.

The flags that make it work:

| Flag | Why it matters |
|---|---|
| `-p, --print` | Non-interactive. Print and exit. |
| `--output-format json` | Parseable result. `stream-json` for realtime. |
| `--json-schema '<schema>'` | Structured output validation. The output contract, enforced, without a framework. |
| `--max-budget-usd <n>` | Spend cap per node. **Use this on every fan-out.** |
| `--model <alias>` | Per-node tiering: `haiku`, `sonnet`, `opus`, `fable`. |
| `--effort <low\|medium\|high\|xhigh\|max>` | Second tiering axis. Cheap nodes do not need max. |
| `--tools "Read,Grep"` | Restrict the built-in tool surface for this node. |
| `--allowedTools` / `--disallowedTools` | Finer control, e.g. `"Bash(git *)"`. |
| `--permission-mode` | `acceptEdits`, `plan`, `dontAsk`, `bypassPermissions`, `manual`, `auto`. |
| `--restricted` | Removes command-running tools and WebFetch, confines file tools to the working dirs, refuses `bypassPermissions`. The strongest sandbox for a read-only verifier node. |
| `--append-system-prompt` | Inject the lens without rewriting the whole prompt. |
| `--add-dir` | Extra directories a node may read. |
| `-w, --worktree [name]` | Isolate a writing node in its own git worktree. |
| `--fallback-model a,b` | Survive an overloaded model mid-run. `--print` only. |
| `--session-id <uuid>` / `-r, --resume` | Address a node again later. |
| `--fork-session` | Resume without reusing the original session id. |
| `--bg` | Run detached. Returns a short id. |
| `--settings <file-or-json>` | Per-node settings without touching your own. |
| `--strict-mcp-config` | Ignore ambient MCP servers. Reproducibility. |

Background sessions are managed with `claude agents`, `claude attach <id>`,
`claude logs <id>`, `claude respawn <id>`, `claude rm <id>`.

A worker node, complete:

```bash
claude -p "$(cat prompts/worker-$slice.md)" \
  --model sonnet \
  --output-format json \
  --json-schema "$(cat schemas/finding.json)" \
  --max-budget-usd 0.50 \
  --tools "Read,Grep,Glob" \
  --permission-mode dontAsk \
  > "results/$slice.json"
```

A verifier node that physically cannot cheat:

```bash
claude -p "$(cat prompts/verify-$slice.md)" \
  --model opus --effort high \
  --restricted --tools "Read" \
  --add-dir ./results --add-dir ./src \
  --output-format json --max-budget-usd 1.00 \
  > "verdicts/$slice.json"
```

**The pipefail trap.** `claude -p ... | tee log` returns the exit status of `tee`.
A failed node looks green. Put `set -euo pipefail` at the top of every graph
script, or capture the status before you pipe.

A runnable end-to-end example, fan-out plus code-node merge plus gate plus a
scoped return, is in [../scripts/graph-run.sh](../scripts/graph-run.sh).

---

## Hooks: gates the model cannot skip

A hook is a command the harness runs, not the model. That is the point: **a gate
in a hook cannot be talked out of.** Everything in this file so far is a gate the
model chooses to respect. A hook is one it cannot reach.

Shape, in `settings.json` at user, project or local level:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command", "command": "bash .claude/hooks/scope-guard.sh", "timeout": 20 }
        ]
      }
    ]
  }
}
```

Event names present in 2.1.251: `PreToolUse`, `PostToolUse`, `UserPromptSubmit`,
`SessionStart`, `SessionEnd`, `Stop`, `SubagentStart`, `SubagentStop`,
`PreCompact`, `PostCompact`, `Notification`, `TaskCompleted`. Run `/hooks` to see
what your build actually exposes and what each one receives.

Graph uses that pay for themselves:

| Hook | Graph job |
|---|---|
| `PreToolUse` on `Bash` | Block the closed lane. A pattern match on `git push --force`, `rm -rf`, `npm publish`, `DROP TABLE` stops it before it runs. |
| `PostToolUse` on `Edit\|Write` | Scope guard. Compare the touched path against the slice's file list, fail loudly if it drifted. |
| `SubagentStop` | Completeness ledger. Append the unit id to a file. The code node counts that file. |
| `Stop` | Refuse to finish while the gate is red. |
| `SessionStart` | Load the constraints file. This is the learning edge, made automatic. |

Hook output is treated as user feedback, so a hook that prints "scope violation:
edited src/api/auth.ts, not in slice" lands in the model's context as a
correction, not as a silent failure.

---

## Worktrees: the answer to shared writes

The most common hidden edge is two nodes editing one file. Git worktrees remove
it by construction.

- `Agent` tool: `isolation: "worktree"`.
- CLI: `claude -w <name>` or `claude --worktree <name>`, plus `--tmux` for panes.
- In-session: `EnterWorktree` / `ExitWorktree`.
- The `superpowers:using-git-worktrees` skill covers the manual route.

Rule: **one writer per path, always.** Either the split is disjoint by file, or
each writer is in its own worktree and a code node merges afterwards. There is no
third option that is safe.

---

## Scheduled and self-paced graphs

Two different tools, easy to confuse:

- **`CronCreate`** for a graph that fires on a schedule. The nightly audit, the
  hourly drift check.
- **`ScheduleWakeup`** for `/loop` dynamic mode, where you decide the next
  interval yourself.

The pacing rule that saves money: this session's prompt cache has a five-minute
TTL. Sleeping past 300 seconds means the next wake-up reads your full context
uncached. So stay under 270s when you are genuinely polling external state, or
commit to 1200s or more so one cache miss buys a long wait. **Never pick exactly
300s**, it is the worst of both.

Do not poll for harness-tracked background work. You are re-invoked automatically
when it finishes. Schedule a long fallback (1200s+) only so the loop survives a
hang.

---

## Model tiering, concretely

| Tier | Alias | Nodes |
|---|---|---|
| Fast / cheap | `haiku` | Classification, extraction, completeness checks, "does every expected item appear" |
| Standard | `sonnet` | Per-item analysis, per-slice building. Most of the work. |
| Strong | `opus` | The splitter's brief, the final synthesis, high-stakes verification |
| Alternate | `fable` | A second opinion with different failure modes |

`--effort` is the second axis and it is cheaper to turn than the model. A `haiku`
node at `low` and an `opus` node at `max` differ by orders of magnitude in cost.

For the verification node specifically, a **different** model beats the same
model at a higher effort. Different failure modes catch more than the same
failure mode twice. That is the independence property from
[verifiers.md](verifiers.md), bought with a flag.

---

## What to reach for, in order

1. Can one loop do it? Do that.
2. Fan out with parallel `Agent` calls in one turn. Still no files.
3. A node recurring across sessions? Give it an `.claude/agents/*.md` definition.
4. Two nodes writing the same paths? Worktree isolation.
5. A gate the model must not be able to skip? A hook.
6. Deterministic phases, schemas, resume, and the user has asked for
   orchestration? The `Workflow` tool.
7. Must survive the session, or run in CI, or be driven by a different agent?
   Headless `claude -p` in a script.

Stop at the first one that works.
