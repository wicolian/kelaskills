#!/usr/bin/env bash
# Symlink every skill into one or more agent skill directories.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/skills" && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ./install.sh                         Install for every supported agent
  ./install.sh --agent codex          Install for one agent (repeatable)
  ./install.sh /custom/skills/path    Install into an explicit directory

Agents: claude-code, codex, cursor, t3-code, hermes-agent, pi, universal, all

T3 Code runs provider CLIs. Its preset installs the universal skills plus the
Claude Code, Codex, and Cursor copies that its providers discover.
EOF
}

destinations_for() {
  case "$1" in
    claude|claude-code) printf '%s\n' "$HOME/.claude/skills" ;;
    codex) printf '%s\n' "${CODEX_HOME:-$HOME/.codex}/skills" ;;
    cursor) printf '%s\n' "$HOME/.cursor/skills" ;;
    hermes|hermes-agent) printf '%s\n' "$HOME/.hermes/skills" ;;
    pi) printf '%s\n' "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills" ;;
    universal) printf '%s\n' "$HOME/.agents/skills" ;;
    t3|t3-code)
      printf '%s\n' \
        "$HOME/.agents/skills" \
        "$HOME/.claude/skills" \
        "${CODEX_HOME:-$HOME/.codex}/skills" \
        "$HOME/.cursor/skills"
      ;;
    all)
      printf '%s\n' \
        "$HOME/.agents/skills" \
        "$HOME/.claude/skills" \
        "${CODEX_HOME:-$HOME/.codex}/skills" \
        "$HOME/.cursor/skills" \
        "$HOME/.hermes/skills" \
        "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills"
      ;;
    *) echo "unknown agent: $1" >&2; usage >&2; return 2 ;;
  esac
}

install_into() {
  local dest="$1" d name target
  mkdir -p "$dest"
  for d in "$SRC"/*/; do
    [ -f "$d/SKILL.md" ] || continue
    name="$(basename "$d")"
    target="$dest/$name"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      echo "skip  $name  (a real directory already exists at $target)"
      continue
    fi
    ln -sfn "$d" "$target"
    echo "link  $name  ->  $target"
  done
}

if [ "$#" -eq 0 ]; then
  set -- --agent all
elif [[ "$1" != -* ]]; then
  install_into "$1"
  echo
  echo "Done. Restart your agent so it re-reads the skills directory."
  exit 0
fi

agents=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --agent)
      [ "$#" -ge 2 ] || { echo "--agent needs a value" >&2; exit 2; }
      agents+=("$2"); shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ "${#agents[@]}" -gt 0 ] || agents=(all)
for agent in "${agents[@]}"; do
  while IFS= read -r dest; do install_into "$dest"; done < <(destinations_for "$agent")
done

echo
echo "Done. Restart your agent so it re-reads the skills directory."
