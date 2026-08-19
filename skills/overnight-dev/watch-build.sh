#!/usr/bin/env bash
#
# Poll an AWS Amplify job to a terminal state and, on failure, print the
# tail of the log that actually failed.
#
#   watch-build.sh              # newest job on develop
#   watch-build.sh 83           # a specific job id
#   watch-build.sh --commit <sha>   # the job built from a commit
#
# Exit: 0 SUCCEED, 1 FAILED/CANCELLED, 2 gave up waiting.
set -uo pipefail

# Required. Never hardcode an app id: the same AWS account usually holds prod,
# UAT and preprod apps, and one wrong id deploys to paying customers.
APP="${AMPLIFY_APP_ID:?set AMPLIFY_APP_ID to the dev app id}"
BRANCH=develop
POLL=20          # seconds between polls; a build runs ~15 min
MAX_MIN=40       # give up after this
TAIL=120         # log lines to print on failure

q() { aws amplify "$@" 2>/dev/null; }

resolve_job() {
  if [[ "${1:-}" == "--commit" ]]; then
    q list-jobs --app-id "$APP" --branch-name "$BRANCH" --max-results 20 \
      --query "jobSummaries[?commitId=='${2:-}'].jobId | [0]" --output text
  elif [[ -n "${1:-}" ]]; then
    echo "$1"
  else
    q list-jobs --app-id "$APP" --branch-name "$BRANCH" --max-results 1 \
      --query 'jobSummaries[0].jobId' --output text
  fi
}

JOB=$(resolve_job "$@")
if [[ -z "$JOB" || "$JOB" == "None" ]]; then
  echo "watch-build: could not resolve a job. Is the push through, and is autoBuild on?" >&2
  exit 2
fi

COMMIT=$(q list-jobs --app-id "$APP" --branch-name "$BRANCH" --max-results 20 \
  --query "jobSummaries[?jobId=='$JOB'].commitId | [0]" --output text)
echo "watch-build: app=$APP branch=$BRANCH job=$JOB commit=${COMMIT:0:12}"
echo "watch-build: expect ~15 min; polling every ${POLL}s"

deadline=$(( $(date +%s) + MAX_MIN * 60 ))
last=""
while :; do
  status=$(q get-job --app-id "$APP" --branch-name "$BRANCH" --job-id "$JOB" \
    --query 'job.summary.status' --output text)
  steps=$(q get-job --app-id "$APP" --branch-name "$BRANCH" --job-id "$JOB" \
    --query 'job.steps[].[stepName,status]' --output text | tr '\t' '=' | tr '\n' ' ')

  line="$status | $steps"
  [[ "$line" != "$last" ]] && { printf '%s  %s\n' "$(date +%H:%M:%S)" "$line"; last="$line"; }

  case "$status" in
    SUCCEED)
      echo "watch-build: SUCCEED — ${DEPLOY_URL:-check the Amplify console}"
      echo "watch-build: next, verify the flow (force the UI flag - it is not the default)"
      exit 0 ;;
    FAILED|CANCELLED)
      echo "watch-build: $status — failing log tail below"
      for step in BUILD DEPLOY; do
        st=$(q get-job --app-id "$APP" --branch-name "$BRANCH" --job-id "$JOB" \
          --query "job.steps[?stepName=='$step'].status | [0]" --output text)
        [[ "$st" == "FAILED" ]] || continue
        url=$(q get-job --app-id "$APP" --branch-name "$BRANCH" --job-id "$JOB" \
          --query "job.steps[?stepName=='$step'].logUrl | [0]" --output text)
        echo "───── $step (last $TAIL lines) ─────"
        # logUrl is a short-lived presigned URL: fetch now, never persist it
        [[ -n "$url" && "$url" != "None" ]] && curl -s "$url" | tail -n "$TAIL" \
          || echo "(no log available for $step)"
      done
      exit 1 ;;
    None|"")
      echo "watch-build: no status for job $JOB" >&2; exit 2 ;;
  esac

  (( $(date +%s) > deadline )) && {
    echo "watch-build: still $status after ${MAX_MIN}m — giving up waiting (build may still finish)" >&2
    exit 2; }
  sleep "$POLL"
done
