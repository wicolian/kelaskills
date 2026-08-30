# The auto-answer ladder

Every candidate question goes down this ladder before it is allowed near a human.
Stop at the first rung that answers it. Record the rung and the exact source.

| Rung | Source | Cost | Answers questions of the form |
|---|---|---|---|
| 1 | The repo as it stands | Seconds | "What is the convention here?" |
| 2 | Version control history | Seconds to a minute | "Was this decided or tried before?" |
| 3 | Prior lens output: `-why` findings, `-obsidian` vault | Seconds | "Did we already settle this?" |
| 4 | A parallel fact-finding worker | Minutes, non-blocking | "What is true outside this repo?" |

Only what survives all four is a real question.

---

## Rung 1: the repo

The question is usually "what does this codebase already do", and the codebase
answers it. Consistency is a legitimate answer and it needs no human.

```bash
# The convention, by frequency. The winner is the answer.
rg -n 'createClient\(' --type ts -g '!**/node_modules/**' | wc -l

# Does the thing already exist under another name?
rg -in 'retry|backoff|exponential' --type ts -l

# What do the tests assert? Tests are the spec nobody wrote down.
rg -n 'describe\(|it\(' src/auth/__tests__ | head -40

# Config and types pin down more than prose does.
fd -e json -e toml -e yaml . --max-depth 2
rg -n 'interface .*Options|type .*Config' --type ts

# Written conventions, if any.
fd -i 'readme|contributing|architecture|adr|decisions' -t f
```

Read order when they disagree: types and tests beat config, config beats code
comments, code comments beat the README. The README is the most likely to be stale.

## Rung 2: version control

The best source for "why is it like this" and "did somebody already try the thing I
am about to propose".

```bash
# Has this file's shape been argued about?
git log --oneline -20 -- src/db/schema.ts

# Who last changed this line, and in what commit?
git blame -L 40,60 src/db/schema.ts

# The pickaxe. When did this string enter or leave the codebase?
git log -S 'email NOT NULL' --oneline --all

# The regex pickaxe, for a pattern rather than a literal.
git log -G 'retry\w*\(' --oneline --all

# Reverts are the loudest signal in a repo. Somebody tried it and it failed.
git log --oneline --all --grep='revert' -i | head -20

# The full message on a suspicious commit. Rationale often lives only here.
git show --stat --no-patch 9f21c0a

# Merge commits carry the pull request number on most hosts.
git log --oneline --merges -20
gh pr view 482 --comments        # if gh is available and the remote is GitHub
```

A revert answers a question **negatively and definitively**. "Should we use X?" is
settled when `git log -S` shows X went in and came back out three weeks later. Cite
the sha, and cite the revert.

## Rung 3: prior lens output

A decision recorded last month is not a question this month.

- If `-why` ran, its findings are in this run's context already. Read them before
  drafting a single question. Archaeology exists so the next lens does not repeat
  the dig.
- If an `-obsidian` vault exists, search it. Prior runs wrote decisions there
  precisely so that this run starts where they ended.

```bash
# Whatever the vault path is for this setup.
rg -il 'rate limit|throttle' "$OBSIDIAN_VAULT"/decisions/
rg -n '^ANSWERED|^ASSUMED' "$OBSIDIAN_VAULT" -g '*.md' | head -40
```

Look for open `ASSUMPTION:<slug>` markers too. An assumption a previous run left
behind is a question that is already half asked.

```bash
rg -n 'ASSUMPTION:' . -g '!**/node_modules/**'
```

## Rung 4: a parallel fact-finding worker

Only for facts that live outside the repo: a library's actual behaviour, a service
limit, an API's real response shape, what a dependency did in its last major
version.

**Dispatch it and do not block on it.** A running fact-finder is an unsettled
prerequisite, so only the questions downstream of it move to a later round. Ask the
rest of the frontier now.

A good brief has four parts:

```
QUESTION   The exact fact needed, phrased so the answer is checkable.
           Not "research rate limiting". Instead: "What is the per-token
           requests-per-minute limit on the endpoint we call in
           src/api/client.ts, and where is that documented?"

SOURCES    Where to look, in preference order. Primary sources only:
           official docs, the package's own source in node_modules, the
           changelog. Not a blog post, not a forum answer.

RETURN     The shape of the answer. "One number, plus the URL or file path
           that states it. If the docs disagree with the installed version,
           report both and say which you trust."

STOP       The budget. "If you cannot find a primary source in ten minutes,
           report NO EVIDENCE with the list of places you looked."
```

That last line is not optional. Without it, a worker that finds nothing will
produce a plausible guess instead of an absence, which is the worst possible output
because it looks like an answer.

---

## No evidence, or searched wrong

This is the failure mode that matters most. A wrong "no evidence" turns a settled
decision into a human interruption, or worse, into a confident assumption that
contradicts something the repo already decided.

**Treat "no evidence" as a claim you have to earn, not a default.**

Before you may write NO EVIDENCE, all of these must be true:

| Check | How |
|---|---|
| You searched more than one spelling | camelCase, snake_case, kebab-case, and the abbreviation. `retryCount`, `retry_count`, `retries`, `maxAttempts` |
| You searched more than one word | The thing and its synonyms. `throttle`, `rate limit`, `backoff`, `debounce` |
| You searched the whole history, not the tip | `git log -S ... --all`, not just the working tree. A deleted implementation is invisible to `rg` |
| You searched outside the source directory | Tests, fixtures, scripts, CI config, generated files, docs |
| Your tooling did not silently exclude it | `rg` honours `.gitignore` by default. Generated clients, lockfiles and build output are often exactly where the answer lives |
| A positive control passed | Search for something you know is there. If that returns nothing, your search is broken, not the repo |

The positive control is the one people skip and it is the cheapest.

```bash
# Broken tooling looks exactly like an empty repo. Prove the tool works.
rg -c 'import' src/ | head -3          # should obviously hit
rg --no-ignore --hidden -n 'retryCount' .   # then widen deliberately
git log --oneline --all | wc -l        # non-zero means history is present
```

### Say which one it is

| Write this | When |
|---|---|
| `NO EVIDENCE` | Every check above passed and the repo genuinely does not decide this. It is a real question. |
| `SEARCH INCONCLUSIVE` | A check failed, or the search was shallow, or the history is shallow (`git log` shows a truncated clone). Say so, say what you would need, and treat the question as still open rather than as a real question for the human. |
| `AMBIGUOUS` | You found conflicting evidence. Two conventions, or a doc that contradicts the code. This is a **good** question for a human, and you now have a much better one: not "which convention?" but "the code does A, the docs say B, which is stale?" |

A shallow clone is a common and silent cause of a false NO EVIDENCE:

```bash
git rev-parse --is-shallow-repository    # true means rung 2 is not trustworthy
git log --oneline | wc -l                # a suspiciously round number is a warning
```

If the clone is shallow, say the history was not available. Do not report an
absence you could not have observed.
