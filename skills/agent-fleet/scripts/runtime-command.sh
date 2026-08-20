#!/usr/bin/env bash
# Print the interactive launch command for a supported coding-agent runtime.
set -euo pipefail
[ "$#" -ge 1 ] || { echo "usage: $0 RUNTIME [MODEL]" >&2; exit 2; }
RUNTIME="$1"; MODEL="${2:-default}"

if [ -n "${AGENT_FLEET_COMMAND:-}" ]; then
  printf '%s\n' "$AGENT_FLEET_COMMAND"
  exit 0
fi

q() { printf '%q' "$1"; }
with_model() {
  local command="$1" flag="$2"
  if [ -n "$MODEL" ] && [ "$MODEL" != "default" ] && [ "$MODEL" != "-" ]; then
    printf '%s %s %s\n' "$command" "$flag" "$(q "$MODEL")"
  else
    printf '%s\n' "$command"
  fi
}

case "$RUNTIME" in
  claude|claude-code) with_model "claude --dangerously-skip-permissions" "--model" ;;
  codex) with_model "codex --dangerously-bypass-approvals-and-sandbox" "--model" ;;
  cursor)
    if command -v cursor-agent >/dev/null 2>&1; then cursor_bin=cursor-agent; else cursor_bin=agent; fi
    with_model "$cursor_bin --yolo" "--model"
    ;;
  hermes|hermes-agent) with_model "hermes --yolo" "--model" ;;
  pi) with_model "pi" "--model" ;;
  t3|t3-code)
    provider="${T3_PROVIDER_RUNTIME:-}"
    [ -n "$provider" ] || {
      echo "T3 Code wraps provider CLIs. Set T3_PROVIDER_RUNTIME to claude-code, codex, or cursor." >&2
      exit 2
    }
    [ "$provider" != "t3" ] && [ "$provider" != "t3-code" ] || { echo "T3_PROVIDER_RUNTIME cannot be t3-code" >&2; exit 2; }
    exec "$0" "$provider" "$MODEL"
    ;;
  *) echo "unsupported runtime: $RUNTIME" >&2; exit 2 ;;
esac
