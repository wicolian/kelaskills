#!/usr/bin/env bash
# refresh-loop.sh SECONDS COMMAND...
# Re-run COMMAND every SECONDS, forever, logging failures but never dying.
# Use it for the status report, so the page stays true with nothing driving it.
#   refresh-loop.sh 180 ./make-report.sh
set -uo pipefail
SECS="${1:?usage: refresh-loop.sh SECONDS COMMAND...}"; shift
[ $# -gt 0 ] || { echo "no command given"; exit 2; }
echo "refresh-loop: every ${SECS}s -> $*"
while :; do
  if ! "$@"; then echo "$(date '+%H:%M:%S') refresh FAILED (rc=$?) - continuing"; fi
  sleep "$SECS"
done
