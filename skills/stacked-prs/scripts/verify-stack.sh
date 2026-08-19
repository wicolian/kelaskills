#!/usr/bin/env bash
# verify-stack.sh - check both stack invariants.
#
#   1. the top branch is identical to the fat branch
#   2. every layer builds and tests green on its own
#
#   verify-stack.sh --plan layers.txt --verify "pnpm build && pnpm test" [--fat feat/big]
#
# Reads the same plan file as carve-stack.sh. Read-only: it checks branches out
# and runs the verify command, and changes no history.

set -euo pipefail

PLAN=""; VERIFY=""; FAT=""

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --plan)   PLAN="$2"; shift 2 ;;
    --verify) VERIFY="$2"; shift 2 ;;
    --fat)    FAT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown flag: $1" >&2; usage ;;
  esac
done

[ -n "$PLAN" ] && [ -n "$VERIFY" ] || usage
[ -f "$PLAN" ] || { echo "no such plan file: $PLAN" >&2; exit 1; }

cd "$(git rev-parse --show-toplevel)"
# Untracked files are fine (your plan file, build output). Tracked edits are not.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "ERROR: tracked files are modified. Commit them. Do not stash." >&2
  git status --short --untracked-files=no >&2
  exit 1
fi

START_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
# --force because a verify command may rewrite a tracked lockfile mid-run.
trap 'git checkout -q --force "$START_BRANCH" 2>/dev/null || true' EXIT

BRANCHES=()
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  BRANCHES+=("${line%%$'\t'*}")
done < "$PLAN"

RESULTS=(); FAILED=0

for BR in "${BRANCHES[@]}"; do
  if ! git rev-parse --verify --quiet "$BR" >/dev/null; then
    RESULTS+=("MISSING  $BR"); FAILED=1; continue
  fi
  echo "=== $BR"
  git checkout -q --force "$BR"
  LOG="/tmp/verify_${BR//\//_}.$$.log"
  if bash -lc "$VERIFY" > "$LOG" 2>&1; then
    RESULTS+=("PASS     $BR"); echo "    PASS"; rm -f "$LOG"
  else
    RESULTS+=("FAIL     $BR   log: $LOG"); FAILED=1
    echo "    FAIL"; tail -25 "$LOG" | sed 's/^/      /'
  fi
done

echo
echo "=== invariant 2: every layer green on its own"
printf '  %s\n' "${RESULTS[@]}"

if [ -n "$FAT" ]; then
  TOP="${BRANCHES[$((${#BRANCHES[@]}-1))]}"
  echo
  echo "=== invariant 1: $TOP vs $FAT"
  if [ -z "$(git diff --name-only "$FAT" "$TOP")" ]; then
    echo "  PASS - identical"
  else
    echo "  FAIL - differing paths:"
    git --no-pager diff --stat "$FAT" "$TOP" | sed 's/^/    /'
    FAILED=1
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "Both invariants hold. Safe to gh stack submit (ask the repo owner first)."
else
  echo "NOT safe to submit. Fix the plan and re-carve." >&2
  exit 1
fi
