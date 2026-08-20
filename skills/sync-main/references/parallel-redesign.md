# Parallel redesign (v1 / v2)

Architecture companion to the **sync-main** skill. That skill says what to run,
when, and what to do with what comes back. This file says where code goes.

Load this when the work involves deciding where a new screen should live,
dual-running old and new UI, Tailwind v3/v4 coexistence, feature-flagging a
reskin, harvesting a long-lived redesign branch, or any question shaped like
"how do I keep main's changes without losing the redesign". Also load before
adding any new screen during the migration window - the placement rule is
non-obvious and getting it wrong creates conflict debt.

## The core principle

**Merge conflicts are a symptom of two versions editing the same files. Fix the file layout, not the merge.**

A redesign branch that lives for 30+ days is not a branch, it's a fork. Every
day it survives, the cost of landing it grows superlinearly - because `main`
keeps shipping product logic into the exact files the redesign is rewriting.

The industry pattern (strangler fig) inverts this: **v2 ships to `main` from
day one, dark, behind a route split.** v1 and v2 coexist in the same commit,
in different directories, sharing one logic layer. There is nothing to merge
because there is no divergence.

The branch does not become the product. The branch becomes a **reference
implementation** you port from.

## Three layers, one rule

| Layer | Owns | v1/v2 relationship |
|---|---|---|
| **Logic** | data fetching, mutations, validation, state machines, permissions, tenancy scoping | **shared** - one copy, both consume |
| **Shell** | routes, layout, composition, navigation | **forked** - separate trees |
| **Presentation** | components, tokens, styles | **forked** - separate packages |

The rule: **a bug fix from `main` should only ever have to land in the logic
layer.** If a fix to one screen requires editing both `v1/ThatScreen.tsx` and
`v2/ThatScreen.tsx`, the logic wasn't extracted far enough. That duplicated edit
is the merge conflict, just relocated.

This is the usual cause of a reskin regression: state lived in the component, so
the reskin had to re-implement it, so it drifted. Extraction would have made that
class of bug structurally impossible.

## Extraction is the actual work

Before porting a screen, extract its logic:

```
useThatScreen()       <- queries, mutations, form state, validation, RBAC gates
  |-- v1/ThatScreen    <- old markup, consumes the hook
  `-- v2/ThatScreen    <- new markup, consumes the same hook
