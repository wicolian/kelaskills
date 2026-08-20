---
name: agent-fleet
description: Run a fleet of visible Claude Code, Codex, Cursor, Hermes Agent, Pi, or T3 Code provider workers in herdr panes. Use when a job is bigger than one context, such as many independent tasks, an overnight programme, or a wave of parallel edits, and each worker should stay visible instead of running as a headless subagent. Cover spawning, addressing, watching, collecting reports, runtime selection, and file ownership. Require HERDR_ENV=1.
---

# Agent fleet

Spawn real interactive coding-agent sessions in herdr panes, one per task. Watch
them work and read the reports they write to disk.

Check `HERDR_ENV=1` first. If it is not set, stop because the scripts are not
running inside herdr.

## Keep workers interactive

Headless modes leave a pane blank until a run ends. A human cannot distinguish a
working agent from a hung process. Interactive mode shows the runtime's actual
TUI, tool calls, progress, and status.

Still require a machine-readable result. Tell every worker to write its report
to a file as its final action.

## Choose a runtime

`scripts/runtime-command.sh` provides launch adapters for these names:

| Runtime | Interactive command |
|---|---|
| `claude-code` | `claude --dangerously-skip-permissions --model MODEL` |
| `codex` | `codex --dangerously-bypass-approvals-and-sandbox --model MODEL` |
| `cursor` | `cursor-agent --yolo --model MODEL`, with `agent` as a fallback |
| `hermes-agent` | `hermes --yolo --model MODEL` |
| `pi` | `pi --model MODEL` |
| `t3-code` | The provider selected by `T3_PROVIDER_RUNTIME` |

T3 Code is a GUI over provider CLIs, not a separate terminal agent. Set
`T3_PROVIDER_RUNTIME=codex`, `claude-code`, or `cursor`; the worker then launches
the same provider that T3 Code would drive. Set `AGENT_FLEET_COMMAND` to an exact
interactive command when using a custom provider or nonstandard binary.

Pass `default` as the model to keep the runtime's configured default. Review
every runtime's bypass mode before running unattended work. Cursor still honors
explicit deny rules when `--yolo` is active.

## Use the scripts

Call the scripts in place or copy the full `scripts/` directory so the runtime
adapter stays beside the launchers.

```text
scripts/spawn-agent.sh NAME RUNTIME MODEL PROMPT_FILE [TAB] [CWD]
scripts/fleet-status.sh
scripts/fleet-watch.sh [SECONDS]
scripts/reuse-pane.sh PANE NAME RUNTIME MODEL PROMPT_FILE [CWD]
```

Use `reuse-pane.sh` to keep a fleet at full width without growing the pane count.
When a worker finishes, give its pane the next task instead of splitting again.

## Spawn workers

```bash
FLEET=/path/to/your/programme
export AGENT_FLEET_ROOT="$FLEET"

scripts/spawn-agent.sh API-021 codex gpt-5.6 "$FLEET/prompts/API-021.md" backend /repo
scripts/spawn-agent.sh UI-022 cursor default "$FLEET/prompts/UI-022.md" frontend /repo
scripts/spawn-agent.sh QA-023 pi default "$FLEET/prompts/QA-023.md" qa /repo
```

Fill a tab by alternating right and down. Keep four to six panes per tab so they
remain readable. Name the tab after the wave or theme, not `workers-3`.

Set `AGENT_STARTUP_WAIT` if a runtime needs more than eight seconds to reach its
prompt. If it prints a stable readiness marker, set `AGENT_READY_PATTERN` and
optionally `AGENT_READY_TIMEOUT`.

## Keep the prompt in a file

A herdr `send-text` containing newlines submits at the first newline. Send one
short line that points to the real prompt on disk:

> You are worker NAME. Read PROMPT and do exactly what it says, in full, to the
> end. When finished, save your report to REPORTS/NAME.md and touch
> REPORTS/NAME.done.

Put the task, rules, acceptance criteria, and verification commands in the prompt
file before spawning anything.

## Watch and collect

```bash
scripts/fleet-status.sh
herdr pane list
herdr pane read wG:pE --source visible --lines 40
herdr wait agent-status wG:pE --status done --timeout 600000
```

Treat `.done` beside a report as the reliable completion signal. Use herdr's
`agent_status` as a second opinion. Read the report file for the result and the
pane transcript only to confirm the worker is alive.

## Nudge a stuck worker

```bash
herdr pane send-text wG:pE "Status? If blocked, report the one blocker and stop."
herdr pane send-keys wG:pE Enter
```

If a pane remains unchanged after submission, resend once. The launcher compares
visible pane output and performs that single retry automatically.

## Write every prompt in this order

1. Require the shared brief.
2. Name the task and its source file.
3. Assign absolute paths the worker owns.
4. Name paths owned by other workers.
5. State concrete acceptance criteria.
6. Give exact verification commands.
7. Forbid commits, `git add`, and ledger edits.
8. Fix the report shape.

## Keep parallel edits safe

- Give each file to one task. If a worker needs a file it does not own, require
  it to stop and report instead of editing.
- Keep commits with the orchestrator. Commit serially with explicit pathspecs.
  Never use `git add -A` or `git stash` while a fleet runs.
- Keep repository-wide gates out of workers. Give each worker a narrow command
  and cap worker concurrency where the test runner supports it.
- Cap browser sessions across the entire fleet.
- Put cross-worker discoveries in `FINDINGS.md` and require later prompts to read
  it.

## Route models by capability

Use the strongest available reasoning model for the hardest dependency or design
cluster. Use a balanced coding model for implementation, and a fast inexpensive
model for search, mechanical edits, and verification. Model names vary by
runtime, so keep them in launch configuration instead of skill instructions.

Judge the output against acceptance criteria. Rerun weak results on a stronger
model instead of accepting them because the first run was cheaper.

## Control fleet cost

Each worker is a complete agent session with its own context and provider usage.
Spawn only the width the wave needs. Concurrent test runners and browser sessions
usually become the bottleneck before pane count does.

For work longer than one quota window, load `blackout-proof` before starting. It
covers the external watchdog, backoff, and disk-backed handoff needed to survive
the orchestrator process ending.
