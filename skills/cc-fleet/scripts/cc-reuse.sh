#!/usr/bin/env bash
# cc-reuse.sh PANE NAME MODEL PROMPT_FILE [CWD]
# Start a fresh interactive claude worker in a pane whose previous worker has finished.
set -euo pipefail
[ "${HERDR_ENV:-}" = "1" ] || { echo "not inside herdr"; exit 1; }
PANE="$1"; NAME="$2"; MODEL="$3"
PROMPT="$(cd "$(dirname "$4")" && pwd)/$(basename "$4")"
CWD="${5:-$PWD}"
ROOT="${CC_FLEET_ROOT:-$PWD}"
REPORTS="$ROOT/artifacts/reports"; STATE="$ROOT/artifacts/panes"
mkdir -p "$REPORTS" "$STATE"; echo "$PANE" > "$STATE/$NAME.pane"
rm -f "$REPORTS/$NAME.md" "$REPORTS/$NAME.done"
MSG="You are worker $NAME. Read $PROMPT and do exactly what it says, in full, to the end. Do not stop early and do not ask me anything. When you are completely finished, use the Write tool to save your full final report to $REPORTS/$NAME.md and then run: touch $REPORTS/$NAME.done"
herdr pane send-keys "$PANE" "ctrl+c" >/dev/null 2>&1 || true
sleep 1
herdr pane run "$PANE" "clear; cd '$CWD' && claude --dangerously-skip-permissions --model $MODEL"
herdr wait output "$PANE" --match "bypass permissions on" --timeout 90000 >/dev/null 2>&1 || true
sleep 8
herdr pane send-text "$PANE" "$MSG"; sleep 1; herdr pane send-keys "$PANE" Enter; sleep 3
if ! herdr pane read "$PANE" --source visible --lines 12 | grep -q "esc to interrupt"; then
  echo "  first send did not land, retrying $NAME"; sleep 5
  herdr pane send-text "$PANE" "$MSG"; sleep 1; herdr pane send-keys "$PANE" Enter
fi
echo "$NAME -> pane $PANE (reused, interactive, model $MODEL)"