```

Extraction PRs are small, reviewable, and **merge into `main` immediately** -
they don't change behaviour, so they carry near-zero risk. Each one permanently
removes a future conflict surface. Do them first; they are the highest-leverage
commits in the whole migration.

Test for a clean extraction: **the hook has no JSX imports and no className
strings.** If it imports from the UI package, it isn't a logic layer.

## Directory contract

Four roles. **The role structure transfers; the paths do not.** Map them to
whatever the repo already uses rather than restructuring to match names in a
document.

| Role | Contract | Typical home |
|---|---|---|
| **shared** | hooks, services, types, permissions. Neither version owns it. | the existing shared logic layer (`hooks/`, `helpers/`, ...) |
| **legacy (v1)** | frozen. bugfixes only. no new features, no refactors. | the existing package tree |
| **redesign (v2)** | active development. New styling system, new component package. | `src/v2/**` |
| **gate** | the flag is read here and nowhere else. | one gate component, at the route boundary |

Restructuring an existing repo to match literal directory names is a large
unforced refactor. Don't.

**Placement rule for any new screen during the migration window:** build it in
`v2` only, and if it must exist in v1, ship a v1 route that redirects into the
v2 shell. Never build the same new feature twice. If it can't be v2-only, the
feature waits.

`v1` is frozen. "Frozen" means: no refactors, no token cleanup, no lint fixes,
no dependency bumps. Under staged cutover, every touch of a v1 file is wasted
work on code with a delete date. Under per-account rollout v1 persists, but
"frozen" still holds: it receives ported behaviour and bugfixes, never new
features or cosmetic churn.

## CSS coexistence

The collision is real: v1 product UI on Tailwind v3, v2 on Tailwind v4, both
emitting unprefixed utilities into the same document. Same classnames,
different semantics - v4 changed `shadow-sm`, `rounded-sm`, `outline-none`,
and the default border colour. Last stylesheet loaded wins. That is a silent,
screen-by-screen visual corruption, not a build error.

Three parties now share the document: **v1 product, v2 product, plugin
runtime.** Solve them separately:

**An embedded or third-party runtime** - shadow DOM boundary. If you already
have one, it is isolated and unaffected by the v1/v2 split. Do not entangle that
decision with the others.

**v1 vs v2** - both light DOM, so shadow DOM doesn't help. Two options:

1. **Split bundles at the route boundary** *(preferred)*. The flag lives in
   the router; ship two CSS bundles and load exactly one. Zero collision, zero
   prefix noise, authoring stays clean. Cost: switching versions is a full
   reload, and v1 and v2 can never render on the same page.

2. **Prefix v2** - `@import "tailwindcss" prefix(v2)`, so utilities become
   `v2:flex`. Ugly to author, but it's the only option if a v2 shell has to
   host a v1 modal or a v1 page has to embed a v2 panel during the transition.
   Codemod-able in both directions.

Pick (1) unless a mixed-render case actually exists. If one does, name it
explicitly - a single hybrid screen is not worth prefixing the entire design
system.

**Preflight:** v4's preflight will reset v1's styling out from under it. If both
bundles ever load together, import v4 without preflight (`theme.css` +
`utilities.css` only) and scope a hand-written reset to `[data-ui="v2"]`.

## Porting loop

Per screen, one PR each, all into `main`:

1. Extract logic into shared - no visual change, merge same day
2. Build the v2 screen against the extracted hook
3. Register it in the v2 route tree (still dark)
4. QA on the v2 flag internally
5. Move the screen's flag default to v2
6. **Retire or retain v1** - see the rollout model below. Under staged
   cutover, delete the v1 screen in the same sprint. Under per-account
   rollout, v1 stays and the extraction from step 1 is what keeps it
   maintainable.

Step 1 is the one that gets skipped, and skipping it is what makes every later
sync expensive. A screen is not migrated because its v2 copy renders; it is
migrated when a fix to it can only land in one place.

## Rollout model - decide this before porting anything

Flag granularity is **per route, not global**, under either model. A global
flag forces big-bang launch and removes per-screen rollback.

**Staged cutover.** Flip routes to v2 for everyone, delete each v1 screen in
its porting PR, delete the flag at the end. Duplicated presentation is
tolerable here because it has a delete date.

**Per-account rollout** *(account-level targeting in your flag provider)*.
v1 and v2 coexist for as long as accounts are being rolled over, plausibly
indefinitely. **No v1 deletion. No flag deletion - it is permanent
infrastructure, and needs to survive as an account targeting rule.**

Per-account is not the cheaper option; it is strictly more expensive, and
planning it as "less work" is the mistake:

- **Dual maintenance is permanent.** With no delete date, every duplicated
  *behaviour* is a bug fixed twice, forever.
- **So logic extraction stops being cleanup and becomes the whole game.** The
  test that matters: a fix from `main` should only ever land in the logic
  layer. Anywhere it has to land twice is unfinished work, not a chore.
- **Behavioural divergence becomes customer-visible, not transitional.** Two
  accounts genuinely render differently at the same time. Accepted divergences
  belong in account-facing release notes, not just an internal status file.
- **CSS coexistence is unchanged.** Account-level targeting still resolves to
  one version per user per load, so the route-boundary bundle split stays
  correct and no Tailwind prefixing is needed.

Ordering follows design impact under both models: authoring surfaces first
(highest builder time-on-task, fastest signal), settings and admin last.

## Keeping up with `main` during the migration

Absorbing other devs' `main` work is a recurring ritual with its own cadence,
layering, and conflict tiers. See the parent **sync-main** skill (`SKILL.md`). The one rule that belongs here: a merge from `main` lands
changes in v1 only - porting them into the v2 twins is a separate, mandatory
second step, and deferring it is how the branch re-forks from the inside.

## If a long-lived branch already exists

Don't merge it. Harvest it.

1. Stop adding to it. It's now read-only reference.
2. Merge `main` into it one final time, so it stops rotting mid-harvest.
3. Land the scaffolding on `main` first: `v2/` tree, shared logic, the ui/core
   package, the router flag, the CSS bundle split. Behaviour-neutral, low
   review cost.
4. Port screen by screen out of the branch using the loop above.
   `git checkout branch -- path/to/file` into the `v2/` tree, adapt to the
   extracted hooks.
5. Delete the branch when it's empty.

This trades one terrifying merge for thirty boring ones. That trade is always
correct.

## Anti-patterns

- **Rebasing a shared long-lived branch.** Rewrites history others may hold,
  and forces conflict resolution once per commit instead of once per merge.
  Merge `main` in; never rebase a branch anyone else has pulled.
- **Copying a screen into v2 without extracting logic first.** Creates two
  divergent state machines. This is the most common regression pattern.
- **A global "new UI" flag.** Forces big-bang launch, prevents per-screen
  rollback.
- **Cosmetic cleanup in `v1`.** Lint, tokens, nesting - fix in `v2` or don't
  fix. Behavioural fixes are different and do belong in v1.
- **Letting v1 and v2 share a component file "just for now".** That file
  becomes the permanent conflict site.
- **Deferring v1 deletion to "a cleanup sprint"** *(staged cutover only)*. The
  cleanup sprint does not happen. Delete in the porting PR.
- **Treating per-account rollout as a reason to skip extraction.** It is the
  reason extraction is mandatory - permanent coexistence without a shared
  logic layer is permanent double-fixing.
- **Restructuring a working repo to match this document's directory names.**
  The pattern transfers; the paths are disposable.

## Escalation

- Extraction reveals tenancy scoping living in a component → **P0**. Scope
  enforcement must never sit in presentation. Stop and escalate before
  porting.
- A token needed by v2 has no v1 equivalent → file a design-system ticket,
  don't hardcode. Applies during migration exactly as it does normally.
- Migration timeline slipping past one quarter -> escalate to whoever owns the
  roadmap. Dual maintenance beyond a quarter costs more than pausing feature work
  to finish the port.
