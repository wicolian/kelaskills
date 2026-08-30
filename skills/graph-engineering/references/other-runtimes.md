# Running the graph somewhere other than Claude Code

Read this when the runtime is not Claude Code, when the graph must span more than
one runtime, or when the user asks to "set up orchestration" / "set up multi-agent"
/ "wire this into Pi" / "use LangGraph".

Flags below were checked on macOS in August 2026 against the CLIs installed on
this machine. Run `<tool> --help` before trusting one.

---

## Part 1: the setup interview. Run this first.

**Picking a runtime or a framework is one of the few decisions in this skill that
is genuinely the user's.** It is expensive to unwind, it commits them to a
dependency, and there is no obvious default. Ask. Everything else in graph
engineering you should just do.

Four questions. Ask them together, not one at a time. Skip any the user has
already answered.

### Q1. Where does this graph have to run?

| Answer | Implication |
|---|---|
| Inside my current session | Parallel `Agent` calls. Nothing to install. Stop here. |
| A script I can re-run | Headless CLI in shell. `scripts/graph-run.sh` is the starting point. |
| CI, or a server, on a schedule | Headless CLI plus a cron. Pin the model. Cap the spend. |
| A product I am shipping | A framework. LangGraph or Google ADK. Go to Q4. |

### Q2. One runtime, or several?

One is almost always right. Several is right for exactly one reason: **you want
different failure modes on the verifier than on the worker.** A Claude worker and
a GPT verifier disagree in ways two Claude passes do not, and that disagreement
is the independence property you are trying to buy.

Several is wrong when the reason is "we have both installed".

### Q3. What is the irreversible step, and who approves it?

If the answer is "nothing is irreversible", say so in the plan and move on. If
there is one, it gets a human node, executes inline, and never goes in a
subagent. Confirm who that human is and how they will be asked.

### Q4. If a framework: which, and are you sure you need one?

Ask this last and ask it honestly. Most graphs are 3 to 5 nodes and a shell
script beats a framework at that size. A framework earns its keep when you need
persisted state across restarts, time-travel over past states, a running server,
or a team maintaining it after you.

| Framework | Buy it for | Cost |
|---|---|---|
| **LangGraph** | `StateGraph` with nodes/edges/shared state, checkpointers (SQLite, Postgres, Redis), `interrupt_before` for human-in-the-loop, state history and time travel | Python/JS dependency, LangChain gravity |
| **Google ADK** | Named sequential / parallel / loop workflow agents, agent routing, fan-out and fan-in as first-class pieces, A2A | Google ecosystem |
| **Microsoft Agent Framework** | AutoGen's named successor, multi-agent orchestration with A2A and MCP | .NET/Python gravity |
| **AutoGen (GraphFlow)** | Nothing new. It is in maintenance mode, community managed, no new features. | Prior art only. Do not start here. |
| **Nothing** | 3 to 5 nodes, one machine, work you own | You write the loop yourself |

Do not present this as a survey. Recommend one, give the reason in a sentence,
and let them override.

---

## Part 2: the same node in every CLI

Every runtime here supports the four things a graph node needs: a non-interactive
run, a restricted tool surface, a structured output, and a file to write into.
The names differ. The shape does not.

| Need | Claude Code | Codex | Cursor | Pi |
|---|---|---|---|---|
| Non-interactive | `-p` | `codex exec` | `-p` | `-p` |
| Structured output | `--output-format json` | `--json` | `--output-format json` | `--mode json` |
| Enforce a schema | `--json-schema '<json>'` | `--output-schema FILE` | (post-validate) | (post-validate) |
| Write the result to a file | redirect | `-o, --output-last-message FILE` | redirect | redirect |
| Read-only node | `--restricted --tools "Read"` | `-s read-only` | `--mode ask` or `--plan` | `--tools read` |
| Restrict tools | `--tools`, `--allowedTools` | `-c` config override | (mode only) | `-t` / `-xt` |
| Pick the model | `--model` | `-m` | `--model` | `--provider` + `--model` |
| Reasoning effort | `--effort` | `-c model_reasoning_effort=...` | model bracket syntax | `--thinking` |
| Extra writable dir | `--add-dir` | `--add-dir` | (cwd) | (cwd) |
| Working root | (cwd) | `-C, --cd DIR` | (cwd) | (cwd) |
| Spend cap | `--max-budget-usd` | (none) | (none) | (none) |
| Address it again | `--session-id` / `-r` | `codex exec resume` | `--resume` | `--session-id` / `-r` |
| Fork a session | `--fork-session` | `codex exec fork` | (none) | `--fork` |
| Ephemeral | `--no-session-persistence` | `--ephemeral` | (none) | `--no-session` |
| Bypass everything | `--dangerously-skip-permissions` | `--dangerously-bypass-approvals-and-sandbox` | `--yolo` / `-f` | (permissive by default) |

