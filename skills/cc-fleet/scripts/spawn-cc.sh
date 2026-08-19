#!/usr/bin/env bash
# spawn-cc.sh NAME MODEL PROMPT_FILE [TAB] [CWD]
# Spawns an INTERACTIVE claude worker in its own herdr pane.
# Reports land in $CC_FLEET_ROOT/artifacts/reports/NAME.md, finished marked by NAME.done
set -euo pipefail
[ "${HERDR_ENV:-}" = "1" ] || { echo "not inside herdr (HERDR_ENV != 1)"; exit 1; }
NAME="$1"; MODEL="$2"
PROMPT="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
TAB="${4:-workers}"; CWD="${5:-$PWD}"
ROOT="${CC_FLEET_ROOT:-$PWD}"
WS="${HERDR_WORKSPACE_ID:?}"
REPORTS="$ROOT/artifacts/reports"; STATE="$ROOT/artifacts/panes"
mkdir -p "$REPORTS" "$STATE"
pid() { python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["pane"]["pane_id"])'; }
rid() { python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["root_pane"]["pane_id"])'; }

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

MSG="You are worker $NAME. Read $PROMPT and do exactly what it says, in full, to the end. Do not stop early and do not ask me anything. When you are completely finished, use the Write tool to save your full final report to $REPORTS/$NAME.md and then run: touch $REPORTS/$NAME.done"

herdr pane run "$PANE" "cd '$CWD' && claude --dangerously-skip-permissions --model $MODEL"
herdr wait output "$PANE" --match "bypass permissions on" --timeout 90000 >/dev/null 2>&1 || true
sleep 8
herdr pane send-text "$PANE" "$MSG"; sleep 1; herdr pane send-keys "$PANE" Enter; sleep 3
if ! herdr pane read "$PANE" --source visible --lines 12 | grep -q "esc to interrupt"; then
  echo "  first send did not land, retrying $NAME"
  sleep 5
  herdr pane send-text "$PANE" "$MSG"; sleep 1; herdr pane send-keys "$PANE" Enter
fi
echo "$NAME -> pane $PANE (interactive, model $MODEL, tab $TAB)"
