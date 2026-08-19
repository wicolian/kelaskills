---
name: overnight-dev
description: Use when one command should take a web app from "probably fine" to "verifiably usable" unattended - QA it as a daily power user against a local server, fix what breaks, ship one deploy, verify the deployed site, cross-check error and product telemetry, and leave a morning report. Triggers on "run overnight", "make dev clean by morning", "fix it while I sleep", "QA this properly", "is this actually usable", "find the z-index bugs".
---

# Overnight dev

An unattended QA-and-fix loop. Fired at night, read in the morning.

Two helper scripts live beside this file and are accelerators, not prerequisites:
`overlay-audit.mjs` (mechanical overlay checks), `verify-flow.mjs` (a scripted
flow against a deployed host), `watch-build.sh` (poll a CI/CD job to a terminal
state).

## The contract

**The person who started this is asleep and cannot unblock you.** So: never wait
on a question, never leave the tree dirty, never leave the environment worse than
you found it. When genuinely blocked, write it down and move to the next thing.

**Deliverable:** `MORNING.md` and `qa-findings.md` at the repo root, and the dev
environment deployed green. Both files are gitignored - they are evidence, not
repo state.

**Happy-path smoke tests pass on software nobody can actually use.** The job is to
find what a person hits on day 200, not day 1.

## Configure this first

This skill is host-agnostic. Fill this in for your project before running, and
keep it out of version control if any of it is sensitive:

```bash
QA_BASE_URL=http://localhost:3000     # what you QA against
QA_DEPLOY_URL=                        # what you verify after shipping
QA_ORACLE_URL=                        # a deployed build of main, read-only
QA_EMAIL= QA_PASSWORD=                # from the environment, never a file
AMPLIFY_APP_ID=                       # or whatever your deploy target needs
```

Credentials come from the environment only. Never into a file, a log, a commit,
or this skill.

## Guardrails - these are what make unattended running safe

- **No PRs. Never merge to `main`. Never force-push.** Ship to the integration
  branch only.
- **Name the one deploy target you may write to, by id, and check the id every
  time.** Production, UAT and preprod usually live in the same cloud account. One
  wrong `--app-id` hits paying customers. Everything else is read-only.
- **Never `git stash`.** Unattended plus stash is how a night's work disappears
  with no trace. Commit or discard.
- Anything created in a shared environment gets a `qa-` prefix and is cleaned up.
- **All run output stays local.** Ledgers, reports, JSON and screenshots are
  gitignored. Never commit evidence.

## Test the thing you think you are testing

If the app serves an old UI by default and the new one is behind a flag, **every
check must force the flag** or the whole run is worthless.

Force it two ways, because one is not enough:

- the query param on every navigation, and
- the flag written to `localStorage` in an init script, so it survives client-side
  navigation

Then **assert it stuck** before trusting anything - query for a marker only the
new UI renders. If the marker is absent, stop and fix the harness. Do not QA on.

## The oracle: compare against main

**A deployed build of `main`, with the same credentials, is the reference for
"how this is supposed to work".** Nothing else resolves the only question that
matters at 3am.

| Oracle (main) | Your build | Verdict |
|---|---|---|
| works | broken | **regression - fix it, this is the job** |
| broken | broken | pre-existing; log it, do not spend the night on it |
| broken | works | you fixed it - make sure the change is recorded |
| n/a | new surface | judge against your design system and your docs |

**Read-only. Never deploy to it, never change its data.**

And check your intentional-behaviour-change ledger before calling any difference a
regression. On a long redesign branch, corrective changes get misread as
regressions repeatedly, and each misreading costs hours.

## Canonical fixtures

Pick 5-8 real URLs that cover the product's distinct surfaces, and **parameterise
the host so the same list runs locally, on dev and on the oracle**. Write them
down once, here, with what each is for.

Cover the same object reached two different ways when the product offers that -
two entry points to one feature exercise different code paths, and a bug in one is
invisible from the other.

Verify the list still loads before every run. A fixture that 404s silently turns a
whole night into a no-op.

## The bug taxonomy

Where to look. Grouped by mechanism, because the fix differs per class.

### 1. Stacking / z-index

Define a z-index ladder in one file and treat it as a contract:

```
content 800 -> chrome 820 -> fullscreen 830
-> overlay 900 -> popover 910 -> toast 1000 -> portal 1001
```

**A popover opened inside a dialog must land above the dialog.** A hardcoded
`z-50` is the classic break.

- overlay renders behind its trigger's container
- dropdown inside a modal invisible or unclickable
- tooltip under a sticky header
- overlay clipped by an ancestor's `overflow: hidden` instead of portalling out

### 2. Scroll

