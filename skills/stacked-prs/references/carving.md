# Carving a fat branch into a stack

You have one branch with a month of work and a diff too large to review. You want
a stack. This is the method.

## Why not split by commits

The obvious idea is to group the existing commits into ranges and make one branch
per range. It fails on real branches, for three reasons:

1. **History is interleaved.** You touched the config on day 1, day 9 and day 20.
   No contiguous range holds "the config change".
2. **Mid-range states do not build.** A commit that renames a symbol and a commit
   that updates its callers can be 40 commits apart.
3. **Fixups.** A month of work contains commits that fix earlier commits in the
   same branch. Split them apart and both halves are wrong.

Cherry-pick ranges only when the branch is short and was already committed in
themed blocks. Check first:

```bash
git log --oneline --reverse trunk..fat | cat
```

If you can draw clean lines between blocks and each block touches a disjoint set
of paths, ranges work and you keep the history. Otherwise, carve by path.

## Split by path

For each layer you declare a set of paths. The layer's branch is the previous
layer plus **the fat branch's content at those paths**. Stack the layers and the
top branch is byte-identical to the fat branch.

You lose the intermediate commit history of the fat branch. You gain layers that
each build, review and revert on their own. On a revamp that is the right trade -
nobody was going to read those 400 commit messages.

The fat branch is never modified. Keep it until the stack is merged.

## Step 1 - Bring the fat branch current

```bash
git checkout fat
git merge origin/<trunk>          # merge. Do not rebase a month of commits.
# resolve, build, test
```

Do this first. Carving against a stale trunk means every layer carries unrelated
drift, and invariant 1 stops meaning anything.

## Step 2 - Inventory the diff

```bash
TRUNK=origin/main
FAT=fat

# how big, by top-level area
git diff --numstat $TRUNK...$FAT | awk '{split($3,p,"/"); a[p[1]"/"p[2]]+=$1+$2} END{for(k in a) printf "%8d  %s\n", a[k], k}' | sort -rn | head -40

# what kind of change
git diff --name-status $TRUNK...$FAT | cut -c1 | sort | uniq -c   # A/M/D/R counts

# files deleted or renamed - these decide layer order
git diff --name-status --diff-filter=DR $TRUNK...$FAT | cat

# config and lockfiles - almost always layer 1
git diff --name-only $TRUNK...$FAT | grep -E '(^|/)(package\.json|.*lock.*|tsconfig.*|\.nvmrc|biome\.json|\.github/)' | cat
```

Use `...` (three dots) so you measure against the merge base, not the trunk tip.

## Step 3 - Order the layers

Bottom to top. Each layer must build with only the layers below it.

| Order | Layer | Contains |
|---|---|---|
| 1 | **Toolchain / config** | package manager, lockfile, Node and TS versions, build config, CI, linter config |
| 2 | **Generated and vendored** | codegen output, schema types, vendored assets |
| 3 | **Leaf packages** | shared libs, tokens, utils - anything nothing above it imports |
| 4..n | **Consumers, in dependency order** | one layer per package or feature area; imports only downward |
| n+1 | **Deletions and renames** | removing the old implementation, after every caller has moved |
| last | **Catch-all** | whatever invariant 1 says you missed |

Three rules that decide most arguments:

- **A layer may only import from layers below it.** If layer 3 imports layer 5,
  they are one layer. Fold them.
- **Deletions go last.** Delete a file in layer 2 and every layer between 2 and
  the one that removed its last caller is red.
- **Config goes first, always.** A TypeScript upgrade or an npm-to-pnpm cutover
  in layer 4 means layers 1 to 3 were verified with the wrong toolchain.

Target 3 to 6 layers. Above 6 the reviewers stop reading and you have made the
problem worse.

## Step 4 - Write the layer plan

A plain text file. One line per layer, bottom first. Tab between the branch name
and the pathspecs. `#` comments and blank lines are ignored.

```
# layers.txt  -  bottom to top
revamp/001-toolchain	package.json pnpm-lock.yaml pnpm-workspace.yaml .nvmrc tsconfig.base.json .github biome.json
revamp/002-core		packages/core/src packages/core/package.json
revamp/003-plugin	packages/plugin/src
revamp/004-app		apps/web/src
revamp/005-cleanup	.
```

The last layer is `.` on purpose. It is the catch-all that guarantees invariant 1:
everything not claimed above lands here. If it comes out large, your plan is
wrong - read what it caught and promote those paths into real layers.

## Step 5 - Carve

```bash
scripts/carve-stack.sh --fat fat --trunk origin/main --plan layers.txt \
  --verify "pnpm install --frozen-lockfile && pnpm build && pnpm test"
```

It creates each branch off the one below, copies the fat branch's content at that
layer's paths, commits, and runs the verify command. It stops at the first red
layer and tells you which one.

Omit `--verify` for a fast dry run of the shape, then re-run with it.

Files the fat branch deleted are reported, not removed, unless you pass
`--allow-rm`. Read the list first.

## Step 6 - Verify

```bash
scripts/verify-stack.sh --fat fat --plan layers.txt \
  --verify "pnpm install --frozen-lockfile && pnpm build && pnpm test"
```

Invariant 1 - the top branch equals the fat branch:

