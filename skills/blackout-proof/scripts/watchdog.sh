#!/usr/bin/env bash
# watchdog.sh - keep a long unattended run alive across quota blackouts.
#
# A plain shell loop on purpose. It must survive the agent session dying, so it
# uses no agent, and nothing it needs to make a decision costs quota.
#
# Every WD_INTERVAL seconds:
#   1. is there work left?          no  -> exit 0, cleanly
#   2. is the fleet still alive?    yes -> do nothing
#   3. fleet empty, work remains    -> probe quota, then restart an orchestrator
#      quota gone                   -> exponential backoff, keep retrying
#
# Configure with env vars. The defaults assume a cc-fleet layout.
#
#   WD_ROOT            programme root            (default: $CC_FLEET_ROOT or $PWD)
#   WD_WORK_REMAINING  cmd printing an integer   (default: ledger TODO count)
#   WD_FLEET_SIZE      cmd printing an integer   (default: running workers)
#   WD_START           cmd that starts one orchestrator  (REQUIRED)
#   WD_PROBE           cmd, exit 0 if quota is available (default: claude probe)
#   WD_INTERVAL        seconds between checks     (default: 600)
#   WD_MAX_RESTARTS    give up after this many    (default: 12)
#   WD_BACKOFF_MAX     cap on blackout backoff    (default: 1800)
#   WD_BACKOFF_START   first blackout sleep       (default: 60)
#   WD_COOLDOWN        quiet period after a restart (default: max(2*interval,300))
#
# Stop it with:  touch "$WD_ROOT/artifacts/watchdog.stop"

set -uo pipefail

ROOT="${WD_ROOT:-${CC_FLEET_ROOT:-$PWD}}"
ART="$ROOT/artifacts"; mkdir -p "$ART"
LOG="$ART/watchdog.log"
LOCK="$ART/watchdog.lock"
BEAT="$ART/watchdog.heartbeat"
STOP="$ART/watchdog.stop"
REPORTS="$ART/reports"

INTERVAL="${WD_INTERVAL:-600}"
MAX_RESTARTS="${WD_MAX_RESTARTS:-12}"
BACKOFF_MAX="${WD_BACKOFF_MAX:-1800}"
BACKOFF_START="${WD_BACKOFF_START:-60}"
# Clamp the starting value too, or the cap cannot shorten the first sleep.
[ "$BACKOFF_START" -gt "$BACKOFF_MAX" ] && BACKOFF_START="$BACKOFF_MAX"
# After a restart, ignore an empty fleet for this long. A freshly started
# orchestrator needs time to spawn workers; without a floor here a short
# interval restarts it repeatedly and burns the restart budget in seconds.
COOLDOWN="${WD_COOLDOWN:-$(( INTERVAL * 2 > 300 ? INTERVAL * 2 : 300 ))}"

log() { printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }

# Bash defers a trap until the current foreground command finishes, so a plain
# `sleep 600` makes the watchdog take up to ten minutes to answer a signal.
# Backgrounding the sleep and waiting on it makes the trap fire immediately.
nap() { sleep "$1" & SLEEP_PID=$!; wait "$SLEEP_PID" 2>/dev/null; }

# --- single watchdog, enforced by the filesystem ----------------------------
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -f "$LOCK/pid" ] && kill -0 "$(cat "$LOCK/pid")" 2>/dev/null; then
    echo "watchdog already running as PID $(cat "$LOCK/pid")"; exit 3
  fi
  log "removing a stale lock from PID $(cat "$LOCK/pid" 2>/dev/null || echo '?')"
  rm -rf "$LOCK"; mkdir "$LOCK" || { echo "cannot take lock"; exit 3; }
fi
echo $$ > "$LOCK/pid"
cleanup() {
  # Only release a lock we actually own. Removing it unconditionally lets a
  # second watchdog start while the first is still running, and then they
  # restart each other's orchestrators.
  if [ "$(cat "$LOCK/pid" 2>/dev/null)" = "$$" ]; then rm -rf "$LOCK"; fi
  log "watchdog exiting (PID $$)"
}
# A signal trap that only runs cleanup does NOT stop the loop: the handler
# returns and the watchdog keeps going, having already released its lock.
# It must exit explicitly.
trap 'kill "${SLEEP_PID:-0}" 2>/dev/null; cleanup; exit 0' INT TERM
trap cleanup EXIT

