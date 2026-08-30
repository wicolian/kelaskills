#!/usr/bin/env bash
# propose-surfaces.sh - draft a "surfaces a feature must reach" checklist from a
# repository's layout.
#
# Read-only. It runs find and grep and prints markdown. It writes nothing.
#
# Usage:  ./propose-surfaces.sh [path-to-repo]
#
# The output is a CANDIDATE list. Prune it by hand. A directory named
# "providers" is not automatically a surface, and a surface with no directory
# of its own will not appear here at all.
#
# Cost: two full-tree greps plus a few finds. Under 2 seconds on a small
# repository, about a minute on a 2.7 GB monorepo. Point it at a repository
# root, not at a home directory.

set -u

ROOT="${1:-.}"
[ -d "$ROOT" ] || { echo "not a directory: $ROOT" >&2; exit 2; }

SKIP="--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist
      --exclude-dir=build --exclude-dir=vendor --exclude-dir=.next
      --exclude-dir=coverage --exclude-dir=target --exclude-dir=.venv"

PRUNE='-name node_modules -o -name .git -o -name dist -o -name build
       -o -name vendor -o -name target -o -name .venv -o -name venv
       -o -name __pycache__ -o -name .next -o -name coverage'

rel() { sed "s#^$ROOT/##; s#^$ROOT\$#.#"; }
section() { printf '\n## %s\n\n' "$1"; }
none() { printf -- '- (nothing found. Check by hand: %s)\n' "$1"; }
boxes() { while IFS= read -r l; do [ -n "$l" ] && printf -- '- [ ] `%s`\n' "$l"; done; }

printf '# Proposed surface checklist\n'
printf '\nRepository: `%s`\n' "$ROOT"
printf '\nDraft only. Prune what is not real, and add what has no directory.\n'

# ---------------------------------------------------------------- platforms
section "Clients and platforms"
PLAT=$(find "$ROOT" -maxdepth 3 \( $PRUNE \) -prune -o -type d \
  \( -name web -o -name webapp -o -name desktop -o -name mobile \
     -o -name ios -o -name android -o -name cli -o -name extension \
     -o -name extensions -o -name server -o -name backend -o -name frontend \
     -o -name electron -o -name native -o -name tui -o -name worker \) \
  -print 2>/dev/null | rel | sort -u)
if [ -n "$PLAT" ]; then printf '%s\n' "$PLAT" | boxes
else none "one deployable, or platform names this script does not know"; fi
WS=$(find "$ROOT" -maxdepth 2 \( -name 'pnpm-workspace.yaml' -o -name 'lerna.json' \
  -o -name 'go.work' -o -name 'turbo.json' -o -name 'Cargo.toml' \) 2>/dev/null | rel)
[ -n "$WS" ] && printf -- '- a workspace manifest exists. Read it for the full member list:\n%s\n' \
  "$(printf '%s\n' "$WS" | sed 's/^/  /')"

# ---------------------------------------------------------------- adapters
section "Adapters and providers"
printf 'Each one needs a decision, even when the decision is "not supported here".\n\n'
ADP=$(find "$ROOT" \( $PRUNE \) -prune -o -type d \
  \( -name adapters -o -name adapter -o -name providers -o -name provider \
     -o -name drivers -o -name integrations -o -name backends \
     -o -name connectors -o -name plugins -o -name transports \) \
  -print 2>/dev/null | rel | sort -u)
if [ -n "$ADP" ]; then
  printf '%s\n' "$ADP" | while IFS= read -r d; do
    kids=$(find "$ROOT/$d" -mindepth 1 -maxdepth 1 2>/dev/null \
      | sed 's#.*/##; s#\.[a-zA-Z0-9]*$##' | sort -u | tr '\n' ' ')
    printf -- '- [ ] `%s` -> %s\n' "$d" "${kids:-empty}"
  done
else
  none "an interface with three or more implementations, whatever the folder is called"
fi

# ---------------------------------------------------------------- contracts
section "Shared contracts"
CON=$(find "$ROOT" \( $PRUNE \) -prune -o -type d \
  \( -name shared -o -name common -o -name contracts -o -name schema \
     -o -name schemas -o -name proto -o -name protocol \) \
  -print 2>/dev/null | rel | sort -u)
if [ -n "$CON" ]; then printf '%s\n' "$CON" | boxes
else none "a package both sides import, or a generated client"; fi

# ---------------------------------------------------------------- entry points
section "Entry points"
EP_PAT='registerCommand|commandPalette|command_palette|keybinding|keyBinding|contextMenu|context_menu|menuItem|deepLink|deep_link|urlScheme|quickAction'
EP=$(grep -rElI $SKIP --exclude-dir=tests --exclude-dir=test \
      --exclude-dir=__tests__ --exclude-dir=e2e --exclude-dir=spec \
      --include='*.*' "$EP_PAT" "$ROOT" 2>/dev/null \
  | grep -vE '\.(md|markdown|txt|rst)$' \
  | grep -vE '\.(spec|test|stories)\.[a-zA-Z]+$' \
  | rel | sort -u | head -25)
