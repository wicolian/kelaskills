# Resolving the conflicts a convergence produces

Read this when you are merging scattered branches into `<integration>` and the
merge stops. Placeholders are the ones from
[SKILL.md](../SKILL.md): `<trunk>` is what pull requests merge into,
`<integration>` is the branch collecting your work.

## Merge order: smallest delta first

Sort the branches you are converging by commits ahead of `<integration>`:

```bash
for b in <branch-a> <branch-b> <branch-c>; do
  printf '%-30s %s\n' "$b" "$(git rev-list --count <integration>..$b)"
done | sort -k2 -n
```

Merge the smallest first, the largest last.

The reasoning is not fairness, it is readability. **The second merge is where the
conflicts are.** Whatever you merge first becomes part of the tree the next merge
fights with. A small first merge produces a small, comprehensible conflict set on
the second. A large first merge produces a conflict set where you can no longer
tell which side is which.

Predict before each merge, and predict again after each commit:

```bash
git merge-tree --write-tree <integration> <branch>
```

Non-empty conflict output means resolve by hand. Empty output means clean
**against the tree as it is at this second**. It is not a property of the two
branches. Land anything on `<integration>` and the prediction is void.

Then:

```bash
git merge --no-commit --no-ff <branch>
```

`--no-commit` keeps you in control of the message. `--no-ff` keeps the merge
visible in history, which matters when you have to explain later why a file looks
the way it does.

## The resolution rule: the integration branch is the later decision

When the same lines conflict, the default is:

> **`<integration>` moved something, and the feature branch predates the move?
> Take `--ours`.**

`<integration>` carries the newer decision. The feature branch was written
against a world that has since changed. Re-applying its version silently reverts
whatever moved.

```bash
git checkout --ours -- <path>
```

**The one exception: the change the feature branch exists to deliver.**

That change is not stale, it is the payload. It never gets resolved as an
either/or. It is a **union**: keep the newer structure from `<integration>` and
put the feature branch's behaviour back inside it. If you find yourself picking a
side on the payload, you are about to ship a merge that compiles and does
nothing.

| Situation | Resolution |
|---|---|
| A file moved, renamed or was restructured on `<integration>` | `--ours` |
| A shared token, config value or constant changed on `<integration>` | `--ours` |
| Formatting or import-order churn | `--ours`, then reformat once at the end |
| **The behaviour the feature branch was written to add** | **Union. Rewrite it into the new structure.** |
| Both sides added a dependency | Keep both. |
| Lockfile | Never by hand. Fix the manifest, re-run the install, let the package manager rewrite it. |

## Conflicts are one theme wearing several file names

Before you resolve file by file, read the whole conflict list once:

```bash
git diff --name-only --diff-filter=U
```

Almost always the eleven conflicted files are **one decision** repeated: a
renamed export, a moved directory, a token that changed value, a config key that
became an array. Name the theme first, decide it once, then apply that decision
to all eleven. Resolving them one at a time invites eleven slightly different
answers, and three of them will be wrong.

## The conflict-resolution commit message

The next person to read this merge is trying to answer one question: *why does
this file look like that?* Answer it in the message.

Say the theme, say which side won, say why.

```
Bad:
  Merge branch 'feat/filters' into integration

  Resolved conflicts.

Good:
  merge feat/filters into integration

  Theme: the filter panel moved from components/ to features/filters/
  on integration after this branch forked. Nine of the eleven conflicts
  are that move.

  Took --ours for the paths and imports, so the new location wins.
  Unioned FilterBar.tsx: kept integration's structure and re-applied
  this branch's multi-select behaviour, which is the change the branch
  exists to deliver.

  Left the lockfile to the package manager.
```

Three or four lines. It is cheaper to write now than to reconstruct in six weeks.

## Telling a real conflict from a supersession

A branch that has been sitting for a long time may already be landed on the
trunk, in a better form. Its conflicts then are not conflicts. They are the trunk
telling you the work is done.

**Step 1. Look at the shape.**

```bash
git rev-list --left-right --count origin/<trunk>...<branch>
#            ^ behind        ^ ahead
```

Hundreds behind and a handful ahead is the shape to suspect. It is not proof.

**Step 2. Compare exported symbols, not lines.**

Line counts lie, especially where line endings or formatters have churned. What
matters is whether the trunk already exports everything the branch does.

```bash
FILE=<path/to/file>
comm -23 \
  <(git show <branch>:"$FILE" \
      | grep -oE 'export (const|let|function|async function|class|type|interface|default) [A-Za-z_$][A-Za-z0-9_$]*' \
      | awk '{print $NF}' | sort -u) \
  <(git show origin/<trunk>:"$FILE" \
      | grep -oE 'export (const|let|function|async function|class|type|interface|default) [A-Za-z_$][A-Za-z0-9_$]*' \
      | awk '{print $NF}' | sort -u)
```

`comm -23` prints only what is in the branch and **not** on the trunk.

- **Empty output.** The trunk already exports everything this file's branch
  version does. Strong supersession signal.
- **A few names.** Do not conclude "missing" yet. Go to step 3.

Across every changed file at once:

```bash
for f in $(git diff --name-only origin/<trunk>...<branch> -- '*.ts' '*.tsx' '*.js'); do
  git show origin/<trunk>:"$f" >/dev/null 2>&1 || { echo "ONLY-ON-BRANCH: $f"; continue; }
done
```

**Step 3. Check whether the remaining names were renamed or made config-driven.**

The two ways a symbol legitimately disappears from the trunk while its behaviour
stays:

```bash
# renamed: does the trunk have something that does this job under another name?
git log --oneline -S'<symbol>' origin/<trunk> | head -5
git grep -n '<a distinctive string or literal from the symbol>' origin/<trunk>

# made config-driven: three exported variants became one function plus a key
git grep -n '<the shared literal>' origin/<trunk> -- <dir>
```

A branch exporting `useCompactTable`, `useWideTable` and `useAutoTable` against a
trunk exporting `useTable(mode)` is superseded, not incomplete.

**Step 4. Decide, and say it out loud.**

| Finding | Do |
|---|---|
| Trunk exports everything, or everything under new names | **Superseded. Drop the branch.** Close its PR with one sentence saying which trunk commit replaced it. |
| One or two real behaviours are genuinely absent | Do not merge the branch. Cherry-pick or rewrite just those, onto `<integration>`, as a small commit. |
| Substantial unique work remains | A real merge. Go back to the merge order above. |

**Do not build an integration branch to carry nothing.** A superseded branch
merged anyway produces a diff full of reverts that read as deliberate, and
somebody will spend a day working out which side was right.

## If the merge is unrecoverable

```bash
git merge --abort       # before you commit
git reset --hard ORIG_HEAD   # after, only if nothing else landed since
```

Then reconsider the order. A merge that will not resolve is usually a merge you
attempted second when it should have been first, or a branch that is superseded
and should not be merged at all.
