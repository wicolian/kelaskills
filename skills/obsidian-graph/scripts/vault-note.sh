#!/usr/bin/env bash
# vault-note.sh - write ONE learned fact into an Obsidian vault as a typed-edge note.
#
# Append-only by design. It never bulk-rewrites, never deletes, and refuses to
# clobber an existing note. A fact that changed is written as a NEW note that
# supersedes the old one, so the reasoning trail survives.
#
# Usage:
#   vault-note.sh --claim TEXT --type TYPE --confidence LEVEL --source TEXT
#                 [--title TEXT] [--tag TAG]... [--edge TYPE=SLUG]...
#                 [--falsified-by TEXT] [--supersede] [--dry-run]
#
#   --type         constraint | decision | cause
#   --confidence   high | medium | low
#   --edge         one of: supersedes depends_on decided_by caused implements references
#                  value is the slug of another note, no brackets, repeatable
#   --supersede    on a filename collision, write the next note in the chain and
#                  flip the predecessor to status: superseded. Without it, a
#                  collision is a refusal (exit 3).
#
# Environment:
#   VAULT_DIR        vault root. If unset or missing, degraded mode kicks in.
#   VAULT_SUBFOLDER  folder inside the vault             (default: Agent/Learned)
#   VAULT_FALLBACK   degraded-mode directory             (default: ./.agent-notes)
#
# Exit codes: 0 written, 2 bad invocation, 3 refused (note exists).
#
# Bash 3.2 clean: no associative arrays, no ${x^^}, arrays guarded for set -u.

set -euo pipefail

SELF="$(basename "$0")"
die() { printf '%s: %s\n' "$SELF" "$1" >&2; exit "${2:-2}"; }
note() { printf '%s: %s\n' "$SELF" "$1" >&2; }

CLAIM=""; TYPE=""; CONF=""; SOURCE=""; TITLE=""; FALSIFY=""
SUPERSEDE=0; DRYRUN=0
TAGS=()
E_SUPERSEDES=""; E_DEPENDS=""; E_DECIDED=""; E_CAUSED=""; E_IMPLEMENTS=""; E_REFS=""

add_edge() { # add_edge <type> <slug>
  _t="$1"; _s="$2"
  [ -n "$_s" ] || die "empty slug for edge '$_t'"
  case "$_s" in
    *"[["*|*"]]"*) die "edge value must be a bare slug, not a wikilink: $_s" ;;
  esac
  _v="\"[[$_s]]\""
  case "$_t" in
    supersedes)  E_SUPERSEDES="${E_SUPERSEDES:+$E_SUPERSEDES, }$_v" ;;
    depends_on)  E_DEPENDS="${E_DEPENDS:+$E_DEPENDS, }$_v" ;;
    decided_by)  E_DECIDED="${E_DECIDED:+$E_DECIDED, }$_v" ;;
    caused)      E_CAUSED="${E_CAUSED:+$E_CAUSED, }$_v" ;;
    implements)  E_IMPLEMENTS="${E_IMPLEMENTS:+$E_IMPLEMENTS, }$_v" ;;
    references)  E_REFS="${E_REFS:+$E_REFS, }$_v" ;;
    *) die "unknown edge type '$_t'. Allowed: supersedes depends_on decided_by caused implements references" ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --claim)        CLAIM="${2:?--claim needs a value}"; shift 2 ;;
    --type)         TYPE="${2:?--type needs a value}"; shift 2 ;;
    --confidence)   CONF="${2:?--confidence needs a value}"; shift 2 ;;
    --source)       SOURCE="${2:?--source needs a value}"; shift 2 ;;
    --title)        TITLE="${2:?--title needs a value}"; shift 2 ;;
    --falsified-by) FALSIFY="${2:?--falsified-by needs a value}"; shift 2 ;;
    --tag)          TAGS=(${TAGS[@]+"${TAGS[@]}"} "${2:?--tag needs a value}"); shift 2 ;;
    --edge)
      _pair="${2:?--edge needs TYPE=SLUG}"
      case "$_pair" in *=*) : ;; *) die "--edge wants TYPE=SLUG, got '$_pair'" ;; esac
      add_edge "${_pair%%=*}" "${_pair#*=}"
      shift 2 ;;
    --supersede)    SUPERSEDE=1; shift ;;
    --dry-run)      DRYRUN=1; shift ;;
    -h|--help)      sed -n '2,30p' "$0"; exit 0 ;;
    *) die "unknown argument '$1'" ;;
  esac
done

[ -n "$CLAIM" ]  || die "--claim is required"
[ -n "$SOURCE" ] || die "--source is required. A claim with no source is a rumour."
case "$TYPE" in constraint|decision|cause) : ;; *) die "--type must be constraint, decision or cause (got '${TYPE:-}')" ;; esac
case "$CONF" in high|medium|low) : ;; *) die "--confidence must be high, medium or low (got '${CONF:-}')" ;; esac

