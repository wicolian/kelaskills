#!/usr/bin/env bash
# why-line.sh - wave 1 and wave 2 of a context-archaeology dig, for one line of one file.
#
# Wave 1 is local and free: blame the line to a commit, print the full commit
# message, and say which releases contain it.
# Wave 2 needs the network: resolve the commit to a pull request, print the PR
# body, grep the body for issue and PR references, then print inline review
# comments and review verdicts.
#
# It is READ ONLY. It posts nothing, comments nothing, and changes nothing.
#
# Usage:
#   why-line.sh <file> <line>
#   why-line.sh <file>:<line>
#   why-line.sh --repo <owner>/<repo> <file> <line>
#
# Options:
#   --repo OWNER/REPO   override the slug inferred from the git remote
#   --no-net            wave 1 only, do not touch the network
#   --max-comments N    cap printed inline comments (default 20)
#
# Exit codes: 0 finished (with or without an answer), 2 bad invocation,
#             3 the line could not be blamed.
#
# Degrades honestly. If gh is missing, unauthenticated, or the repo is not on
# GitHub, it prints everything wave 1 found and then names exactly what it could
# not reach. It never reports silence as an answer.
#
# Bash 3.2 clean: no associative arrays, no ${x^^}, arrays guarded under set -u.

set -uo pipefail

SELF="$(basename "$0")"
die() { printf '%s: %s\n' "$SELF" "$1" >&2; exit "${2:-2}"; }
hr() { printf '\n%s\n' "------------------------------------------------------------"; }
head_() { printf '\n== %s ==\n' "$1"; }

REPO_SLUG=""
NO_NET=0
MAX_COMMENTS=20
ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) [ $# -ge 2 ] || die "--repo needs a value"; REPO_SLUG="$2"; shift 2 ;;
    --no-net) NO_NET=1; shift ;;
    --max-comments) [ $# -ge 2 ] || die "--max-comments needs a value"; MAX_COMMENTS="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *) ARGS[${#ARGS[@]}]="$1"; shift ;;
  esac
done

set -- ${ARGS[@]+"${ARGS[@]}"}

FILE=""
LINE=""
if [ $# -eq 1 ]; then
  case "$1" in
    *:[0-9]*) FILE="${1%:*}"; LINE="${1##*:}" ;;
    *) die "need a line number: $SELF <file> <line>" ;;
  esac
elif [ $# -eq 2 ]; then
  FILE="$1"; LINE="$2"
else
  die "usage: $SELF [--repo OWNER/REPO] [--no-net] <file> <line>"
fi

case "$LINE" in ''|*[!0-9]*) die "line must be a number, got '$LINE'" ;; esac
[ -e "$FILE" ] || die "no such file: $FILE"

DIR="$(cd "$(dirname "$FILE")" && pwd)"
BASE="$(basename "$FILE")"
ROOT="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)"
[ -n "$ROOT" ] || die "not inside a git repository: $FILE"
REL="${DIR#"$ROOT"/}"
[ "$REL" = "$DIR" ] && REL="" || REL="$REL/"
PATH_IN_REPO="$REL$BASE"

printf '%s\n' "context-archaeology / why-line"
printf 'target     %s:%s\n' "$PATH_IN_REPO" "$LINE"
printf 'repo root  %s\n' "$ROOT"

# ---------------------------------------------------------------- wave 1
head_ "wave 1  blame hygiene"
if [ -f "$ROOT/.git-blame-ignore-revs" ]; then
  printf 'found .git-blame-ignore-revs. Blame below does NOT apply it.\n'
  printf 'Re-run with: git -C %s blame --ignore-revs-file .git-blame-ignore-revs -L %s,%s -w -M -C -- %s\n' \
    "$ROOT" "$LINE" "$LINE" "$PATH_IN_REPO"
else
  printf 'no .git-blame-ignore-revs in the repo root. Blame is unfiltered.\n'
fi
printf 'flags in use: -w -M -C  (ignore whitespace, follow moves and copies)\n'

head_ "wave 1  blame"
BLAME="$(git -C "$ROOT" blame -L "$LINE,$LINE" --porcelain -w -M -C -- "$PATH_IN_REPO" 2>&1)"
if [ $? -ne 0 ] || [ -z "$BLAME" ]; then
  printf '%s\n' "$BLAME"
  die "could not blame $PATH_IN_REPO:$LINE (wrong path, or the file was renamed)" 3
fi
SHA="$(printf '%s\n' "$BLAME" | head -1 | cut -d' ' -f1)"
case "$SHA" in
  0000000000000000000000000000000000000000)
    printf 'the line is uncommitted in the working tree. There is no history yet.\n'
    exit 0 ;;
esac
printf 'sha        %s\n' "$SHA"
git -C "$ROOT" show -s --format='author     %an <%ae>%ndate       %ad%nsubject    %s' "$SHA"

head_ "wave 1  full commit message"
git -C "$ROOT" show -s --format=%B "$SHA"
printf '\nRead this before any network call. It answers the question outright often enough to stop here.\n'

head_ "wave 1  releases containing this commit"
TAGS="$(git -C "$ROOT" tag --contains "$SHA" 2>/dev/null | head -10)"
if [ -n "$TAGS" ]; then printf '%s\n' "$TAGS"; else printf 'no tag contains this commit (unreleased, or the repo does not tag).\n'; fi

