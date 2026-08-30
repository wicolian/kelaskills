# The failure taxonomy

Nine categories. For each one: how to detect it in a transcript, what a false
positive looks like, and the config change that usually fixes it.

Read this before you write a rule. A count from `scripts/retro-scan.sh` is a
candidate. This file is how you turn a candidate into a finding.

**Order matters.** These are sorted by what a mistake costs to undo, not by how
often it happens. Fix from the top.

---

## 1. Destructive or wrong-target actions

The agent deleted, reset, killed or overwrote something it should not have.
Rare. The most expensive thing in the file when it lands.

| | |
|---|---|
| **Where it lives** | Assistant tool calls. Claude Code: `message.content[]` blocks with `type: tool_use`, `name: Bash`, `input.command`. Codex: `payload.type == "function_call"`, `name == "shell"`, `arguments` is a JSON string holding `command` as an array. Cursor: `message.content[]` with `type: tool_use`. |
| **Patterns** | `^rm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+` / `^git\s+reset\s+--hard` / `^git\s+checkout\s+(--\s+)?\.\s*$` / `^git\s+clean\s+-[a-zA-Z]*[fd]` / `^git\s+push\b.*(--force|\s-f\b)` / `^git\s+branch\s+-D` / `^(pkill\|killall)\b` / `^kill\s+-9` / `DROP\s+TABLE` / `TRUNCATE\s+TABLE` |
| **Match per segment** | Split the command block on newline, `;`, `&&`, `\|\|`, `\|` and match each segment at its head. Matching the whole block is how a document that mentions `pkill` gets counted as a process kill. |

**False positives, and there are a lot of them.**

- `rm -rf` inside `/tmp`, `/var/folders` or a scratch directory the agent
  created itself. This is housekeeping. On one machine it was the single
  loudest count in the whole scan and almost none of it was a problem.
- `rm -f some.DS_Store`, `rm -f node_modules`.
- Any destructive command you explicitly asked for. `git reset --hard` when you
  said "throw that away" is the agent doing its job.
- A destructive string quoted inside a heredoc the agent is writing into a file.
- `git stash` is only destructive when a parallel fleet is running. Alone, it is
  normal.

**The one that is never a false positive: killing the process the session
depends on.** A `pkill -f node` that takes out the dev server, or the very
harness the agent is running inside. Search the next few records for the agent
noticing it lost its own environment.

**Config change**

| Situation | Change |
|---|---|
| It happens more than once | A hook or a permission deny rule. A prompt line will not hold here, because the agent is not disobeying, it is not thinking about it. |
| It targets a specific process | Name the process in a deny rule, not in prose. |
| It is your own scratch cleanup | Nothing. Record the reason and move on. |

This is the category where a **guardrail beats a rule**. Everything else in this
file can be an instruction. This one gets mechanically blocked.

---

## 2. Tool misuse

The right intent, the wrong instrument. A package-manager subcommand that
silently does something else. A flag that means the opposite of what was
assumed. The same tool invoked five times, failing the same way each time.

| | |
|---|---|
| **Where it lives** | Tool results. Claude Code puts `toolUseResult` on the user record following a tool call, and an error usually carries `is_error: true` or an `Error:` prefix in the content. Codex: `payload.type == "function_call_output"`, and `output` holds a JSON blob with `metadata.exit_code`. |
| **Signals** | Bash error rate above roughly 15% of calls. Three or more consecutive failed calls to the same tool with near-identical input. A tool call immediately followed by the same call with one character changed. |
| **Patterns** | `command not found`, `no such file or directory`, `unknown (option\|command\|flag)`, `did you mean` |

**False positives.** Probing is not misuse. An agent that runs `which pnpm`,
gets a failure, and falls back to `npm` did the right thing. Count a failure
only when nothing changed between attempts, or when the failure was silent.

The dangerous version of this category is the one that produces **no error at
all**: a command that succeeds while doing the wrong thing. You will not find
that with a grep. You find it by reading a session that ended badly and working
backwards.

**Config change.** Name the correct command for the tool in the project
instructions, positively. "Install with `<the right command>`" beats a list of
things not to run.

---

## 3. Overbuild

Far more code than the request implied. An abstraction layer nobody asked for. A
config system for a value that appears once.