**Only Claude Code has a per-node spend cap.** On the other runtimes, cap the
graph instead: bound the number of nodes, bound the retries at three, and check
your provider dashboard after the first full run before you schedule it.

### The same worker node, four ways

```bash
# Claude Code
claude -p "$(cat prompts/worker.md)" --model sonnet \
  --output-format json --json-schema "$(cat schemas/finding.json)" \
  --max-budget-usd 0.50 --tools "Read,Grep,Glob" > "out/$id.json"

# Codex
codex exec "$(cat prompts/worker.md)" -m gpt-5.5 \
  -s read-only --output-schema schemas/finding.json \
  --skip-git-repo-check -o "out/$id.json"

# Cursor
cursor-agent -p "$(cat prompts/worker.md)" --model sonnet-4-thinking \
  --output-format json --mode ask > "out/$id.json"

# Pi
pi -p --mode json --provider anthropic --model sonnet \
  --thinking medium -t read,bash "$(cat prompts/worker.md)" > "out/$id.json"
```

Four nodes, one graph, no framework. The orchestrator is the shell script that
launches them, counts the results, and runs the gate.

### Cross-runtime verifier

The single highest-value use of a second runtime:

```bash
# worker: Claude
claude -p "$(cat prompts/port-$slice.md)" --model sonnet \
  --output-format json --max-budget-usd 1.00 > "out/$slice.json"

# verifier: a different model, different vendor, read-only, sources not synthesis
codex exec "$(cat prompts/verify.md)" -m gpt-5.5 -s read-only \
  --output-schema schemas/verdict.json -o "verdicts/$slice.json"
```

The verifier gets the source file, the ported file and the raw test output. It
does not get the worker's report. See [verifiers.md](verifiers.md) for why that
distinction is the whole point.

---

## Part 3: agents and skills, per runtime

A node definition lives in a different place in each runtime. The graph does not
change.

| Runtime | Agent / subagent definition | Project instructions | Skills |
|---|---|---|---|
| Claude Code | `.claude/agents/*.md` (`name`, `description`, `tools`, `model`, `skills`) | `CLAUDE.md` | `.claude/skills/`, `~/.claude/skills/`, `~/.agents/skills/` |
| Codex | Config profiles: `$CODEX_HOME/<name>.config.toml`, used with `-p <name>` | `AGENTS.md` | `~/.codex/skills/` |
| Cursor | Modes (`--mode plan`/`ask`), rules files | `AGENTS.md` | `~/.cursor/skills/` |
| Pi | Extensions (`-e`), skills (`--skill`), prompt templates | `AGENTS.md`, `CLAUDE.md` (both discovered) | `~/.pi/agent/skills/`, `.pi/skills/` |
| Hermes | Agent config | `AGENTS.md` | `~/.hermes/skills/` |
| Cross-runtime | n/a | `AGENTS.md` | `~/.agents/skills/`, project `.agents/skills/` |

Two practical consequences:

- **Put a shared graph skill in `~/.agents/skills/`.** Claude Code, Codex, Cursor,
  Hermes and Pi all read it, so one copy serves every node in a cross-runtime
  graph.
- **`AGENTS.md` is the near-universal project instruction file.** If your graph
  spans runtimes, the constraints file from the learning edge belongs there, or in
  a file `AGENTS.md` points at. Claude Code reads `CLAUDE.md`; Pi reads both.

