---
name: cc-fleet
description: Run a fleet of visible Claude Code workers in herdr panes. Use when a job is bigger than one context - many independent tasks, an overnight programme, a wave of parallel edits - and you want each worker in its own pane you can watch, not a headless subagent. Covers spawning, addressing, watching, collecting reports, and the file-ownership discipline that keeps parallel edits safe. Requires HERDR_ENV=1.
---

# cc-fleet

Spawn real, **interactive** `claude` sessions in herdr panes, one per task. You watch them
work. They write their reports to files you read.

Check `HERDR_ENV=1` first. If it is not set, you are not inside herdr. Stop.

## Why interactive, not `claude -p`

`claude -p` is headless. The pane stays blank until the run ends, so a human watching the
screen sees nothing and cannot tell a working agent from a hung one. Interactive mode shows
the real TUI: the tool calls, the thinking line, the token count.

You still get a machine-readable result, because you tell the worker to **write its report
to a file** as its last act.

## The three scripts

Copy them out of `scripts/` next to this file, or call them in place.

```
scripts/spawn-cc.sh    NAME MODEL PROMPT_FILE [TAB] [CWD]   spawn one worker
scripts/fleet-status.sh                                     one line per worker
scripts/fleet-watch.sh [SECONDS]                            block until all are done
scripts/cc-reuse.sh    PANE NAME MODEL PROMPT_FILE [CWD]     put a NEW task in a finished pane
```

`cc-reuse.sh` is how you keep a fleet at full width without growing the pane count. When a
worker finishes, hand its pane the next task instead of splitting a new one.

`spawn-cc.sh` does the whole dance: create the tab if it is new, split a pane, `cd` to the
right folder, start `claude --dangerously-skip-permissions --model MODEL`, wait for the TUI
to be ready, type one short line, press Enter, and retry the typing once if it did not land.

## Spawning

```bash
FLEET=/path/to/your/programme          # holds prompts/ and artifacts/reports/
export CC_FLEET_ROOT="$FLEET"

scripts/spawn-cc.sh CD-021 opus  "$FLEET/prompts/CD-021.md" registry /repo/frontend
scripts/spawn-cc.sh CD-022 opus  "$FLEET/prompts/CD-022.md" registry /repo/frontend
scripts/spawn-cc.sh lint   sonnet "$FLEET/prompts/lint.md"  chores   /repo
```

Panes fill a tab alternating right / down. Four to six per tab stays readable; past that,
start a new tab. The tab label is how the human finds the work, so name it after the wave or
the theme, not `workers-3`.

## The one-line message, and why the prompt lives in a file

A herdr `send-text` of a multi-line string submits at the first newline, so half your prompt
would run as its own turn. The script therefore sends exactly one line that points at the
real prompt on disk:

> You are worker NAME. Read PROMPT and do exactly what it says, in full, to the end. Do not
> stop early and do not ask me anything. When you are completely finished, use the Write tool
> to save your full final report to REPORTS/NAME.md and then run: touch REPORTS/NAME.done

Everything else - the task, the rules, the acceptance, the verify commands - belongs in the
prompt file. Write those files before you spawn anything.

## Watching and collecting

```bash
scripts/fleet-status.sh                       # NAME  RUNNING|DONE  bytes
herdr pane list                               # agent_status per pane: working / idle / done
herdr pane read wG:pE --source visible --lines 40
herdr wait agent-status wG:pE --status done --timeout 600000
```

`.done` next to the report is the reliable finish signal. `agent_status` is herdr's own
detection and is a good second opinion, but a worker that ends its turn to think reads as
`idle` for a moment.

Read the **report file**, never the pane transcript, for the result. The transcript is for
seeing that it is alive.

## Nudging a stuck worker

It is a real session, so you can just talk to it:

```bash
herdr pane send-text wG:pE "Status? If you are blocked, say the one blocker and stop."
herdr pane send-keys  wG:pE Enter
```

If the pane shows an empty prompt box and no `esc to interrupt`, the first message never
landed. Re-send it. That is the single most common failure and the script already retries
once.

## Prompt-file template

Every prompt file should carry these, in this order:

1. **Read the shared brief first**, and say it is not optional. One file with the rules for
   every worker beats repeating them nine times and drifting.
2. **The task**, by ID, with the file that defines it.
3. **What you own**, as absolute paths. Then: *nothing else, N other agents are editing this
   repo right now.*
4. **What other workers own**, named, so a worker knows what red test is not its problem.
5. **Acceptance**, concrete.
6. **Verify**, as exact commands to run and quote.
7. **Do not commit, do not `git add`, do not edit the ledger.**
8. **The report shape**, fixed, so you can diff nine reports without reading nine essays.

## The rules that make parallelism safe

- **One task owns one file.** Write the ownership map down before you spawn. Two workers on
  one file will silently lose each other's edits. If a worker needs a file it does not own,
  it stops and reports; it does not edit.
- **Workers never commit.** The git index is shared across every pane in the checkout. You,
  the orchestrator, commit - serially, with an explicit pathspec, once per wave. Never
  `git add -A`. Never `git stash` while a fleet is running.
- **Workers never run repo-wide gates.** Six concurrent full test suites will thrash the
  machine and each one will blame the others' half-written files. Give each worker the
  narrowest path, and `--maxWorkers=2`.
- **Cap browsers.** One or two Playwright sessions across the whole fleet, scheduled by you.
- **A findings file beats a broadcast.** When one worker discovers the plan is wrong, it
  reports; you append to a `FINDINGS.md` that every later prompt tells workers to read.
  Later workers get the correction without you rewriting nine prompts.

## Model routing

Fable for the one hardest reasoning cluster, and only one instance - it is expensive. Opus
for anything with judgement in it, which is most implementation. Sonnet for search, bulk
mechanical edits, and verification. Judge the output, not the price: if a cheap model misses
the bar, re-run it on a better one rather than accepting the result.

## Cost of a fleet

Each worker is a full session with its own context. Ten workers on Opus is roughly ten times
one worker. Spawn what the wave actually needs, not the maximum the machine will hold. On a
24 GB machine, ten to fifteen concurrent workers plus three dev servers sits near 9 GB and
load 2.5 - comfortable. The limit you hit first is usually concurrent test runners, not RAM.

## Running a fleet longer than one quota window

A fleet dies when the session driving it dies, and a usage limit kills that
session. If the run has to outlive you going to bed, load **blackout-proof**
before you start: it covers the watchdog that restarts an orchestrator, the
backoff that gets through the wall, and the handoff that survives the blackout.
