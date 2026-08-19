# The handoff: RESUME.md, the ledger, the report

Three files. Between them, anyone - you in the morning, or a fresh agent at
03:07 - can pick the run up without reading a transcript.

## 1. The ledger: task state on disk

Context dies with the session. State has to live in a file.

One row per task, and a state that a script can count:

```
T-021  DONE     first batch of generated entries
T-022  DONE     second batch of generated entries
T-031  RUNNING  wave 3, pane wG:pE, started 01:12
T-032  TODO     depends on T-031
T-131  HELD     two review defects open, needs a red test first
T-140  BLOCKED  needs a human decision: which default to pick
```

Rules that make it survive a blackout:

- **The orchestrator writes the ledger, but the report never trusts it.** The
  report counts `.done` files. The ledger is intent; the markers are fact.
- **`RUNNING` is a lie after a crash.** A resume must treat every `RUNNING` row
  with no live pane and no `.done` marker as `TODO` again - which means every
  task has to be safe to run twice.
- **`HELD` and `BLOCKED` are different.** Held means finished but deliberately
  not shipped. Blocked means it cannot proceed. Only one of them is your problem
  at 8am.

## 2. RESUME.md: the handoff

Written before you go dark, updated by the orchestrator as it goes. It answers
one question: *what do I do first?*

```markdown
# Resume

## First thing to do
<one sentence. Not a summary - an instruction.>

## State
99 of 114 done. 15 running. Ledger: artifacts/ledger.tsv

## The three files that govern this run
- BRIEF.md      the rules every worker reads first
- FINDINGS.md   what the run learned that changes the plan
- LIMITS.md     which quota wall we are near, and its real reset

## In flight when the lights went out
- T-131 in pane wG:pE, closing two review defects
- T-140 waiting on a human decision (see Held)

## Held - finished, deliberately not shipped
- backend commit: 7 defects found in review, 2 still open. Do not commit
  until T-131 passes clean.
- nothing published. The package builds; publishing is a human decision.

## Traps
- <the thing that will waste an hour if nobody says it>
- <the second one>

## Snapshots
artifacts/snapshots/*.patch - every uncommitted tree, per branch, timestamped
```

**"First thing to do" is the whole point.** A handoff that opens with a status
summary makes the reader reconstruct the decision. Give them the decision.

## 3. The report: derived, never transcribed

Generated from the artifacts, on a loop, by a script that asks nobody.

```bash
#!/usr/bin/env bash
# make-report.sh - regenerate the status page from what is on disk
DONE=$(ls artifacts/reports/*.done 2>/dev/null | wc -l | tr -d ' ')
TOTAL=$(ls prompts/*.md 2>/dev/null | wc -l | tr -d ' ')
{
  echo "<h1>$DONE / $TOTAL</h1>"
  echo "<p>generated $(date '+%Y-%m-%d %H:%M:%S') - regenerates every 3 min</p>"
  for r in artifacts/reports/*.md; do
    n=$(basename "$r" .md)
    [ -f "artifacts/reports/$n.done" ] && s=done || s=running
    echo "<h2>$n <em>$s</em></h2><pre>$(head -40 "$r")</pre>"
  done
} > MORNING-REPORT.html
```

Two properties that matter more than how it looks:

- **It works with nothing driving it.** Kill the orchestrator, wait, reload. If
  the number moved, the report is honest.
- **It marks what it discovered on its own**, so a human can see which results
  arrived while the lights were off. A count that jumps from 65 to 83 with no
  explanation reads as a bug; tagged `[auto]`, it reads as the system working.

## What goes in the morning summary, in order

1. **The verdict**, in one line. Usable or not.
2. **Held**, with the reason for each. This is what you are actually needed for.
3. **Blackouts**: how many, how long, how many restarts. From the watchdog log -
   it is the only record of the night's real shape.
4. **Findings** that change the plan.
5. Everything else.

Put the held list second, not last. It is the only part that cannot proceed
without the person reading it.
