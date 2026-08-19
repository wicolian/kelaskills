# The porting loop (Layer B), as a checklist

Layer A merged `main` in. This is the part that is silent if you skip it. Run it
per candidate, in order.

## Guardrails

- Every path you edit is under the checkout you are standing in. Never reach into
  a sibling checkout of the same repo.
- **Never `git stash`.** The sync refuses a dirty tree on purpose.
- **Never `git checkout origin/main -- <path>` over a redesigned file**, a gate
  wrapper, or redesign styles. That wipes the redesign in one command. Port by
  editing, always.
- Commit locally. Do not push, do not tag beyond what the sync tagged, do not open
  a PR, unless you were asked to in this session.
- Stage explicit paths. Never `git add -A`.

## Steps

**1. Confirm position.** `git rev-parse --show-toplevel` and
`git branch --show-current`. Abort and say so if either is wrong.

**2. Confirm the tree is clean.** `git status --porcelain`. If dirty, stop and
ask whether to commit. Do not stash. Do not proceed.

**3. Layer A - merge.** Run the sync script.
- On conflicts, resolve by file type (see the parent skill). Take the mainline
  side for shared logic, security and schema bumps; take the branch side for the
  redesign tree and its tokens; combine for gate wrappers, shared shells and
  `package.json`. Then `git add <explicit paths> && git commit`.
- If it reports already up to date, **still continue.** There may be unfinished
  ports from an earlier window. Cross-check the log.

**4. Get the candidate list.** Anything where a mainline file has a redesigned
twin, a mirrored path, or an entry in your hand-maintained drift map. The map
matters: no tool can infer a twin that was renamed.

**5. Port each candidate.** For every one:

- Read what `main` actually changed: `git diff <since-ref>...origin/main -- <path>`
- Read the twin.
- Classify honestly:
  - **PORT** - the change is behavioural: logic, data shape, a guard, a query, an
    edge case, security.
  - **SKIP** - pure formatting, copy, or legacy-only chrome the redesign replaced.
  - **VERIFY** - the twin imports the same module, so Layer A already applied it.
    Confirm the import path. Do not re-port.
- For PORT: edit the twin so the **behaviour** matches. Keep the redesign's
  presentation, naming, tokens and component structure. Do not copy the old markup
  or styles across.
- If a mainline change has **no** twin yet, that is expected and normal - most
  legacy components will never get one. Note it and move on. Do not invent a twin.

**6. Verify.** Run these, and report the real output:
- the boundary or layering check, if you have one; a merge is exactly when
  baselines drift
- typecheck and lint for the packages you touched
- unit tests, if the ports touched logic with coverage

**7. Log.** One line per candidate: the verdict, and what was ported. **If a PORT
was left undone, write that down** in the log and say it in your summary.

**8. Commit.** One coherent commit for the ports. Explicit paths only.

## The two failure modes

| Failure | What it looks like later |
|---|---|
| Tagging after Layer A and calling it a sync | Green board, the fix silently absent from half the product |
| A silent SKIP on something behavioural | A bug production already fixed, shipped again |