- long menu opens but will not scroll (missing `max-height` + `overflow-y`)
- page scrolls behind an open modal (scroll-lock missing), or stays frozen after
  close (scroll-lock leaked)
- nested scroll: the inner container swallows the wheel, the outer never moves
- a virtualised list stops loading mid-scroll

### 3. Pointer / selection

- `pointer-events` leaking from a portal wrapper and eating clicks page-wide
- an option highlights but will not commit on click
- text in an input cannot be selected (`user-select: none` inherited)
- hit area smaller than the visual

### 4. Focus

- focus trap will not release on Escape
- Tab escapes a modal into the page behind
- reopening a menu drops focus to `<body>`, killing keyboard flow

### 5. Inherited visual crimes

The defaults nobody revisited.

- hardcoded `#fff` or `background: white` where a surface token belongs
- one item in a row styled unlike its siblings - the classic is the first filter in
  a filter row rendering opaque while the rest are transparent
- dark mode unconsidered: a white box on a dark surface

### 6. Staleness

- stuck shimmer: the skeleton is still mounted after the data arrived
- a spinner that never resolves
- a stale package with a known upstream bug - confirm upstream before rewriting
  app code

### 7. Memory

The power user keeps the tab open all day. A leak invisible in 30 seconds is a
crash by mid-afternoon.

- heap grows across navigations and never settles near baseline
- detached DOM retained by a listener outliving its component
- `IntersectionObserver` / `ResizeObserver` / `setInterval` never disconnected
- a chart or map instance not disposed when its widget unmounts

Sample `performance.memory.usedJSHeapSize` per route. More than ~150MB of growth
across a walk is a finding. To find the culprit, diff heap-snapshot retainers -
growth alone names the route, not the object.

## The night

**Cheap signal first, expensive builds last. Never build per fix.** A cloud build
is ~15 minutes; getting this backwards is 40 builds instead of 3.

```
0  preflight         clean tree, sync, local build passes
1  QA sweep (local)  power user vs localhost, real Chrome, flag forced
2  fix               batch everything fixable; typecheck + build green
3  ship once         merge -> integration branch -> deploy -> watch
4  verify deployed   re-walk the fixtures on the deployed host
5  telemetry         errors + product analytics cross-check
6  loop or stop
7  MORNING.md
```

### Phase 0 - preflight

```bash
git branch --show-current
git status --porcelain          # commit or discard - never stash
git fetch origin && git rev-list --count HEAD..origin/<integration-branch>
<typecheck command>
<build command>
```

If the tree is dirty with **someone else's** work in progress, stop and say so in
`MORNING.md`. Do not tidy a working tree you did not author.

Create `qa-findings.md` now and append to it **as you find things**. A crash at 3am
must not cost the night's evidence.

### Phase 1 - QA sweep, locally

Real Chrome, not the headless shell. The shell composites differently and will not
reproduce stacking or paint bugs. Cap at **3 tabs** - more starves the GPU and
muddies what you see.

```js
chromium.launch({ headless: false, channel: 'chrome' })
```

```bash
node ./overlay-audit.mjs --base "$QA_BASE_URL" \
  --routes /,/route-a,/route-b,/settings \
  --ledger qa-findings.md
```

`overlay-audit.mjs` mechanically covers classes 1-4: it opens each trigger and
asserts the overlay is **on top** (`elementFromPoint` at its centre resolves inside
it), **scrollable if it overflows**, **unclipped**, and **Escape-dismissible**,
plus a per-route heap sample for class 7.

**It is a first pass, not coverage.** On a real run it audited **6 of 36 triggers
(17%)** - the rest were hidden, or not a recognised overlay type. It prints
`audited N/M`. **If it ever audits 0, that is nothing checked, not a pass.**

The remainder needs you: walk the fixtures by hand, and work through your own
product documentation as a queue. For each doc page, read what it claims, then do
exactly that:

- flow works -> pass
- flow broken -> finding (**check the oracle first** - regression or pre-existing?)
- flow no longer exists -> doc drift, not a bug
- feature undocumented -> still QA it

### Phase 2 - fix, in priority order

1. **Blockers** - white screen, route will not render, a flow cannot complete
2. **Stacking / scroll / pointer / focus** - usually a token or one `overflow` line
3. **Memory** - a leak is a crash for the all-day user
4. **Visual** - load your design-system skill and fix to the system, never by eye
5. **Doc drift** - record it; never invent UI to match stale docs

Unattended rules:

- **Root cause, not symptom.** A symptom patched at 3am is a bug inherited at 9am.
- **A behaviour change gets a ledger row in the same commit.**
- **Three failed attempts on one bug = stop.** Log it open, with what you tried,
  and move on. Do not burn the night on one defect.