if [ -n "$EP" ]; then
  printf 'Files that register a way in. Read them and list the real entry points.\n\n'
  printf '%s\n' "$EP" | boxes
else
  none "menus, palettes, shortcuts, settings screens, deep links, public routes"
fi

# ---------------------------------------------------------------- docs
section "Docs"
DOC=$(find "$ROOT" -maxdepth 3 \( $PRUNE \) -prune -o -type d \
  \( -name docs -o -name doc -o -name documentation -o -name website \) \
  -print 2>/dev/null | rel | sort -u)
if [ -n "$DOC" ]; then
  printf '%s\n' "$DOC" | boxes
  if [ "$(printf '%s\n' "$DOC" | grep -c .)" -lt 2 ]; then
    printf -- '- NOTE: one docs root. The user versus maintainer split does not exist\n'
    printf -- '  yet, so internal detail is probably leaking into user-facing pages.\n'
  fi
else
  none "no docs root at all"
fi

# ---------------------------------------------------------------- reverse states
section "Reverse states"
printf 'A forward-state verb in the source with no matching reverse is the most\n'
printf 'commonly missed surface. This is a word search, so read the spellings it\n'
printf 'found before you believe a row.\n\n'

WORDS='mute snooze archive pin favourite favorite subscribe invite share hide enable connect'

# one forward scan for every word, compressed to distinct spellings with counts
FWD_ALT=$(for w in $WORDS; do
  W=$(printf '%s' "$w" | cut -c1 | tr 'a-z' 'A-Z')$(printf '%s' "$w" | cut -c2-)
  printf '%s|%s|' "$w" "$W"
done | sed 's/|$//')
FWD=$(grep -rhoIE $SKIP --include='*.*' "(^|[^A-Za-z])(${FWD_ALT})[A-Za-z_]*" "$ROOT" 2>/dev/null \
      | sed 's/^[^A-Za-z]*//' | sort | uniq -c | sort -rn)

# per-word reverse patterns, and one scan for all of them
rev_for() {
  case "$1" in
    share)   printf 'unshare|unShare|revoke|Revoke|stopSharing' ;;
    invite)  printf 'uninvite|unInvite|revokeInvite|cancelInvite|revoke' ;;
    enable)  printf 'disable|Disable' ;;
    connect) printf 'disconnect|Disconnect' ;;
    hide)    printf 'unhide|unHide|reveal|Reveal|show[A-Z_]' ;;
    archive) printf 'unarchive|unArchive|restore|Restore' ;;
    *) w="$1"
       W=$(printf '%s' "$w" | cut -c1 | tr 'a-z' 'A-Z')$(printf '%s' "$w" | cut -c2-)
       printf 'un%s|un_%s|un%s|remove_?%s|remove%s|clear_?%s|clear%s|cancel_?%s|cancel%s' \
         "$w" "$w" "$W" "$w" "$W" "$w" "$W" "$w" "$W" ;;
  esac
}
REV_ALT=$(for w in $WORDS; do rev_for "$w"; printf '|'; done | sed 's/|$//')
REV=$(grep -rhoIE $SKIP --include='*.*' "$REV_ALT" "$ROOT" 2>/dev/null | sort | uniq -c)

FOUND=0
for w in $WORDS; do
  W=$(printf '%s' "$w" | cut -c1 | tr 'a-z' 'A-Z')$(printf '%s' "$w" | cut -c2-)
  rows=$(printf '%s\n' "$FWD" | awk -v a="$w" -v b="$W" '$2 ~ "^("a"|"b")" {print}')
  [ -z "$rows" ] && continue
  fwd=$(printf '%s\n' "$rows" | awk '{t+=$1} END {print t+0}')
  [ "$fwd" -lt 3 ] && continue
  FOUND=1
  spell=$(printf '%s\n' "$rows" | head -3 | awk '{printf "%s ", $2}')
  rp=$(rev_for "$w")
  hits=$(printf '%s\n' "$REV" | awk -v p="$rp" '$2 ~ "^("p")" {t+=$1} END {print t+0}')
  if [ "$hits" -eq 0 ]; then
    printf -- '- [ ] **`%s`: no reverse found.** %s hits, spelled: %s\n' "$w" "$fwd" "$spell"
    printf -- '      Where is the un-%s? If those spellings are a styling token or an\n' "$w"
    printf -- '      unrelated word, this row is a false positive. Delete it.\n'
  else
    printf -- '- [ ] `%s`: %s forward hits (%s), %s reverse hits.\n' "$w" "$fwd" "$spell" "$hits"
    printf -- '      Is the reverse on every surface above, not just one?\n'
  fi
done
[ "$FOUND" = "0" ] && none "any verb that puts an object into a state"

printf '\n## Always\n\n'
printf -- '- [ ] The reverse of any state you added\n'
printf -- '- [ ] The docs\n'
printf '\nFull reverse-state procedure: `references/glossary-and-surfaces.md`.\n'
