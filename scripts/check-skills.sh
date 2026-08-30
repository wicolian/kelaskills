#!/usr/bin/env bash
# Repo gate. Run before opening a PR.
#   - no em-dash anywhere (U+2014 is banned in this repo)
#   - every skill folder has a SKILL.md with name and description
#   - the folder name matches the frontmatter name
#   - every lens satisfies the contract in skills/skill-tags/SKILL.md
#   - every script is executable and passes a syntax check
# Exit 0 clean, 1 with findings.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
FAIL=0
note() { printf '  %s\n' "$1"; FAIL=1; }

fm() {
  awk -v k="$2" '
    NR==1 && $0=="---" { inb=1; next }
    inb && $0=="---"    { exit }
    inb { i=index($0,":")
      if (i>0) { key=substr($0,1,i-1); val=substr($0,i+1)
        gsub(/^[ \t]+|[ \t]+$/,"",key); gsub(/^[ \t]+|[ \t]+$/,"",val)
        if (key==k) { print val; exit } } }' "$1" 2>/dev/null
}

echo "== em-dash =="
HITS=$(git ls-files -z --cached --others --exclude-standard | xargs -0 grep -n $'\xe2\x80\x94' 2>/dev/null)
if [ -n "$HITS" ]; then
  note "banned character U+2014 found. use a comma, a colon, a full stop, or ' - '."
  printf '%s\n' "$HITS" | sed 's/^/    /' | head -20
else
  echo "  clean"
fi

echo "== skills =="
for d in skills/*/; do
  name="$(basename "$d")"
  f="${d%/}/SKILL.md"
  if [ ! -f "$f" ]; then
    [ -f "${d%/}/README.md" ] || note "$name: no SKILL.md and no README.md"
    continue
  fi
  head -1 "$f" | grep -q '^---$' || note "$name: SKILL.md does not open with frontmatter"
  fname="$(fm "$f" name)"
  [ -n "$fname" ] || note "$name: frontmatter has no name"
  [ "$fname" = "$name" ] || note "$name: frontmatter name is '$fname', folder is '$name'"
  [ -n "$(fm "$f" description)" ] || note "$name: frontmatter has no description"

  if [ "$(fm "$f" kind)" = "lens" ]; then
    tag="$(fm "$f" tag)"; phase="$(fm "$f" phase)"; budget="$(fm "$f" ask_budget)"
    case "$tag" in -?*) ;; *) note "$name: lens tag must start with '-', got '${tag:-empty}'" ;; esac
    case "$phase" in before|decisions|gates|after) ;; *) note "$name: lens phase must be before|decisions|gates|after, got '${phase:-empty}'" ;; esac
    case "$budget" in ''|*[!0-9]*) note "$name: lens ask_budget must be a number, got '${budget:-empty}'" ;; esac
    for h in "## Intervention points" "## Hard rules" "## When to skip" "## Handoff"; do
      grep -qF "$h" "$f" || note "$name: lens is missing required heading '$h'"
    done
    grep -qF "skills/$name" TAGS.md 2>/dev/null || note "$name: lens is not registered in TAGS.md"
  fi
done
echo "  checked $(ls -d skills/*/ 2>/dev/null | wc -l | tr -d ' ') skill folders"

# A hint that advertises a tag nobody implements is worse than no hint: it puts
# a broken invocation in front of the user at the exact moment they are choosing.
KNOWN_TAGS=" $(for d in skills/*/; do
    f="${d%/}/SKILL.md"; [ -f "$f" ] || continue
    [ "$(fm "$f" kind)" = "lens" ] || continue
    t="$(fm "$f" tag)"; [ -n "$t" ] && printf '%s ' "$t"
  done) "
for d in skills/*/; do
  f="${d%/}/SKILL.md"; [ -f "$f" ] || continue
  hint="$(fm "$f" argument-hint)"
  [ -n "$hint" ] || continue
  # Only a fully bracketed token counts, so "[skill-name]" and the "<skill>
  # [-tag ...]" placeholder are not mistaken for advertised lenses.
  for t in $(printf '%s' "$hint" | grep -oE '\[-[a-z][a-z0-9-]*\]' | tr -d '[]' || true); do
    case "$KNOWN_TAGS" in
      *" $t "*) ;;
      *) note "$(basename "${d%/}"): argument-hint advertises '$t', which is not a registered lens" ;;
    esac
  done
done

echo "== links =="
# Every relative markdown link must resolve. This covers skills/<name> links in
# the README and TAGS.md, and the ../sibling links skills use to reach each
# other, which an earlier version of this check silently ignored.
nlink=0
while IFS= read -r md; do
  dir="$(dirname "$md")"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    case "$target" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    target="${target%%#*}"          # drop an anchor
    target="${target%%\?*}"         # drop a query
    [ -n "$target" ] || continue
    nlink=$((nlink+1))
    case "$target" in
      /*) resolved="${target#/}" ;;
      *)  resolved="$dir/$target" ;;
    esac
    [ -e "$resolved" ] || note "$md links to '$target', which does not resolve"
  done < <(grep -oE '\]\([^)]+\)' "$md" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//')
done < <(git ls-files --cached --others --exclude-standard '*.md')
echo "  checked $nlink relative links"

echo "== scripts =="
n=0
while IFS= read -r s; do
  n=$((n+1))
  [ -x "$s" ] || note "$s is not executable (chmod +x)"
  case "$s" in
    *.sh) bash -n "$s" 2>/dev/null || note "$s fails bash syntax check" ;;
    *.mjs|*.js) command -v node >/dev/null && { node --check "$s" 2>/dev/null || note "$s fails node syntax check"; } ;;
  esac
done < <(git ls-files --cached --others --exclude-standard 'skills/*/scripts/*' 'skills/*/*.sh' 'skills/*/*.mjs' 'scripts/*' 2>/dev/null)
echo "  checked $n scripts"

echo
echo "This gate checks correctness. For description quality, which is a"
echo "judgement call and not a hard failure, run:"
echo "  skills/skill-authoring/scripts/lint-descriptions.sh"
echo
if [ "$FAIL" = "0" ]; then echo "PASS"; else echo "FAIL"; fi
exit "$FAIL"
