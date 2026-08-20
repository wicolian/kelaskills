#!/usr/bin/env bash
# Run the smallest practical provider call for quota and authentication checks.
set -uo pipefail
RUNTIME="${1:-${AGENT_RUNTIME:-claude-code}}"
MODEL="${AGENT_PROBE_MODEL:-default}"
PROMPT="reply with exactly: ok"

case "$RUNTIME" in
  claude|claude-code)
    [ "$MODEL" != "default" ] || MODEL=haiku
    claude -p "$PROMPT" --model "$MODEL"
    ;;
  codex)
    if [ -n "$MODEL" ] && [ "$MODEL" != "default" ] && [ "$MODEL" != "-" ]; then
      codex exec --model "$MODEL" --ephemeral --skip-git-repo-check "$PROMPT"
    else
      codex exec --ephemeral --skip-git-repo-check "$PROMPT"
    fi
    ;;
  cursor)
    if command -v cursor-agent >/dev/null 2>&1; then cursor_bin=cursor-agent; else cursor_bin=agent; fi
    if [ -n "$MODEL" ] && [ "$MODEL" != "default" ] && [ "$MODEL" != "-" ]; then
      "$cursor_bin" -p "$PROMPT" --model "$MODEL" --output-format text
    else
      "$cursor_bin" -p "$PROMPT" --output-format text
    fi
    ;;
  hermes|hermes-agent)
    if [ -n "$MODEL" ] && [ "$MODEL" != "default" ] && [ "$MODEL" != "-" ]; then
      hermes --model "$MODEL" -Q chat -q "$PROMPT"
    else
      hermes -Q chat -q "$PROMPT"
    fi
    ;;
  pi)
    if [ -n "$MODEL" ] && [ "$MODEL" != "default" ] && [ "$MODEL" != "-" ]; then
      pi --model "$MODEL" --print "$PROMPT"
    else
      pi --print "$PROMPT"
    fi
    ;;
  t3|t3-code)
    provider="${T3_PROVIDER_RUNTIME:-}"
    [ -n "$provider" ] || { echo "set T3_PROVIDER_RUNTIME to claude-code, codex, or cursor" >&2; exit 2; }
    [ "$provider" != "t3" ] && [ "$provider" != "t3-code" ] || { echo "T3_PROVIDER_RUNTIME cannot be t3-code" >&2; exit 2; }
    exec "$0" "$provider"
    ;;
  *) echo "unsupported runtime: $RUNTIME" >&2; exit 2 ;;
esac
