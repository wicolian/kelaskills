#!/usr/bin/env bash
# pr-status.sh - one read-only snapshot of a pull request.
#
#   ./pr-status.sh                    # the PR for the current branch
#   ./pr-status.sh 42                 # PR 42 in the current repo
#   ./pr-status.sh 42 owner/repo      # PR 42 elsewhere
#
# Prints: state, checks, reviews, and which feedback arrived AFTER the last push.
# That last part is the whole point: only act on feedback newer than your head
# commit.
#
# This script only reads. It never opens, comments on, closes, merges, rebases or
# pushes anything. Keep it that way.
set -u

PR="${1:-}"
REPO="${2:-}"

command -v gh >/dev/null 2>&1 || { echo "gh CLI not found" >&2; exit 2; }

R_FLAG=""
[ -n "$REPO" ] && R_FLAG="--repo $REPO"

if [ -z "$PR" ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  [ -n "$BRANCH" ] || { echo "not in a git repo, and no PR number given" >&2; exit 2; }
  # shellcheck disable=SC2086
  PR="$(gh pr list $R_FLAG --head "$BRANCH" --state open --limit 1 --json number -q '.[0].number' 2>/dev/null)"
  [ -n "$PR" ] && [ "$PR" != "null" ] || { echo "no open PR for branch '$BRANCH'" >&2; exit 1; }
fi

# shellcheck disable=SC2086
[ -n "$REPO" ] || REPO="$(gh repo view $R_FLAG --json nameWithOwner -q .nameWithOwner)"
[ -n "$REPO" ] || { echo "could not resolve owner/repo" >&2; exit 2; }

FIELDS='number,title,state,isDraft,baseRefName,headRefName,headRefOid,mergeStateStatus,url'
META="$(gh pr view "$PR" --repo "$REPO" --json "$FIELDS" \
  -q '[.number,.title,.state,(.isDraft|tostring),.baseRefName,.headRefName,.headRefOid,.mergeStateStatus,.url] | @tsv')"
[ -n "$META" ] || { echo "could not read PR $PR in $REPO" >&2; exit 1; }

IFS="$(printf '\t')" read -r N TITLE STATE DRAFT BASE HEAD SHA MERGE URL <<PRMETA
$META
PRMETA

SINCE="$(gh api "repos/$REPO/commits/$SHA" -q .commit.committer.date 2>/dev/null)"
[ -n "$SINCE" ] || SINCE="1970-01-01T00:00:00Z"

echo "== PR #$N  $TITLE"
echo "   $URL"
echo "   state=$STATE draft=$DRAFT merge=$MERGE  $HEAD -> $BASE"
echo "   head $SHA pushed $SINCE"
if [ "$DRAFT" = "true" ]; then
  echo "   WARNING: draft. Review bots and some CI will not run. Ask before marking ready."
fi

echo
echo "== checks"
gh pr view "$PR" --repo "$REPO" --json statusCheckRollup \
  -q '.statusCheckRollup // [] | .[] | [(.status // .state // "?"),(.conclusion // .state // "-"),(.name // .context // "?"),(.completedAt // "")] | @tsv' \
  2>/dev/null | while IFS="$(printf '\t')" read -r ST CONC NAME DONE; do
    MARK="  "
    case "$CONC" in
      FAILURE|FAILING|ERROR|TIMED_OUT|CANCELLED|failure|error) MARK="->" ;;
    esac
    STALE=""
    if [ -n "$DONE" ] && [ "$DONE" \< "$SINCE" ]; then STALE="  (ran before the last push, stale)"; fi
    printf '%s %-10s %-12s %s%s\n' "$MARK" "$ST" "$CONC" "$NAME" "$STALE"
  done
echo "   (nothing listed above means no checks are reporting)"

echo
echo "== reviews"
gh pr view "$PR" --repo "$REPO" --json reviews \
  -q '.reviews // [] | .[] | [.author.login,.state,.submittedAt] | @tsv' 2>/dev/null \
  | while IFS="$(printf '\t')" read -r WHO ST WHEN; do
      NEW=""
      if [ -n "$WHEN" ] && [ "$WHEN" \> "$SINCE" ]; then NEW="  NEW"; fi
      printf '   %-20s %-18s %s%s\n' "$WHO" "$ST" "$WHEN" "$NEW"
    done

echo
echo "== inline review comments newer than the last push"
gh api --paginate "repos/$REPO/pulls/$N/comments" \
  --jq ".[] | select(.created_at > \"$SINCE\") | [.user.login, (.path // \"?\"), ((.line // .original_line // 0)|tostring), (.body | gsub(\"[\\r\\n]+\"; \" \") | .[0:120])] | @tsv" \
  2>/dev/null | while IFS="$(printf '\t')" read -r WHO PATHP LINE BODY; do
      printf '   %s  %s:%s\n     %s\n' "$WHO" "$PATHP" "$LINE" "$BODY"
    done

echo
echo "== conversation comments newer than the last push"
gh api --paginate "repos/$REPO/issues/$N/comments" \
  --jq ".[] | select(.created_at > \"$SINCE\") | [.user.login, (.body | gsub(\"[\\r\\n]+\"; \" \") | .[0:120])] | @tsv" \
  2>/dev/null | while IFS="$(printf '\t')" read -r WHO BODY; do
      printf '   %s\n     %s\n' "$WHO" "$BODY"
    done

echo
echo "Act only on what is listed as newer than the last push."
echo "Verify every finding against the source before changing code."
echo "Merging and closing are the human's call."
