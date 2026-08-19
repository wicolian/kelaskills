#!/usr/bin/env bash
# Symlink every skill in this repo into an agent skills directory.
#   ./install.sh                  -> ~/.claude/skills
#   ./install.sh ~/.agents/skills -> cross-runtime location
set -euo pipefail

DEST="${1:-$HOME/.claude/skills}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/skills" && pwd)"

mkdir -p "$DEST"
for d in "$SRC"/*/; do
  name="$(basename "$d")"
  target="$DEST/$name"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "skip  $name  (a real directory already exists there - not overwriting)"
    continue
  fi
  ln -sfn "$d" "$target"
  echo "link  $name  ->  $target"
done
echo
echo "Done. Restart your agent so it re-reads the skills directory."
