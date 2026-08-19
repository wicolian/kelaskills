#!/usr/bin/env bash
# carve-stack.sh - build a stack of branches from one fat branch, by path.
#
# Reads a layer plan (bottom to top). For each layer it branches off the layer
# below and copies the fat branch's content at that layer's paths. The top
# branch ends up identical to the fat branch.
#
# The fat branch is never modified. Nothing is pushed.
#
#   carve-stack.sh --fat feat/big --trunk origin/main --plan layers.txt \
#                  --verify "pnpm install --frozen-lockfile && pnpm build"
#
# Plan format, one line per layer, bottom first:
#   <branch-name><TAB><space-separated pathspecs>
#   # comments and blank lines ignored
#   Use "." as the last layer's pathspec to catch everything else.

set -euo pipefail

FAT=""; TRUNK=""; PLAN=""; VERIFY=""; FORCE=0; ALLOW_RM=0; CTYPE="chore"

usage() { sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --fat)     FAT="$2"; shift 2 ;;
    --trunk)   TRUNK="$2"; shift 2 ;;
    --plan)    PLAN="$2"; shift 2 ;;
    --verify)  VERIFY="$2"; shift 2 ;;
    --force)   FORCE=1; shift ;;
    --allow-rm) ALLOW_RM=1; shift ;;
    --type)    CTYPE="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown flag: $1" >&2; usage ;;
  esac
done