[ -n "${WD_START:-}" ] || { log "FATAL: WD_START is not set - nothing to restart"; exit 2; }

# --- defaults that fit a cc-fleet layout ------------------------------------
work_remaining() {
  if [ -n "${WD_WORK_REMAINING:-}" ]; then bash -lc "$WD_WORK_REMAINING"; return; fi
  # every task that has a prompt but no .done marker
  local total done
  total=$(ls "$ROOT"/prompts/*.md 2>/dev/null | wc -l | tr -d ' ')
  done=$(ls "$REPORTS"/*.done 2>/dev/null | wc -l | tr -d ' ')
  echo $(( total - done ))
}

fleet_size() {
  if [ -n "${WD_FLEET_SIZE:-}" ]; then bash -lc "$WD_FLEET_SIZE"; return; fi
  # panes herdr still considers busy
  herdr pane list 2>/dev/null | python3 -c '
import sys,json
try: p=json.load(sys.stdin)["result"]["panes"]
except Exception: print(0); raise SystemExit
print(sum(1 for x in p if x.get("agent_status") in ("working","running")))' 2>/dev/null || echo 0
}

# Probe must be cheap and must fail *fast* when the quota is gone.
quota_ok() {
  if [ -n "${WD_PROBE:-}" ]; then bash -lc "$WD_PROBE" >/dev/null 2>&1; return $?; fi
  local out
  out=$(claude -p 'reply with exactly: ok' --model haiku 2>&1)
  local rc=$?
  if printf '%s' "$out" | grep -qiE 'spend limit|usage limit|rate limit|quota|too many requests|429|resets at'; then
    return 1
  fi
  return $rc
}

# --- main loop ---------------------------------------------------------------
log "watchdog up (PID $$) interval=${INTERVAL}s cooldown=${COOLDOWN}s max_restarts=$MAX_RESTARTS root=$ROOT"
restarts=0
backoff=$BACKOFF_START
cooldown_until=0

while :; do
  date '+%s' > "$BEAT"

  if [ -f "$STOP" ]; then log "stop file present - exiting"; exit 0; fi

  remaining=$(work_remaining 2>/dev/null || echo "?")
  if [ "$remaining" = "0" ]; then
    log "all work complete - nothing left to guard. exiting."
    exit 0
  fi

  live=$(fleet_size 2>/dev/null || echo 0)
  now=$(date '+%s')

  if [ "${live:-0}" -gt 0 ]; then
    log "ok: $live worker(s) alive, $remaining task(s) remaining"
    backoff=$BACKOFF_START
  elif [ "$now" -lt "$cooldown_until" ]; then
    log "fleet empty but inside restart cooldown ($((cooldown_until - now))s left)"
  else
    log "fleet EMPTY with $remaining task(s) remaining - checking quota"
    if quota_ok; then
      if [ "$restarts" -ge "$MAX_RESTARTS" ]; then
        log "FATAL: hit max restarts ($MAX_RESTARTS). Something is crash-looping."
        log "       Not burning more quota. A human needs to look at $LOG."
        exit 1
      fi
      restarts=$((restarts + 1))
      log "quota available - starting orchestrator (restart $restarts/$MAX_RESTARTS)"
      bash -lc "$WD_START" >>"$LOG" 2>&1 &
      cooldown_until=$(( now + COOLDOWN ))
      backoff=$BACKOFF_START
    else
      log "BLACKOUT: quota unavailable. backing off ${backoff}s (retry keeps going)"
      nap "$backoff"
      backoff=$(( backoff * 2 )); [ "$backoff" -gt "$BACKOFF_MAX" ] && backoff="$BACKOFF_MAX"
      continue
    fi
  fi

  nap "$INTERVAL"
done