- Commit per logical fix, with a clear message. The log gets read.

### Phase 3 - ship the batch, once

```bash
git checkout <integration-branch> && git pull --ff-only
git merge <work-branch> && git push
git checkout <work-branch>
AMPLIFY_APP_ID=<dev-app-id> ./watch-build.sh
```

Build-failure playbook - the entries that cost the most time to diagnose:

| Symptom | Cause | Fix |
|---|---|---|
| **`[vite:esbuild-transpile] The service was stopped`** | esbuild was killed at the memory ceiling. **This is the real signature - grepping the log for `JavaScript heap out of memory` finds nothing.** | Trim what got heavier, or raise `NODE_OPTIONS=--max-old-space-size=...`. If your provider sets env vars as a whole map, read the current map first or you erase the rest. |
| `Cannot find module` on an internal package path | build order: the library must build before its consumer | preserve build order |
| codegen or missing generated type | the committed schema drifted from the deployed one | regenerate and commit |
| a header or CSP change did not apply | someone edited the provider's console instead of the repo | edit the config file in the repo - it overrides the console on deploy |

**Fix on the work branch, never directly on the integration branch.** A hotfix
landed only downstream is invisible to the branch you are actually building.

### Phase 4 - verify what actually deployed

Re-walk every fixture against the deployed host, flag forced, in real Chrome, in
both themes if you have them. **A green build proves nothing about usability.**

### Phase 5 - telemetry cross-check

This is what separates "a script clicked things" from "we know what users hit".

Query your error tracker for issues first seen in the last 12 hours on the dev
environment:

- **A new issue since your deploy means you caused it.** Highest priority: fix or
  revert before morning.
- An issue matching a finding -> confirmed, and now you know the volume.
- An issue with no finding -> a coverage gap. Note the route.
- A finding with no issue -> still real. Silent UI defects never throw.

Know your pre-existing noise by name, and write it down, so you do not re-triage
the same schema-drift error every night. Dev-server hot-reload noise is filtered
locally, but **a deployed host serves a real build, so anything it reports is
real.**

Then product analytics for whether it hurt anyone: session replays on the affected
route, error tracking, web vitals. An unused surface is a *deprioritise* signal,
not a *skip* one.

Add a `confirmed:` line to each ledger entry - an issue id, a replay URL, or
`no telemetry (silent UI defect)`.

### Phase 6 - loop or stop

Another batch if findings remain and time allows. Each pass should shorten the
list.

**Stop when** no fixable findings remain without a decision, a bug survived three
attempts, a fix needs backend or infra you cannot deploy, or the environment is
green and the ledger is clean.

**Always end with the environment deployed and green.** Mid-build or broken is the
one outcome worse than doing nothing.

### Phase 7 - MORNING.md

Written last, repo root, read on a phone before coffee. Verdict in the first three
lines.

```markdown
# Morning report - <date>

**<deploy host>: GREEN | BROKEN | NOT SHIPPED**
Build <id> - <status>. <n> fixes across <n> batches.
<one sentence: is it usable today, yes or no>

## Fixed and shipped
- <symptom> - <fixture/route> - `<sha>`   [vs oracle: regression | new]

## Found, not fixed
- <symptom> - <route> - why: <needs decision | backend | 3 attempts failed>

## Needs you
- <question, and what you would do with each answer>

## Telemetry
- New error-tracker issues since deploy: <n> <ids>   (0 is the number you want)
- Pre-existing / not mine: <ids>
- Memory: <heap trail, any leak>

## Coverage
Fixtures <n>/<n>. Routes <n>. Doc pages <n>/<n>. Audited overlays <n>/<m>.
Not reached: <list>
```

Ledger entry shape (`qa-findings.md`, appended live):

```
## <route> - <symptom>
class:     stacking | scroll | pointer | focus | visual | staleness | memory
repro:     <exact clicks>
expected:  <what a power user expects>
actual:    <what happens>
oracle:    works | broken | n/a        <- the regression verdict
evidence:  <screenshot | console line | computed style>
confirmed: <issue id | replay url | no telemetry>
fix:       <sha> | open | needs design
```

## Red flags

- Reporting a clean run without ever opening a menu, dialog or dropdown.
- Testing without forcing the flag - that is the old UI and says nothing.
- Running a cloud build to test a one-line CSS fix.
- Calling something a regression without checking the oracle and the ledger.
- "0 findings" when 0 things were actually audited.
- Fixing a visual finding by eye instead of against the design system.
- Touching any deploy target other than the one dev app id.
- Committing the ledger, the report, or screenshots.

**Report honestly.** A skipped surface is skipped, not passed. A fix you could not
verify on the deployed build is unverified. The only value of a report written
while someone slept is that it is true.
