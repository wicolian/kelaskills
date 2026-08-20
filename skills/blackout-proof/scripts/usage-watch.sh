#!/usr/bin/env bash
# usage-watch.sh [SECONDS]
# A pane a passing human can read: how much quota is left, and is the guard alive.
# Purely informational - never let anything depend on parsing this.
set -uo pipefail
SECS="${1:-300}"
ROOT="${WD_ROOT:-${AGENT_FLEET_ROOT:-${CC_FLEET_ROOT:-$PWD}}}"
ART="$ROOT/artifacts"
while :; do
  clear
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') ==================================="
  echo
  echo "-- watchdog"
  if [ -d "$ART/watchdog.lock" ] && kill -0 "$(cat "$ART/watchdog.lock/pid" 2>/dev/null)" 2>/dev/null; then
    beat=$(cat "$ART/watchdog.heartbeat" 2>/dev/null || echo 0)
    age=$(( $(date +%s) - beat ))
    echo "   ALIVE  pid $(cat "$ART/watchdog.lock/pid")  last beat ${age}s ago"
  else
    echo "   *** NOT RUNNING ***"
  fi
  echo
  echo "-- progress"
  d=$(ls "$ART"/reports/*.done 2>/dev/null | wc -l | tr -d ' ')
  t=$(ls "$ROOT"/prompts/*.md   2>/dev/null | wc -l | tr -d ' ')
  echo "   $d / $t tasks done"
  echo
  echo "-- last 8 watchdog lines"
  tail -8 "$ART/watchdog.log" 2>/dev/null | sed 's/^/   /'
  echo
  echo "-- blackouts so far: $(grep -c BLACKOUT "$ART/watchdog.log" 2>/dev/null || echo 0)"
  echo "-- restarts so far:  $(grep -c 'starting orchestrator' "$ART/watchdog.log" 2>/dev/null || echo 0)"
  sleep "$SECS"
done