| | |
|---|---|
| **Where it lives** | The diff, not the prose. Count files created and lines written per human request. Claude Code: `tool_use` blocks with `name` in `Write`, `Edit`, `MultiEdit`. |
| **Signal** | A single-sentence request that produced more than about three new files. A "small fix" that added a new directory. |
| **Patterns** | Weak. There is no keyword for this. `for future`, `extensib`, `in case we need`, `flexible` in assistant text are hints, not proof. |

**This category cannot be counted reliably by grep, and pretending otherwise is
the main way an agent audit lies to you.** It needs a model that reads the
request beside the diff and forms a view. Give it to your strongest model, or
report the category as not covered.

**False positives.** You asked for a scaffold and got a scaffold. Volume alone
proves nothing. The test is whether the extra thing serves the request.

**Config change.** One line in the global instructions setting the default
scope. Something like: build the smallest thing that satisfies the request, and
name any extra you think is needed rather than adding it.

---

## 4. Stopping early

The agent reported done with work outstanding, or handed back a to-do list
instead of a result.

| | |
|---|---|
| **Where it lives** | The last assistant message of a session, and the first human message of the next one. |
| **Patterns (assistant)** | `remaining work`, `next steps`, `you (may\|might\|should) want to`, `left for`, `flagged for`, `needs further investigation`, `I did not (get to\|complete)`, `TODO` in a completion summary |
| **Patterns (human, the confirming half)** | `finish it`, `you did ?n.?t (finish\|do)`, `what about the`, `carry on`, `keep going` |

The strong detection is the pair: a session that ends with a summary containing
"next steps", followed by a human message that asks for the next step. One
without the other is weak evidence.

**False positives.** A genuine blocker named in one sentence is not stopping
early. That is the correct behaviour. The failure is the vague version:
"this needs more investigation" with no specific blocker.

**Config change.** A working-agreement line. Five things asked means five things
delivered, and a blocked item is named specifically in one sentence.

---

## 5. Unasked edits

Files changed outside the stated scope.

| | |
|---|---|
| **Where it lives** | Compare the set of file paths in `Write` and `Edit` tool calls against the paths named in the human request. |
| **Signal** | A path touched that appears nowhere in the request and is not an obvious dependency of it. Formatting churn across a file the change did not need. |

**False positives.** A required import update in a neighbouring file is in
scope. A lockfile change from an install is in scope. Test files for the code
just written are usually in scope.

The real tell is a **one-file fix arriving as a four-file diff**, where three
files got improvements nobody reviewed.

**Config change.** A scope line on returned work. When a task names files, only
those files change, and anything else that looks wrong gets reported rather than
fixed. If it recurs on one repo, put it in that repo's instructions, not the
global file.

---

## 6. Process failures

The work was right and the shipping was wrong. Branches left stale, CI red and
ignored, a draft pull request opened when a real one was wanted, verification
skipped at the end.

| | |
|---|---|
| **Where it lives** | Shell commands near the end of a session. |
| **Patterns** | `gh pr create` without `--fill` or with `--draft`, `git commit` with no test command anywhere in the preceding records, `git push` on a branch with no CI check afterwards, a session that ends with an uncommitted tree |
| **Cheap proxy** | Count sessions where a `Write` or `Edit` happened and no test, lint or type-check command ran before the session ended. |

**False positives.** A draft pull request you asked for. A repo with no test
suite. Exploration sessions that were never meant to ship.

**Config change.** This is the category most improved by naming the project's
actual gate command in the project instructions. An agent skips verification
far more often because it does not know the command than because it decided not
to bother.

---

## 7. Misreading intent

A different job from the one asked. Not a mistake in execution, a mistake in
understanding.

| | |
|---|---|
| **Where it lives** | The turn after the misread. It is almost always a correction. |
| **Patterns** | The correction list in `scripts/retro-scan.sh`, weighted toward `not what I asked`, `I meant`, `no, I want`, `that is not the` |
| **Best detector** | A human message early in a session that restates the original request in different words. That restatement is the receipt. |

**False positives.** You changed your mind. That is not the agent misreading
you, and it is the single largest source of noise in a correction count. Only a
session read can tell the two apart.

**Config change.** Usually none in the agent's config. The fix is more often in
how the request was written. When it recurs on one kind of task, that is the
task that needs a skill with a fixed intake, not a rule.

