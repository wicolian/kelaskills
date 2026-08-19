#!/usr/bin/env bash
# Block until every spawned worker has a .done file. Prints status each interval.
set -uo pipefail
ROOT="${CC_FLEET_ROOT:-$PWD}"
IVL="${1:-60}"
R="$ROOT/artifacts/reports"; S="$ROOT/artifacts/panes"
while :; do
  left=0
  shopt -s nullglob
  for f in "$S"/*.pane; do n=$(basename "$f" .pane); [ -f "$R/$n.done" ] || left=$((left+1)); done
  "$(dirname "$0")/fleet-status.sh"
  [ "$left" -eq 0 ] && { echo "all workers done"; break; }
  echo "--- $left still running, sleeping ${IVL}s ---"
  sleep "$IVL"
done