# ---------------------------------------------------------------- destination
SUBFOLDER="${VAULT_SUBFOLDER:-Agent/Learned}"
FALLBACK="${VAULT_FALLBACK:-./.agent-notes}"
MODE="vault"
if [ -n "${VAULT_DIR:-}" ] && [ -d "${VAULT_DIR:-}" ]; then
  DEST="$VAULT_DIR/$SUBFOLDER"
else
  MODE="degraded"
  DEST="$FALLBACK"
  note "no vault at VAULT_DIR, degraded mode: writing to $DEST"
fi

# ---------------------------------------------------------------------- slug
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-*//' -e 's/-*$//' \
    | cut -c1-60 \
    | sed -e 's/-*$//'
}

if [ -z "$TITLE" ]; then
  # First 9 words of the claim, which is enough to read in a file list.
  TITLE="$(printf '%s' "$CLAIM" | awk '{ n = (NF < 9 ? NF : 9); for (i = 1; i <= n; i++) printf "%s%s", $i, (i < n ? " " : "") }')"
fi
SLUG="$(slugify "$TITLE")"
[ -n "$SLUG" ] || die "could not build a slug from the title '$TITLE'"

TODAY="$(date +%Y-%m-%d)"

# ------------------------------------------------------- collision behaviour
PREV_FILE=""
TARGET="$DEST/$SLUG.md"
if [ -e "$TARGET" ]; then
  if [ "$SUPERSEDE" -ne 1 ]; then
    die "note already exists: $TARGET
  This fact is already recorded. If it is now wrong, re-run with --supersede.
  If it is a different fact, give it its own --title." 3
  fi
  n=2
  while [ -e "$DEST/$SLUG-$n.md" ]; do n=$((n + 1)); done
  k=$((n - 1))
  if [ "$k" -ge 2 ]; then PREV_SLUG="$SLUG-$k"; else PREV_SLUG="$SLUG"; fi
  PREV_FILE="$DEST/$PREV_SLUG.md"
  TARGET="$DEST/$SLUG-$n.md"
  add_edge supersedes "$PREV_SLUG"
fi

# ------------------------------------------------------------------- render
render() {
  printf -- '---\n'
  printf 'type: %s\n' "$TYPE"
  printf 'status: current\n'
  printf 'confidence: %s\n' "$CONF"
  printf 'source: "%s"\n' "$(printf '%s' "$SOURCE" | sed 's/"/\\"/g')"
  printf 'date: %s\n' "$TODAY"
  printf 'tags: [agent/learned, type/%s' "$TYPE"
  for t in ${TAGS[@]+"${TAGS[@]}"}; do printf ', %s' "$t"; done
  printf ']\n'
  [ -n "$E_SUPERSEDES" ] && printf 'supersedes: [%s]\n' "$E_SUPERSEDES"
  [ -n "$E_DEPENDS" ]    && printf 'depends_on: [%s]\n' "$E_DEPENDS"
  [ -n "$E_DECIDED" ]    && printf 'decided_by: [%s]\n' "$E_DECIDED"
  [ -n "$E_CAUSED" ]     && printf 'caused: [%s]\n' "$E_CAUSED"
  [ -n "$E_IMPLEMENTS" ] && printf 'implements: [%s]\n' "$E_IMPLEMENTS"
  [ -n "$E_REFS" ]       && printf 'references: [%s]\n' "$E_REFS"
  printf -- '---\n\n'
  printf '# %s\n\n' "$TITLE"
  printf '%s\n\n' "$CLAIM"
  printf '**Source.** %s\n' "$SOURCE"
  [ -n "$FALSIFY" ] && printf '\n**Wrong when.** %s\n' "$FALSIFY"
  return 0
}

if [ "$DRYRUN" -eq 1 ]; then
  printf '# would write: %s (mode: %s)\n' "$TARGET" "$MODE"
  render
  exit 0
fi

mkdir -p "$DEST"
render > "$TARGET"

# One targeted edit is allowed, and only this one: flip the direct predecessor
# from current to superseded, inside its frontmatter, nowhere else.
if [ -n "$PREV_FILE" ] && [ -f "$PREV_FILE" ]; then
  TMP="$(mktemp "${TMPDIR:-/tmp}/vault-note.XXXXXX")"
  awk '
    NR == 1 && $0 == "---" { inb = 1; print; next }
    inb && $0 == "---"     { inb = 0; print; next }
    inb && $0 == "status: current" { print "status: superseded"; next }
    { print }
  ' "$PREV_FILE" > "$TMP"
  mv "$TMP" "$PREV_FILE"
  note "flipped to superseded: $PREV_FILE"
fi

printf '%s\n' "$TARGET"
