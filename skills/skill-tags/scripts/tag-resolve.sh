#!/usr/bin/env bash
# Resolve "skill -tag -tag" into an ordered reading plan.
# Prints a plan. Runs nothing. Exit 2 on a bad invocation.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="$(cd "$SELF/../.." && pwd)"

die() { printf 'tag-resolve: %s\n' "$1" >&2; exit 2; }

# Read one frontmatter key from a SKILL.md. Frontmatter is the block between
# the first two lines that are exactly '---'.
fm() { # fm <file> <key>
  awk -v k="$2" '
    NR==1 && $0=="---" { inb=1; next }
    inb && $0=="---"    { exit }
    inb {
      i=index($0,":")
      if (i>0) {
        key=substr($0,1,i-1); val=substr($0,i+1)
        gsub(/^[ \t]+|[ \t]+$/,"",key); gsub(/^[ \t]+|[ \t]+$/,"",val)
        gsub(/^["'\'']|["'\'']$/,"",val)
        if (key==k) { print val; exit }
      }
    }' "$1" 2>/dev/null
}

phase_rank() {
  case "$1" in
    before)    echo 1 ;;
    decisions) echo 2 ;;
    gates)     echo 3 ;;
    after)     echo 4 ;;
    *)         echo 9 ;;
  esac
}

# Emit "tag<TAB>name<TAB>phase<TAB>rank<TAB>budget<TAB>path" for every lens.
scan_lenses() {
  for d in "$SKILLS_ROOT"/*/; do
    f="${d%/}/SKILL.md"; [ -f "$f" ] || continue
    [ "$(fm "$f" kind)" = "lens" ] || continue
    n=$(fm "$f" name); t=$(fm "$f" tag); p=$(fm "$f" phase); b=$(fm "$f" ask_budget)
    [ -n "$t" ] || t="-$n"
    [ -n "$p" ] || p="decisions"
    [ -n "$b" ] || b=0
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$t" "$n" "$p" "$(phase_rank "$p")" "$b" "$f"
  done
}

usage() {
  cat <<'U'
usage: tag-resolve.sh <skill> [-tag ...] [--brief]
       tag-resolve.sh --list

  <skill>   a skill name in this repo, with or without a leading slash
  -tag      a registered lens; order typed is ignored, phase order wins
  --brief   also print the composed brief to paste into a worker prompt
U
}

LENSES="$(scan_lenses)"

if [ $# -eq 0 ]; then usage; exit 2; fi

if [ "$1" = "--list" ]; then
  if [ -z "$LENSES" ]; then echo "no lenses found under $SKILLS_ROOT"; exit 0; fi
  printf '%-18s %-20s %-10s %s\n' TAG SKILL PHASE ASK_ROUNDS
  printf '%s\n' "$LENSES" | sort -t"$(printf '\t')" -k4,4n \
    | while IFS=$'\t' read -r t n p r b f; do printf '%-18s %-20s %-10s %s\n' "$t" "$n" "$p" "$b"; done
  exit 0
fi
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then usage; exit 0; fi

BRIEF=0
HOST=""
TAGS=()
for a in "$@"; do
  case "$a" in
    --brief) BRIEF=1 ;;
    -*)      TAGS+=("$a") ;;
    *)       [ -z "$HOST" ] && HOST="${a#/}" || die "more than one skill named: $HOST and $a" ;;
  esac
done

[ -n "$HOST" ] || die "no skill named. try --list"
HOST_FILE="$SKILLS_ROOT/$HOST/SKILL.md"
[ -f "$HOST_FILE" ] || die "no such skill: $HOST (looked in $SKILLS_ROOT/$HOST/)"
if [ "$(fm "$HOST_FILE" kind)" = "lens" ]; then
  die "$HOST is a lens, not a host skill. a lens cannot run alone."
fi

# Resolve each tag, keep phase order, reject duplicates and unknowns.
RESOLVED=""
seen=""
for t in ${TAGS[@]+"${TAGS[@]}"}; do
  case " $seen " in *" $t "*) die "tag given twice: $t" ;; esac
  seen="$seen $t"
  row="$(printf '%s\n' "$LENSES" | awk -F'\t' -v t="$t" '$1==t {print; exit}')"
  if [ -z "$row" ]; then
    known="$(printf '%s\n' "$LENSES" | cut -f1 | tr '\n' ' ')"
    die "unknown tag: $t (known: ${known:-none})"
  fi
  RESOLVED="${RESOLVED}${row}"$'\n'
done
RESOLVED="$(printf '%s' "$RESOLVED" | sed '/^$/d' | sort -t"$(printf '\t')" -k4,4n -k2,2)"

TOTAL=0
if [ -n "$RESOLVED" ]; then
  TOTAL=$(printf '%s\n' "$RESOLVED" | awk -F'\t' '{s+=$5} END {print s+0}')
fi

echo "host:        $HOST"
echo "host file:   ${HOST_FILE#"$SKILLS_ROOT"/}"
if [ -z "$RESOLVED" ]; then
  echo "lenses:      none"
  echo
  echo "Read the host skill and run it. No lens is in effect; do not add one."
  exit 0
fi
echo "lenses:      $(printf '%s\n' "$RESOLVED" | cut -f1 | tr '\n' ' ')"
echo "ask rounds:  $TOTAL interruption(s) allowed in total (batch questions within a round)"
echo
echo "Reading order (phase order, not the order you typed):"
i=0
while IFS=$'\t' read -r t n p r b f; do
  i=$((i+1))
  printf '  %d. %-18s %-10s rounds<=%s  %s\n' "$i" "$t" "($p)" "$b" "${f#"$SKILLS_ROOT"/}"
done <<< "$RESOLVED"
printf '  %d. %-18s %-10s          %s\n' "$((i+1))" "$HOST" "(host)" "${HOST_FILE#"$SKILLS_ROOT"/}"

if [ "$BRIEF" = "1" ]; then
  echo
  echo "--- brief ---"
  echo "You are running the '$HOST' skill under $(printf '%s\n' "$RESOLVED" | wc -l | tr -d ' ') lens(es)."
  echo "The host skill owns the job and the definition of done. A lens may only add"
  echo "constraints, evidence, questions or gates. It may never add scope."
  echo
  while IFS=$'\t' read -r t n p r b f; do
    echo "$t  (phase: $p, may interrupt the human at most $b time(s))"
    echo "    read: ${f#"$SKILLS_ROOT"/}"
  done <<< "$RESOLVED"
  echo
  echo "Total interruptions allowed across all lenses: $TOTAL. This is a cap, not a target."
  echo "An interruption is one batched round. Ten questions asked at once is one."
  echo "Never ask for a fact. Facts are yours to find. Only decisions go to the human."
  echo "Announce the lenses in effect once, at the top of your first reply."
  echo "On a conflict: hard rules > narrower scope > evidence > conservative > ask."
  echo "Never resolve a conflict silently; say what disagreed and which rule decided."
fi
