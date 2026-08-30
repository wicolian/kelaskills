#!/usr/bin/env bash
# preflight.sh - report kelaskills install state and dependency state.
#
# For every runtime skill directory: does it exist, how many kelaskills skills
# are in it, and is each one a real directory or a symlink. Then the shared
# dependencies, and what each missing one disables.
#
# READ ONLY. It installs nothing, modifies nothing, deletes nothing.
# It never prints a token, and never prints the body of `gh auth status`.
#
# Usage:  preflight.sh
# Exit:   0 always. This reports; it does not gate.
set -uo pipefail

# Skills that belong to this pack. Used to tell a kelaskills install apart from
# whatever else lives in the same directory. Extended automatically below when
# this script is running from a clone of the repo.
KNOWN="agent-fleet agent-retro agents-md babysit-pr blackout-proof
context-archaeology file-pr fleet-sync graph-engineering herdr obsidian-graph
overnight-dev right-question setup-kelaskills skill-authoring skill-tags
stacked-prs switch-env sync-main whatwillmattdo work-order-report"

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SELF=""
if [ -n "$SELF" ] && [ -f "$SELF/../../../TAGS.md" ]; then
  SKILLS_ROOT="$(cd "$SELF/../.." && pwd)"
  for d in "$SKILLS_ROOT"/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"
    case " $KNOWN " in *" $n "*) ;; *) KNOWN="$KNOWN $n" ;; esac
  done
fi
KNOWN="$(printf '%s\n' $KNOWN | sort -u | tr '\n' ' ')"

# Print a path with $HOME collapsed to ~, so output is safe to paste.
tilde() { case "$1" in "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;; *) printf '%s' "$1" ;; esac; }

runtimes() {
  cat <<EOF
Claude Code|$HOME/.claude/skills
Codex|${CODEX_HOME:-$HOME/.codex}/skills
Cursor|$HOME/.cursor/skills
Hermes Agent|$HOME/.hermes/skills
Pi coding agent|${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills
Cross-runtime and T3|$HOME/.agents/skills
EOF
}

MISSING=""
add_missing() { MISSING="$MISSING$1"$'\n'; }

echo "== kelaskills preflight =="
echo "   read only. nothing here installs, changes or deletes anything."
echo

echo "== runtime skill directories =="
TOTAL_FOUND=0
DIRS_WITH_ANY=0
while IFS='|' read -r label dir; do
  [ -n "$label" ] || continue
  if [ ! -d "$dir" ]; then
    printf '  %-22s %-34s absent\n' "$label" "$(tilde "$dir")"
    continue
  fi
  links=""; copies=""; nlink=0; ncopy=0
  for name in $KNOWN; do
    p="$dir/$name"
    [ -e "$p" ] || continue
    if [ -L "$p" ]; then
      links="$links $name"; nlink=$((nlink+1))
    elif [ -d "$p" ]; then
      copies="$copies $name"; ncopy=$((ncopy+1))
    fi
  done
  n=$((nlink+ncopy))
  TOTAL_FOUND=$((TOTAL_FOUND+n))
  [ "$n" -gt 0 ] && DIRS_WITH_ANY=$((DIRS_WITH_ANY+1))
  printf '  %-22s %-34s %d installed (%d symlink, %d copied)\n' \
    "$label" "$(tilde "$dir")" "$n" "$nlink" "$ncopy"
  [ -n "$links" ]  && printf '      symlink:%s\n' "$links"
  [ -n "$copies" ] && printf '      copied :%s\n' "$copies"
done <<EOF
$(runtimes)
EOF

echo
if [ "$TOTAL_FOUND" -eq 0 ]; then
  echo "  No kelaskills skills found in any runtime directory."
  echo "  Install with: npx skills@latest add wicolian/kelaskills --all"
elif [ "$DIRS_WITH_ANY" -gt 1 ]; then
  echo "  Installed in $DIRS_WITH_ANY directories. If one is a symlinked clone and"
  echo "  another is a copy, they will drift. Keep the link, delete the copy."
fi

echo
echo "== dependencies =="

if command -v git >/dev/null 2>&1; then
  printf '  %-12s ok    %s\n' git "$(git --version 2>/dev/null | head -1)"
else
  printf '  %-12s MISSING\n' git
  add_missing "git: context-archaeology, stacked-prs, sync-main and file-pr all stop here."
fi

if command -v gh >/dev/null 2>&1; then
  printf '  %-12s ok    %s\n' gh "$(gh --version 2>/dev/null | head -1)"
  if gh auth status >/dev/null 2>&1; then
    printf '  %-12s ok    authenticated (detail not printed)\n' "gh auth"
  else
    printf '  %-12s NOT AUTHENTICATED\n' "gh auth"
    add_missing "gh auth: file-pr and babysit-pr stop. context-archaeology loses pull requests and reviews. Run: gh auth login"
  fi
else
  printf '  %-12s MISSING\n' gh
  add_missing "gh: file-pr and babysit-pr stop. context-archaeology is limited to local git."
fi

if command -v python3 >/dev/null 2>&1; then
  printf '  %-12s ok    %s\n' python3 "$(python3 --version 2>&1 | head -1)"
else
  printf '  %-12s MISSING\n' python3
  add_missing "python3: bundled scripts that parse JSON lose their preferred parser."
fi

if command -v node >/dev/null 2>&1; then
  printf '  %-12s ok    %s\n' node "$(node --version 2>/dev/null | head -1)"
else
  printf '  %-12s MISSING\n' node
  add_missing "node: no npx, so 'npx skills@latest' cannot install or update."
fi

if [ "${HERDR_ENV:-}" = "1" ]; then
  printf '  %-12s ok    HERDR_ENV=1, inside herdr\n' "herdr"
else
  printf '  %-12s not set\n' "HERDR_ENV"
  add_missing "HERDR_ENV: agent-fleet does not work outside herdr. Use graph-engineering instead."
fi

if [ -n "${VAULT_DIR:-}" ] && [ -d "${VAULT_DIR:-}" ]; then
  printf '  %-12s ok    %s\n' "VAULT_DIR" "$(tilde "$VAULT_DIR")"
elif [ -n "${VAULT_DIR:-}" ]; then
  printf '  %-12s set, but not a directory: %s\n' "VAULT_DIR" "$(tilde "$VAULT_DIR")"
  add_missing "VAULT_DIR points at nothing: obsidian-graph falls back to a local directory in the repo."
else
  printf '  %-12s not set\n' "VAULT_DIR"
  add_missing "VAULT_DIR: obsidian-graph writes to a local directory in the repo instead of a vault."
fi

echo
echo "== summary =="
if [ -z "$MISSING" ]; then
  echo "  Everything checked is present. Nothing is disabled."
else
  echo "  Missing or unset, and what it disables:"
  printf '%s' "$MISSING" | sed '/^$/d' | sed 's/^/    - /'
fi
echo
echo "  Chat, error-tracking, analytics, meeting and session-recording sources are"
echo "  MCP servers and cannot be checked from a shell. context-archaeology reports"
echo "  'no recorded reason' when it cannot reach them, which is not the same as no"
echo "  reason existing. See skills/context-archaeology/references/sources.md."
echo
echo "  A skill on disk is not a skill the agent can see. Most runtimes read the"
echo "  skill directory at session start, so start a new session after installing."
exit 0
