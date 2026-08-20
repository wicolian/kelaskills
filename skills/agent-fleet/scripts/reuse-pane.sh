#!/usr/bin/env bash
# reuse-pane.sh PANE NAME RUNTIME MODEL PROMPT_FILE [CWD]
# Start a fresh interactive coding-agent worker in a finished pane.
set -euo pipefail
[ "${HERDR_ENV:-}" = "1" ] || { echo "not inside herdr"; exit 1; }
[ "$#" -ge 5 ] || { echo "usage: $0 PANE NAME RUNTIME MODEL PROMPT_FILE [CWD]" >&2; exit 2; }
PANE="$1"; NAME="$2"; RUNTIME="$3"; MODEL="$4"
PROMPT="$(cd "$(dirname "$5")" && pwd)/$(basename "$5")"
CWD="${6:-$PWD}"
ROOT="${AGENT_FLEET_ROOT:-${CC_FLEET_ROOT:-$PWD}}"
REPORTS="$ROOT/artifacts/reports"; STATE="$ROOT/artifacts/panes"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$REPORTS" "$STATE"; echo "$PANE" > "$STATE/$NAME.pane"
rm -f "$REPORTS/$NAME.md" "$REPORTS/$NAME.done"
MSG="You are worker $NAME. Read $PROMPT and do exactly what it says, in full, to the end. Do not stop early and do not ask me anything. When you are completely finished, save your full final report to $REPORTS/$NAME.md and then run: touch $REPORTS/$NAME.done"
CMD="$("$SCRIPT_DIR/runtime-command.sh" "$RUNTIME" "$MODEL")"
CWD_Q=$(printf '%q' "$CWD")
herdr pane send-keys "$PANE" "ctrl+c" >/dev/null 2>&1 || true
sleep 1
herdr pane run "$PANE" "clear; cd $CWD_Q && $CMD"
if [ -n "${AGENT_READY_PATTERN:-}" ]; then
  herdr wait output "$PANE" --match "$AGENT_READY_PATTERN" --timeout "${AGENT_READY_TIMEOUT:-90000}" >/dev/null 2>&1 || true
fi
sleep "${AGENT_STARTUP_WAIT:-8}"
herdr pane send-text "$PANE" "$MSG"; sleep 1; herdr pane send-keys "$PANE" Enter
echo "$NAME -> pane $PANE (reused, runtime $RUNTIME, model $MODEL)"