# ---------------------------------------------------------------- wave 2
head_ "wave 2  reaching GitHub"
UNREACHED=""
add_unreached() { UNREACHED="$UNREACHED
  - $1"; }

if [ "$NO_NET" = "1" ]; then
  add_unreached "--no-net was passed. Nothing on GitHub was read: PR body, review comments, review verdicts."
elif ! command -v gh >/dev/null 2>&1; then
  add_unreached "gh is not installed. Could not read: PR body, review comments, review verdicts. Install it, or open the commit on the web host."
elif ! gh auth status >/dev/null 2>&1; then
  add_unreached "gh is installed but not authenticated (gh auth login). Could not read: PR body, review comments, review verdicts."
else
  if [ -z "$REPO_SLUG" ]; then
    ORIGIN="$(git -C "$ROOT" remote get-url origin 2>/dev/null)"
    case "$ORIGIN" in
      *github.com[:/]*)
        REPO_SLUG="${ORIGIN#*github.com}"
        REPO_SLUG="${REPO_SLUG#:}"
        REPO_SLUG="${REPO_SLUG#/}"
        REPO_SLUG="${REPO_SLUG%.git}"
        ;;
      '') add_unreached "no 'origin' remote. Pass --repo <owner>/<repo> to reach the pull request." ;;
      *)  add_unreached "origin is not a github.com remote ($ORIGIN). Pass --repo <owner>/<repo> if a GitHub mirror exists." ;;
    esac
  fi
fi

if [ -n "$REPO_SLUG" ]; then
  printf 'repo slug  %s\n' "$REPO_SLUG"

  PULLS_ERR="$(gh api "repos/$REPO_SLUG/commits/$SHA/pulls" 2>&1 >/dev/null)"
  PR="$(gh api "repos/$REPO_SLUG/commits/$SHA/pulls" --jq '.[0].number' 2>/dev/null)"

  if [ -n "$PULLS_ERR" ]; then
    case "$PULLS_ERR" in
      *"No commit found for SHA"*)
        printf 'HTTP 422, no commit found for this SHA on the remote.\n'
        printf 'VERDICT: the SHA is local-only or unpushed. The search was wrong, not the history.\n'
        add_unreached "the pull request for $SHA. The remote does not have this commit." ;;
      *"Could not resolve to a Repository"*|*"Not Found"*)
        printf '%s\n' "$PULLS_ERR"
        printf 'VERDICT: treat this as an AUTH signal, not as "no such repo". A different account may have access.\n'
        add_unreached "everything on GitHub. Check 'gh auth status' and which account is active." ;;
      *)
        printf '%s\n' "$PULLS_ERR"
        add_unreached "the pull request for $SHA. The API call failed." ;;
    esac
  elif [ -z "$PR" ] || [ "$PR" = "null" ]; then
    printf 'the pull request list for this commit is empty.\n'
    printf 'VERDICT: this is a REAL ANSWER. The commit went straight to trunk with no pull request. Stop looking for one.\n'
  else
    printf 'pull request #%s\n' "$PR"

    head_ "wave 2  pull request"
    gh pr view "$PR" --repo "$REPO_SLUG" --json title,url,closingIssuesReferences \
      --jq '"title      \(.title)\nurl        \(.url)\nlinked     \(if (.closingIssuesReferences|length) == 0 then "[] (closingIssuesReferences lies by omission; the grep below is the real check)" else ([.closingIssuesReferences[].number]|map("#"+(.|tostring))|join(" ")) end)"' 2>/dev/null

    head_ "wave 2  pull request body"
    BODY="$(gh pr view "$PR" --repo "$REPO_SLUG" --json body --jq '.body' 2>/dev/null)"
    if [ -n "$BODY" ] && [ "$BODY" != "null" ]; then printf '%s\n' "$BODY"; else printf '(empty body)\n'; fi

    head_ "wave 2  references grepped from the body"
    REFS="$(printf '%s\n' "$BODY" | grep -oE '(#[0-9]+|https://github\.com/[^ )]+/(issues|pull)/[0-9]+)' | sort -u)"
    if [ -n "$REFS" ]; then printf '%s\n' "$REFS"; else printf 'none. The body links no issue and no prior pull request.\n'; fi

    head_ "wave 2  inline review comments"
    CMTS="$(gh api "repos/$REPO_SLUG/pulls/$PR/comments" \
      --jq '.[] | "\(.user.login) @\(.path):\(.line // .original_line): \(.body)"' 2>/dev/null | head -"$MAX_COMMENTS")"
    if [ -n "$CMTS" ]; then printf '%s\n' "$CMTS"; else printf 'none.\n'; fi

    head_ "wave 2  reviews"
    REVS="$(gh api "repos/$REPO_SLUG/pulls/$PR/reviews" \
      --jq '.[] | "\(.user.login) [\(.state)] \(.body)"' 2>/dev/null | head -"$MAX_COMMENTS")"
    if [ -n "$REVS" ]; then printf '%s\n' "$REVS"; else printf 'none.\n'; fi
  fi
fi

# ---------------------------------------------------------------- honesty
hr
if [ -n "$UNREACHED" ]; then
  printf 'NOT REACHED. Do not read this run as "no evidence":%s\n' "$UNREACHED"
else
  printf 'All of wave 1 and wave 2 ran. Anything still missing was not recorded here.\n'
fi
printf '\nStop now if the commit message, the body or a review states the reason.\n'
printf 'Otherwise go to wave 3 (Slack, Sentry, PostHog, Jam), seeded with the pull request\n'
printf 'title, its merge date, the symbol on the line, and %s.\n' "$PATH_IN_REPO"
