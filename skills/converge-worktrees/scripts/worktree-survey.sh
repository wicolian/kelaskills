#!/usr/bin/env bash
# worktree-survey.sh - read-only survey of every worktree before you converge them.
#
# Prints, for each worktree of one repository:
#   branch, whether an upstream is configured, dirty file count, unpushed
#   commits, and commits behind/ahead of a base ref.
#
# Then runs the OVERLAP CHECK: for every uncommitted file, it reports whether a
# byte-identical copy already exists on a compare ref. That is the check that
# tells you the convergence job is smaller than it looks, because most "lost"
# uncommitted work has usually already been committed somewhere else.
#
# Finally, if `gh` is present and authenticated, it lists your open pull
# requests. Without `gh` it says so and carries on.
#
# READ ONLY. It never commits, merges, pushes, checks out, stashes or fetches.
# Everything it runs is a query.
#
# Usage:
#   worktree-survey.sh [--repo <path>] [--base <ref>] [--compare <ref>] [--no-pr]
#
#   --repo <path>     any checkout of the repository (default: cwd)
#   --base <ref>      count behind/ahead against this ref
#                     (default: origin/HEAD, then origin/main, main, master)
#   --compare <ref>   overlap check against this ref (default: the base)
#   --no-pr           skip the `gh` section
#
# Exit: 0 always when the survey ran, 2 when the arguments or repo are unusable.
# macOS bash 3.2 compatible.
set -uo pipefail

BASE=""
COMPARE=""
REPO="."
WANT_PR=1

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)    REPO="${2:-}";    shift 2 || exit 2 ;;
    --base)    BASE="${2:-}";    shift 2 || exit 2 ;;
    --compare) COMPARE="${2:-}"; shift 2 || exit 2 ;;
    --no-pr)   WANT_PR=0;        shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v git >/dev/null 2>&1 || { echo "git not found" >&2; exit 2; }

ROOT="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$ROOT" ] || { echo "not a git repository: $REPO" >&2; exit 2; }