---

## 8. Regression

Something that worked stopped working. Rare. Expensive out of proportion to how
often it happens.

| | |
|---|---|
| **Where it lives** | Test output. A suite that passed earlier in the session and failed later. |
| **Patterns** | `was working`, `used to work`, `broke`, `regression`, `worked before`, in human messages. A test count that drops between two runs in the same session. |

**False positives.** A test that was already failing when the session started.
Capture the baseline before you blame the change.

**Rank this above anything more frequent.** One broken build costs more than
fifty verbose replies. Frequency is the wrong axis here.

**Config change.** Require the gate to run before the work is called done, and
require the baseline to be recorded at the start. A hook is better than a rule
if you have somewhere to hang it.

---

## 9. Verification skipped

Hooks bypassed, checks not run, a commit that went around the project's own
gates.

| | |
|---|---|
| **Where it lives** | Shell commands. This is the most reliably greppable category in the whole file. |
| **Patterns** | `--no-verify`, `--force`, `SKIP=`, `HUSKY=0`, `--no-gpg-sign`, `\|\| true` appended to a test command, `set +e` before a gate, `git commit` with no preceding gate command |

**False positives.** `--no-verify` on a WIP commit you asked for. `|| true` in a
cleanup line. A hook that was genuinely broken and blocking everything, which is
a real situation and the agent working around it is arguably correct. Read the
surrounding records: if the agent hit a hook failure and then bypassed it, that
is the finding. If it bypassed pre-emptively, that is a worse finding.

**Config change.** A hook or a permission rule. This category, like category 1,
does not hold as a prompt instruction, because the bypass happens exactly when
the agent is under pressure to finish. Block it mechanically.

---

## The proxy metric

Corrections per 100 human messages, split by model and by harness.

Every time you said a variant of no. `no`, `that is wrong`, `undo that`, `I did
not ask for that`, `stop`. The patterns are in `scripts/retro-scan.sh` and they
are deliberately conservative.

**Read it as a floor, not a measurement.** On one machine's real store the rate
came out under 2 per 100 across three harnesses, and a read of the sessions
showed plenty of redirections that used none of the phrases. A conservative
pattern set undercounts. A loose one is worse: a bare `stop` matched a hundred
worker dispatch prompts before it was tightened, and `I said` matched agreement
as often as complaint.

Four things will make this number lie to you:

1. **Raw counts follow usage.** The model you use most tops every count. Only
   the rate means anything.
2. **Difficulty is not held constant.** If your hardest and least-specified work
   goes to one model, it will look worst. Say so in the report instead of
   ranking models on it.
3. **Absence of data is not a clean record.** A model you never gave frontend
   work to has no frontend failures. That is not a strength.
4. **The denominator has to be real human turns.** Tool results, system
   reminders, command echoes and subagent dispatch prompts all look like user
   records. On one store the subagent turns outnumbered the human turns by more
   than twenty to one. Count them and the rate collapses to nothing.

---

## Turning a finding into a change

Each finding becomes exactly one of these. Write the target line before you
decide, because a finding you cannot write a line for is usually not actionable.

| Destination | When |
|---|---|
| Global agent instructions | It applies to every repo you work in |
| Project instructions | It is specific to one repo's commands, layout or conventions |
| A new skill | It is a whole procedure, not a rule. If the line needs three sub-steps, it is a skill. |
| A hook or permission rule | A rule will not hold. Categories 1 and 9 usually land here. |
| Nothing, with a stated reason | It was not preventable by config |

**Write one line per finding, and prompt it positively.** State the target
behaviour, not the ban. A prohibition drags the banned behaviour into context
every time the instruction is read, and the config file grows into a museum of
old complaints.

| Instead of | Write |
|---|---|
| Never run `rm -rf` outside the project | Delete only inside the working directory, and name what you are deleting first |
| Do not add abstractions I did not ask for | Build the smallest thing that satisfies the request. Name any extra you think is needed. |
| Stop reporting work as done when it is not | Five things asked means five things delivered. A blocked item gets one sentence naming the specific blocker. |
| Do not commit without running tests | Run `<the project gate command>` before you call the work done |

That last row is the pattern to copy. The useful part is not the prohibition. It
is the command name.