Codex config profiles are the closest analogue to a Claude Code agent definition.
A read-only verifier profile:

```toml
# ~/.codex/verifier.config.toml
model = "gpt-5.5"
sandbox_permissions = ["disk-full-read-access"]
model_reasoning_effort = "high"
```

```bash
codex exec -p verifier "$(cat prompts/verify.md)" -o verdicts/$slice.json
```

---

## Part 4: LangGraph, if a framework is the answer

LangGraph is the reference implementation of everything in this skill, and its
vocabulary maps one to one:

| This skill | LangGraph |
|---|---|
| Node | `graph.add_node(name, fn)` |
| Edge | `graph.add_edge(a, b)` |
| Gate / conditional routing | `graph.add_conditional_edges(a, should_continue, {...})` |
| Shared state | The `AgentState` `TypedDict` passed to `StateGraph` |
| Accumulating vs replacing state | `Annotated[list, operator.add]` accumulates. Unannotated replaces. |
| Human approval node | `graph.compile(interrupt_before=["action"])` |
| Persistence, resume | A checkpointer: `SqliteSaver`, Postgres, Redis |
| Parallel branches | Multiple edges out of one node, joined downstream |
| Return path | An edge back to an earlier node |

Three things it gives you that shell does not:

1. **State snapshots after every node.** `get_state(config)` returns the current
   state plus `next`, the node about to run. `get_state_history(config)` iterates
   every snapshot.
2. **Time travel.** Each snapshot has an id. Resume from any of them by passing
   that snapshot's config to `stream()`. Modify one first and you branch: a new
   state is pushed and the run continues from the edit.
3. **A real human-in-the-loop.** `interrupt_before` stops the graph before the
   named node. Inspect state, edit the pending tool call, approve, or inject a
   fake result with `update_state(..., as_node="action")` so the graph believes
   the node already ran.

The annotation detail is the one that bites people. `Annotated[Sequence[BaseMessage],
operator.add]` appends. Without the annotation, a node's return **overwrites** that
key. Choose per key: messages accumulate, the current draft replaces.

A worked LangGraph shape for the research/write/critique loop, which is the
canonical non-trivial graph:

```
plan -> research_plan -> generate -> [should_continue?]
                            ^              |
                            |              +-- end
                            |              |
                     research_critique <- reflect
```

State carries `task`, `plan`, `draft`, `critique`, `content[]` (annotated to
accumulate), `revision_number`, `max_revisions`. `should_continue` compares the
two numbers. That bound is the frozen node: without it the critique loop never
exits.

**Do not port a 4-node shell graph to LangGraph because it looks more serious.**
Port it when you need the checkpointer.

---

## Part 5: Google ADK

ADK ships the workflow shapes as named agents rather than as edges you draw:
sequential, parallel and loop workflow agents, plus agent routing for fan-out and
fan-in, plus A2A for delegation across systems. If the graph shapes in
[patterns.md](patterns.md) are the whole requirement, ADK expresses them with
less code than LangGraph. If you need arbitrary conditional routing, LangGraph is
the more direct fit.

A2A is worth naming for a reason beyond features: it is the clearest evidence
that cross-team agent delegation had real enterprise history well before anyone
called it graph engineering. Prior art is a reason to use the existing thing, not
to build a fifth one.

---

## Part 6: what not to do

- **Do not hand-roll a runtime.** Nodes, edges, state, fan-out, fan-in and loops
  already exist in LangGraph and ADK. Reinventing the runtime is its own kind of
  slop.
- **Do not install a framework to run four shell commands.** Read
  `scripts/graph-run.sh` first. It is 120 lines and no dependency.
- **Do not add a second runtime "for diversity".** Add one for independence on the
  verifier, which is a specific job with a measurable payoff.
- **Do not let a bypass flag be the default.** `--yolo`,
  `--dangerously-bypass-approvals-and-sandbox` and
  `--dangerously-skip-permissions` belong on contained worker nodes in an isolated
  worktree, never on the node that touches the closed lane.