short() { case "$1" in "$HOME"/*) echo "~${1#$HOME}" ;; *) echo "$1" ;; esac; }

have_ref() { git -C "$ROOT" rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1; }

pick_base() {
  local d
  d="$(git -C "$ROOT" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$d" ] && have_ref "$d"; then echo "$d"; return 0; fi
  for d in origin/main origin/master main master; do
    if have_ref "$d"; then echo "$d"; return 0; fi
  done
  return 1
}

if [ -z "$BASE" ]; then
  BASE="$(pick_base)" || {
    echo "could not guess a base ref. pass --base <ref>." >&2
    exit 2
  }
fi
have_ref "$BASE" || { echo "base ref does not resolve: $BASE" >&2; exit 2; }

[ -n "$COMPARE" ] || COMPARE="$BASE"
if ! have_ref "$COMPARE"; then
  echo "compare ref does not resolve: $COMPARE" >&2
  exit 2
fi

# path<TAB>branch, one line per worktree. branch is "(detached)" or "(bare)".
each_worktree() {
  local p="" b="" det=0 bare=0
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        if [ -n "$p" ]; then
          if [ "$bare" = 1 ]; then b="(bare)"; elif [ "$det" = 1 ]; then b="(detached)"; fi
          printf '%s\t%s\n' "$p" "${b:-(unknown)}"
        fi
        p="${line#worktree }"; b=""; det=0; bare=0 ;;
      branch\ refs/heads/*) b="${line#branch refs/heads/}" ;;
      detached) det=1 ;;
      bare)     bare=1 ;;
    esac
  done < <(git -C "$ROOT" worktree list --porcelain 2>/dev/null)
  if [ -n "$p" ]; then
    if [ "$bare" = 1 ]; then b="(bare)"; elif [ "$det" = 1 ]; then b="(detached)"; fi
    printf '%s\t%s\n' "$p" "${b:-(unknown)}"
  fi
}

echo "== worktree survey =="
echo "   repo    $(short "$ROOT")"
echo "   base    $BASE"
echo "   compare $COMPARE"
echo

printf '%-34s %-26s %-9s %5s %8s %7s %6s\n' \
  WORKTREE BRANCH UPSTREAM DIRTY UNPUSHED BEHIND AHEAD

TOTAL_DIRTY=0
TOTAL_WT=0

while IFS="$(printf '\t')" read -r wpath wbranch; do
  [ -n "$wpath" ] || continue
  TOTAL_WT=$((TOTAL_WT + 1))

  if [ ! -d "$wpath" ]; then
    printf '%-34s %-26s %-9s %5s %8s %7s %6s\n' \
      "$(short "$wpath")" "$wbranch" "MISSING" "-" "-" "-" "-"
    continue
  fi

  dirty="$(git -C "$wpath" status --porcelain --untracked-files=all 2>/dev/null | grep -c . | tr -d ' ')"
  [ -n "$dirty" ] || dirty=0
  TOTAL_DIRTY=$((TOTAL_DIRTY + dirty))

  up="$(git -C "$wpath" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
  if [ -n "$up" ]; then
    ups="yes"
    unpushed="$(git -C "$wpath" rev-list --count '@{u}..HEAD' 2>/dev/null)"
  else
    ups="none"
    unpushed="-"
  fi
  [ -n "$unpushed" ] || unpushed="-"

  counts="$(git -C "$wpath" rev-list --left-right --count "$BASE...HEAD" 2>/dev/null)"
  if [ -n "$counts" ]; then
    behind="$(echo "$counts" | awk '{print $1}')"
    ahead="$(echo "$counts" | awk '{print $2}')"
  else
    behind="-"; ahead="-"
  fi

  printf '%-34s %-26s %-9s %5s %8s %7s %6s\n' \
    "$(short "$wpath")" "$wbranch" "$ups" "$dirty" "$unpushed" "$behind" "$ahead"
done < <(each_worktree)

echo
echo "   $TOTAL_WT worktree(s), $TOTAL_DIRTY uncommitted file(s) in total"

echo
echo "== overlap check vs $COMPARE =="
echo "   SAME    = byte-identical copy already committed on $COMPARE"
echo "   DIFFERS = tracked there, but your copy is not the same bytes"
echo "   ABSENT  = does not exist on $COMPARE"
echo

OV_SAME=0; OV_DIFF=0; OV_ABSENT=0

while IFS="$(printf '\t')" read -r wpath wbranch; do
  [ -n "$wpath" ] || continue
  [ -d "$wpath" ] || continue
  case "$wbranch" in "(bare)") continue ;; esac

  printed_header=0
  # NUL-delimited so spaces and odd bytes in paths survive. A rename record is
  # "XY <new>\0<old>\0", so the source path is consumed and dropped.
  while IFS= read -r -d '' rec; do
    st="${rec:0:2}"
    rel="${rec:3}"
    case "$st" in
      R*|C*) IFS= read -r -d '' _src || true ;;
    esac
    [ -n "$rel" ] || continue
    [ -f "$wpath/$rel" ] || continue

    if ! git -C "$wpath" cat-file -e "$COMPARE:$rel" 2>/dev/null; then
      verdict="ABSENT"; OV_ABSENT=$((OV_ABSENT + 1))
    elif git -C "$wpath" show "$COMPARE:$rel" 2>/dev/null | cmp -s - "$wpath/$rel"; then
      verdict="SAME"; OV_SAME=$((OV_SAME + 1))
    else
      verdict="DIFFERS"; OV_DIFF=$((OV_DIFF + 1))
    fi

    if [ "$printed_header" = 0 ]; then
      printf '%s  [%s]\n' "$(short "$wpath")" "$wbranch"
      printed_header=1
    fi
    printf '  %-8s %s\n' "$verdict" "$rel"
  done < <(git -C "$wpath" status --porcelain -z --untracked-files=all 2>/dev/null)

  [ "$printed_header" = 1 ] && echo
done < <(each_worktree)

TOTAL_OV=$((OV_SAME + OV_DIFF + OV_ABSENT))
if [ "$TOTAL_OV" = 0 ]; then
  echo "   no uncommitted files. nothing to compare."
else
  echo "   $OV_SAME same, $OV_DIFF differs, $OV_ABSENT absent, of $TOTAL_OV uncommitted file(s)"
  if [ "$OV_SAME" -gt 0 ]; then
    echo "   the SAME rows are already on $COMPARE. they are not work you have to carry."
  fi
fi

echo
echo "== open pull requests =="
if [ "$WANT_PR" = 0 ]; then
  echo "   skipped (--no-pr)"
elif ! command -v gh >/dev/null 2>&1; then
  echo "   gh not installed. list them in the web UI, or: brew install gh"
elif ! gh auth status >/dev/null 2>&1; then
  echo "   gh is installed but not authenticated. run: gh auth login"
else
  # Empty by default. Guarded so `set -u` does not abort on bash 3.2, where an
  # empty array expansion is an unbound variable.
  GH_EXTRA=()
  out="$(cd "$ROOT" && gh pr list --state open --author @me \
          --json number,headRefName,baseRefName,title \
          --template '{{range .}}{{printf "  #%v  %s -> %s  %s\n" .number .headRefName .baseRefName .title}}{{end}}' \
          ${GH_EXTRA[@]+"${GH_EXTRA[@]}"} 2>&1)"
  rc=$?
  if [ "$rc" != 0 ]; then
    echo "   gh could not list pull requests:"
    printf '%s\n' "$out" | sed 's/^/     /'
  elif [ -z "$out" ]; then
    echo "   none open by you"
  else
    printf '%s\n' "$out"
    echo "   retarget with: gh pr edit <n> --base <integration>   (keeps the description)"
  fi
fi

echo
echo "read-only. nothing above changed a ref, an index or a file."