[ -n "$FAT" ] && [ -n "$TRUNK" ] && [ -n "$PLAN" ] || usage
[ -f "$PLAN" ] || { echo "no such plan file: $PLAN" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"

# --- preconditions ----------------------------------------------------------
# Tracked changes block the carve. Untracked files (your layers.txt, build
# output) are left alone - the carve stages only the files it copies.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "ERROR: tracked files are modified. Commit them. Do not stash." >&2
  git status --short --untracked-files=no >&2
  exit 1
fi
git rev-parse --verify --quiet "$FAT^{commit}"   >/dev/null || { echo "no such ref: $FAT" >&2; exit 1; }
git rev-parse --verify --quiet "$TRUNK^{commit}" >/dev/null || { echo "no such ref: $TRUNK" >&2; exit 1; }

START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# The tracked tree was verified clean above, so anything dirty at exit was made
# by this script. --force discards only that, and only in this worktree.
PRECHECK_OK=1
restore() {
  [ "${PRECHECK_OK:-0}" = 1 ] || return 0
  git checkout -q --force "$START_BRANCH" 2>/dev/null || true
}
trap restore EXIT

MB="$(git merge-base "$TRUNK" "$FAT")"
if [ "$MB" != "$(git rev-parse "$TRUNK")" ]; then
  echo "WARNING: $FAT is behind $TRUNK. Merge the trunk into $FAT first," >&2
  echo "         otherwise the carve reproduces a stale branch." >&2
fi

# --- read the plan ----------------------------------------------------------
BRANCHES=(); PATHSETS=()
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  br="${line%%$'\t'*}"
  ps="${line#*$'\t'}"
  [ "$br" = "$ps" ] && { echo "ERROR: no tab in plan line: $line" >&2; exit 1; }
  BRANCHES+=("$br"); PATHSETS+=("$ps")
done < "$PLAN"

N=${#BRANCHES[@]}
[ "$N" -ge 2 ] || { echo "ERROR: a stack needs at least 2 layers" >&2; exit 1; }

# refuse to move a branch that already exists, unless --force
for br in "${BRANCHES[@]}"; do
  if git rev-parse --verify --quiet "$br" >/dev/null && [ "$FORCE" -eq 0 ]; then
    echo "ERROR: branch $br already exists (at $(git rev-parse --short "$br"))." >&2
    echo "       Pass --force to rebuild it. The old SHA is printed above, so it is recoverable." >&2
    exit 1
  fi
done

echo "Carving $N layers from $FAT onto $TRUNK"
echo

PARENT="$TRUNK"
for i in $(seq 0 $((N-1))); do
  BR="${BRANCHES[$i]}"; PS="${PATHSETS[$i]}"
  printf '=== [%d/%d] %s\n' "$((i+1))" "$N" "$BR"

  if git rev-parse --verify --quiet "$BR" >/dev/null; then
    echo "    rebuilding (was $(git rev-parse --short "$BR"))"
  fi
  git checkout -q -B "$BR" "$PARENT"

  # shellcheck disable=SC2086
  git ls-tree -r --name-only "$FAT"  -- $PS | sort > /tmp/carve_fat.$$
  # shellcheck disable=SC2086
  git ls-tree -r --name-only HEAD    -- $PS | sort > /tmp/carve_par.$$

  if [ -s /tmp/carve_fat.$$ ]; then
    tr '\n' '\0' < /tmp/carve_fat.$$ | xargs -0 git checkout "$FAT" --
  fi

  comm -23 /tmp/carve_par.$$ /tmp/carve_fat.$$ > /tmp/carve_del.$$
  if [ -s /tmp/carve_del.$$ ]; then
    if [ "$ALLOW_RM" -eq 1 ]; then
      echo "    removing $(wc -l < /tmp/carve_del.$$ | tr -d ' ') file(s) deleted on $FAT"
      tr '\n' '\0' < /tmp/carve_del.$$ | xargs -0 git rm -q --
    else
      echo "    STOP: $FAT deletes these files under this layer's paths:" >&2
      sed 's/^/      /' /tmp/carve_del.$$ >&2
      echo "    Read the list. Re-run with --allow-rm --force to reproduce the deletions." >&2
      rm -f /tmp/carve_fat.$$ /tmp/carve_par.$$ /tmp/carve_del.$$
      exit 1
    fi
  fi
  rm -f /tmp/carve_fat.$$ /tmp/carve_par.$$ /tmp/carve_del.$$

  # git checkout <ref> -- <paths> and git rm already stage their changes.
  # Never "git add -A" here: it would sweep untracked files into the layer.
  if git diff --cached --quiet; then
    echo "    WARNING: empty layer - these paths add nothing over $PARENT. Fix the plan." >&2
  else
    # Conventional-commit shaped, body wrapped under 100 cols, so repos with
    # commitlint or husky accept it without --no-verify.
    { printf '%s(stack): %s\n\n' "$CTYPE" "$BR"
      printf 'Layer %s/%s of a stacked PR chain onto %s.\n' "$((i+1))" "$N" "$TRUNK"
      printf 'Carved from %s by path.\n\nPaths:\n' "$FAT"
      for one in $PS; do printf -- '- %.90s\n' "$one"; done
    } > /tmp/carve_msg.$$
    git commit -q -F /tmp/carve_msg.$$
    rm -f /tmp/carve_msg.$$
    git --no-pager diff --shortstat "$PARENT" HEAD | sed 's/^/    /'
  fi

  if [ -n "$VERIFY" ]; then
    echo "    verify: $VERIFY"
    if bash -lc "$VERIFY" > /tmp/carve_verify.$$ 2>&1; then
      echo "    PASS"
    else
      echo "    FAIL - layer $BR is not green on its own." >&2
      tail -40 /tmp/carve_verify.$$ >&2
      echo "    Full log: /tmp/carve_verify.$$" >&2
      echo "    Fix by moving paths between layers or folding layers. Do NOT add code." >&2
      echo "    Then re-run with --force to rebuild." >&2
      exit 1
    fi
    rm -f /tmp/carve_verify.$$
  fi

  PARENT="$BR"
  echo
done

TOP="${BRANCHES[$((N-1))]}"
echo "=== invariant 1: $TOP must equal $FAT"
if [ -z "$(git diff --name-only "$FAT" "$TOP")" ]; then
  echo "    PASS - identical"
else
  echo "    FAIL - the plan missed these paths:" >&2
  git --no-pager diff --stat "$FAT" "$TOP" | sed 's/^/      /' >&2
  exit 1
fi

echo
echo "Done. Next:"
echo "  gh stack init --base ${TRUNK#origin/} ${BRANCHES[*]}"
echo "  gh stack view"
echo "  gh stack submit      # confirm with the repo owner first - this pushes"
