#!/usr/bin/env bash
# One line per worker: NAME  RUNNING|DONE  bytes  pane  agent_status
set -uo pipefail
ROOT="${CC_FLEET_ROOT:-$PWD}"
R="$ROOT/artifacts/reports"; S="$ROOT/artifacts/panes"
STATUS=$(herdr pane list 2>/dev/null | python3 -c '
import sys,json
try: d=json.load(sys.stdin)["result"]["panes"]
except Exception: d=[]
print("\n".join("%s %s"%(p["pane_id"],p.get("agent_status","-")) for p in d))' 2>/dev/null || true)
shopt -s nullglob
for f in "$S"/*.pane; do
  n=$(basename "$f" .pane); pane=$(cat "$f")
  if [ -f "$R/$n.done" ]; then s=DONE; else s=RUNNING; fi
  b=0; [ -f "$R/$n.md" ] && b=$(wc -c < "$R/$n.md" | tr -d ' ')
  a=$(echo "$STATUS" | awk -v p="$pane" '$1==p{print $2}')
  printf '%-12s %-8s %9s %-8s %s\n' "$n" "$s" "${b}B" "$pane" "${a:--}"
done
