#!/usr/bin/env bash
# spawn-agent.sh NAME RUNTIME MODEL PROMPT_FILE [TAB] [CWD]
# Spawn an interactive coding-agent worker in a herdr pane.
set -euo pipefail
[ "${HERDR_ENV:-}" = "1" ] || { echo "not inside herdr (HERDR_ENV != 1)"; exit 1; }
[ "$#" -ge 4 ] || { echo "usage: $0 NAME RUNTIME MODEL PROMPT_FILE [TAB] [CWD]" >&2; exit 2; }
NAME="$1"; RUNTIME="$2"; MODEL="$3"
PROMPT="$(cd "$(dirname "$4")" && pwd)/$(basename "$4")"
TAB="${5:-workers}"; CWD="${6:-$PWD}"
ROOT="${AGENT_FLEET_ROOT:-${CC_FLEET_ROOT:-$PWD}}"
WS="${HERDR_WORKSPACE_ID:?}"
REPORTS="$ROOT/artifacts/reports"; STATE="$ROOT/artifacts/panes"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$REPORTS" "$STATE"
pid() { python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["pane"]["pane_id"])'; }
rid() { python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])'; }
visible_signature() { herdr pane read "$1" --source visible --lines 20 2>/dev/null | cksum || true; }

BASEFILE="$STATE/tab-$TAB.base"; COUNTFILE="$STATE/tab-$TAB.count"
if [ ! -f "$BASEFILE" ]; then
  herdr tab create --workspace "$WS" --label "$TAB" | rid > "$BASEFILE"; echo 0 > "$COUNTFILE"
fi
BASE=$(cat "$BASEFILE"); COUNT=$(cat "$COUNTFILE")
if [ "$COUNT" -eq 0 ]; then PANE="$BASE"; else
  DIR=right; [ $((COUNT % 2)) -eq 1 ] && DIR=down
  PANE=$(herdr pane split "$BASE" --direction "$DIR" --no-focus | pid)
fi
echo $((COUNT + 1)) > "$COUNTFILE"; echo "$PANE" > "$STATE/$NAME.pane"
rm -f "$REPORTS/$NAME.md" "$REPORTS/$NAME.done"

MSG="You are worker $NAME. Read $PROMPT and do exactly what it says, in full, to the end. Do not stop early and do not ask me anything. When you are completely finished, save your full final report to $REPORTS/$NAME.md and then run: touch $REPORTS/$NAME.done"
CMD="$("$SCRIPT_DIR/runtime-command.sh" "$RUNTIME" "$MODEL")"
CWD_Q=$(printf '%q' "$CWD")

herdr pane run "$PANE" "cd $CWD_Q && $CMD"
if [ -n "${AGENT_READY_PATTERN:-}" ]; then
  herdr wait output "$PANE" --match "$AGENT_READY_PATTERN" --timeout "${AGENT_READY_TIMEOUT:-90000}" >/dev/null 2>&1 || true
fi
sleep "${AGENT_STARTUP_WAIT:-8}"
before=$(visible_signature "$PANE")
herdr pane send-text "$PANE" "$MSG"; sleep 1; herdr pane send-keys "$PANE" Enter; sleep 3
after=$(visible_signature "$PANE")
if [ "$before" = "$after" ]; then
  echo "  first send showed no visible change, retrying $NAME"
  sleep 5
  herdr pane send-text "$PANE" "$MSG"; sleep 1; herdr pane send-keys "$PANE" Enter
fi
echo "$NAME -> pane $PANE (runtime $RUNTIME, model $MODEL, tab $TAB)"