```bash
git diff --stat fat..revamp/005-cleanup      # must be empty
```

Invariant 2 - every layer green on its own. The script prints a table. Every row
must pass. Not "passes except the one that needs the next layer" - that is
exactly the failure a stack is supposed to catch.

## Step 7 - Publish

```bash
gh stack init --base main revamp/001-toolchain revamp/002-core revamp/003-plugin revamp/004-app revamp/005-cleanup
gh stack view
gh stack submit
```

`gh stack init` with several branch names adopts existing branches in the order
given, bottom to top. Nothing is pushed until `gh stack submit`.

**Confirm with the repo owner before `gh stack submit`.** Everything up to this
point is local and undoable. Submit is not.

## When a layer will not build alone

In order of preference:

1. **Move paths.** The missing symbol usually lives one layer up. Move its file
   down. Check it does not drag its own imports with it.
2. **Fold two layers.** `gh stack modify`, or edit `layers.txt` and re-carve.
   Two honest layers beat five that need each other.
3. **Reorder.** Common when a deletion sits too low.
4. **Accept a documented red layer.** Only for a genuine chicken-and-egg, only
   with the reason written in the PR body, and never for the bottom layer. This
   is a last resort, not a shortcut. If you use it, say so out loud to the human.

Never fix a red layer by writing code that is not in the fat branch. That breaks
invariant 1, and invariant 1 is the only reason anyone can trust the carve.

## Re-carving

Carving is cheap and idempotent. If the plan is wrong, fix `layers.txt` and run
`carve-stack.sh --force` again. It rebuilds the branches from the fat branch.

Once the stack is submitted and reviewed, stop re-carving - you would throw away
the review comments. From then on use `gh stack modify` and `gh stack sync`.

## Worked example - a toolchain and redesign revamp

Fat branch: npm to pnpm, TypeScript 5 to 7, a rebuilt UI layer, 600k added lines.

```
revamp/001-pnpm		package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc .nvmrc scripts/only-pnpm.mjs .github/workflows
revamp/002-typescript	tsconfig.json tsconfig.*.json packages/*/tsconfig.json
revamp/003-tokens	packages/core/src/tokens packages/core/src/theme
revamp/004-core		packages/core/src
revamp/005-plugin	packages/plugin/src
revamp/006-app		apps/web/src
revamp/007-remove-old	.
```

Why it is ordered that way:

- pnpm first: every later layer's verify runs `pnpm install`, so the lockfile has
  to exist before anything is checked.
- TypeScript second: a type error found in layer 5 under the old compiler is not
  a real result.
- tokens before core, core before plugin, plugin before app: import direction.
- The old implementation is removed last, in the catch-all, once nothing calls it.

## Case: a toolchain bump - "should TypeScript 7 be PR-001?"

**Yes. The bump goes at the bottom.** Everything above it is then verified with
the compiler, the package manager and the config it will actually ship with. A
type error found in layer 5 under the old compiler is not a real result, and a
green layer 3 checked with TS 5 tells you nothing about TS 7.

Order inside the toolchain layers:

1. **Package manager first** (npm to pnpm). It resolves every other tool,
   including the compiler. The lockfile must exist before any layer above runs
   `install`.
2. **Compiler and build config second** (TypeScript, Vite, the tsconfigs).
3. **Linter and CI third.** Nothing depends on them.

### The bump does not travel alone

TS 7 is stricter, so the fat branch contains fixes that exist only because of
the bump. Those fixes belong in the bump's layer. A config-only layer 1 is red,
and a red bottom layer is the one case with no excuse.

Find the fallout with the carve loop, not by reading the diff:

```bash
# 1. start with config only
printf 'rev/001-ts7\ttsconfig.json tsconfig.*.json packages/*/tsconfig.json package.json\n' > layers.txt
#    ...rest of the plan...

# 2. carve, verifying just the typecheck - it will fail
scripts/carve-stack.sh --fat fat --trunk origin/main --plan layers.txt --verify "pnpm typecheck"

# 3. read the failure log. Add the erroring files' paths to layer 1. Re-carve.
scripts/carve-stack.sh ... --force

# 4. repeat until layer 1 is green
```

The loop terminates, because the fat branch is already green - every fix the
compiler wants is somewhere in it. Each pass pulls the next set of files down.

### When the fallout is everywhere

Sometimes the loop drags half the repo into layer 1. Then TS 7 cannot honestly
be a small layer. Two choices:

| Option | Do it when |
|---|---|
| **One big mechanical layer**, titled so reviewers know what it is - "TS 7 bump and all of its fallout, mechanical" | The fixes are repetitive: added annotations, widened types, import rewrites. Big but skimmable. Prefer this. |
| **Scope the gate.** Bump at the bottom, but layer 1's verify command typechecks only the packages that exist below it, widening as layers land | The repo supports per-package typecheck and the fallout is genuinely per-package. More moving parts. |

Do not solve it by loosening `strict` or adding `skipLibCheck` to make layer 1
pass. That is code the fat branch does not have, so it breaks invariant 1, and
it hides the exact class of error the bump was supposed to surface.

### And the redesign on top

With the toolchain at the bottom, the rest of a revamp stacks in import order -
tokens, then core, then plugin, then app, then the removal of the old
implementation. See the worked example above.
