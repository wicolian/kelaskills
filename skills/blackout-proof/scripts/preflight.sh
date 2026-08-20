#!/usr/bin/env bash
# preflight.sh - refuse to go dark until the guards are real.
# Exit 0 only when every check passes.
set -uo pipefail
ROOT="${WD_ROOT:-${AGENT_FLEET_ROOT:-${CC_FLEET_ROOT:-$PWD}}}"
ART="$ROOT/artifacts"
FAIL=0
ok()   { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=1; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; }

echo "preflight for $ROOT"
echo

# 1. watchdog alive, with a fresh heartbeat
if [ -d "$ART/watchdog.lock" ] && kill -0 "$(cat "$ART/watchdog.lock/pid" 2>/dev/null)" 2>/dev/null; then
  beat=$(cat "$ART/watchdog.heartbeat" 2>/dev/null || echo 0)
  age=$(( $(date +%s) - beat ))
  if [ "$age" -lt 1200 ]; then ok "watchdog alive (pid $(cat "$ART/watchdog.lock/pid"), beat ${age}s ago)"
  else bad "watchdog holds a lock but has not beaten in ${age}s - it is wedged"; fi
else
  bad "watchdog is NOT running - start scripts/watchdog.sh"
fi

# 2. the report is derived, not transcribed
if [ -n "${PF_REPORT:-}" ] && [ -f "$PF_REPORT" ]; then
  age=$(( $(date +%s) - $(stat -f %m "$PF_REPORT" 2>/dev/null || stat -c %Y "$PF_REPORT") ))
  if [ "$age" -lt 900 ]; then ok "report regenerated ${age}s ago"
  else bad "report is ${age}s stale - the refresh loop is not running"; fi
else
  warn "set PF_REPORT=<path> so this can check the report is being regenerated"
fi

# 3. handoff exists and is not a stub
if [ -f "$ROOT/RESUME.md" ]; then
  if [ "$(wc -l < "$ROOT/RESUME.md" | tr -d ' ')" -ge 10 ]; then ok "RESUME.md present"
  else bad "RESUME.md is a stub - it must name the first thing to do"; fi
else bad "no RESUME.md - nothing can pick this up"; fi

# 4. task ledger on disk
if [ -n "${PF_LEDGER:-}" ] && [ -f "$PF_LEDGER" ]; then ok "task ledger at $PF_LEDGER"
elif [ -d "$ROOT/prompts" ]; then ok "task state derivable from prompts/ + reports/"
else bad "no task ledger and no prompts/ - a resume would have to guess"; fi

# 5. uncommitted work snapshotted
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  if [ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]; then
    ok "tracked tree clean"
  elif ls "$ART"/snapshots/*.patch >/dev/null 2>&1; then
    newest=$(ls -t "$ART"/snapshots/*.patch | head -1)
    ok "tree dirty but snapshotted ($(basename "$newest"))"
  else
    bad "tracked tree is dirty and there is no snapshot in $ART/snapshots/"
  fi
fi

# 6. disk headroom
avail=$(df -m "$ROOT" | awk 'NR==2{print $4}')
if [ "${avail:-0}" -gt 2048 ]; then ok "disk headroom ${avail}MB"
else bad "only ${avail}MB free - logs and screenshots will fill it"; fi

# 7. which limit, and when does it reset
if [ -f "$ROOT/LIMITS.md" ]; then ok "LIMITS.md records which cap you are near"
else warn "no LIMITS.md - write down which limit you are near and its real reset"; fi

echo
if [ "$FAIL" -eq 0 ]; then echo "SAFE TO GO DARK"; else echo "NOT SAFE - fix the FAILs above"; exit 1; fi
