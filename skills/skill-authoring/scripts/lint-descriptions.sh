#!/usr/bin/env bash
# lint-descriptions.sh - flag skill descriptions that will not trigger well.
#
# A skill's description is loaded on every turn whether the skill fires or not,
# so it should be triggers only. This flags the four ways that goes wrong:
#
#   LONG        it is long enough to be a summary of the body
#   NO-TRIGGER  it never says when to fire
#   STEPS       it reads as step-by-step instructions, so the body never loads
#   OVERLAP     it shares most of its content words with another skill
#
# Read-only. It prints findings and changes nothing.
#
# Usage:   lint-descriptions.sh [skills-dir]        (default: ./skills)
# Tuning:  MAXLEN=500 OVERLAP=0.35 lint-descriptions.sh skills
# Exit:    0 clean, 1 with findings, 2 could not read the directory.
set -uo pipefail

DIR="${1:-skills}"
MAXLEN="${MAXLEN:-500}"
OVERLAP="${OVERLAP:-0.35}"

[ -d "$DIR" ] || { echo "not a directory: $DIR" >&2; exit 2; }

TMP="$(mktemp -t lintdesc.XXXXXX)" || exit 2
trap 'rm -f "$TMP"' EXIT INT TERM

# name<TAB>description, one line per skill. Single-line YAML values only.
for f in "$DIR"/*/SKILL.md; do
  [ -f "$f" ] || continue
  awk -v folder="$(basename "$(dirname "$f")")" '
    NR==1 && $0=="---" { inb=1; next }
    inb && $0=="---"    { exit }
    inb {
      i=index($0,":")
      if (i>0) {
        key=substr($0,1,i-1); val=substr($0,i+1)
        gsub(/^[ \t]+|[ \t]+$/,"",key); gsub(/^[ \t]+|[ \t]+$/,"",val)
        if (key=="description") { gsub(/\t/," ",val); print folder "\t" val; exit }
      }
    }
  ' "$f" >> "$TMP"
done

echo "== lint-descriptions =="
echo "   dir $DIR   maxlen $MAXLEN   overlap $OVERLAP"
echo

awk -F'\t' -v maxlen="$MAXLEN" -v ovmin="$OVERLAP" '
function tokens(s,   t,parts,k,i,w,out) {
  t=tolower(s); gsub(/[^a-z]+/," ",t)
  k=split(t,parts," "); out=" "
  for (i=1;i<=k;i++) {
    w=parts[i]
    if (length(w) < 5) continue
    if (w in STOP) continue
    if (index(out," " w " ")==0) out = out w " "
  }
  return out
}
BEGIN {
  split("about after against already always another before because between during " \
        "every everything github inside instead itself might other rather should " \
        "something their there these those through under until using whether which " \
        "while within without would write writes writing skill skills",sw," ")
  for (i in sw) STOP[sw[i]]=1
  n=0; findings=0
}
{ n++; nm[n]=$1; ds[n]=$2 }
END {
  for (i=1;i<=n;i++) {
    d=ds[i]; dl=tolower(d); L=length(d)

    # Count quoted trigger phrases. A description that is a long LIST OF
    # SITUATIONS is earning its length; one that is long because it summarises
    # the body is not. Length alone cannot tell those apart, so do not flag on
    # length alone or the linter cries wolf and gets ignored.
    quoted=0; tmp=d
    while (match(tmp, /"[^"]+"/)) { quoted++; tmp=substr(tmp, RSTART+RLENGTH) }

    if (L > maxlen && quoted < 3)
      report(nm[i],"LONG", L " chars, over " maxlen ", and only " quoted " quoted trigger phrase(s). Strip it to triggers.")
    else if (L < 45)
      report(nm[i],"VAGUE", L " chars. Too thin to match anything specific.")

    # The real defect behind most long descriptions: an inventory of what the
    # skill covers. That belongs in the body, which is exactly what does not
    # load when the description already sounds complete.
    if (dl ~ /(covers?|adds?|includes?|provides?) [^.]*,[^.]*,[^.]*/)
      report(nm[i],"METHOD","summarises the body (\"covers ...\" / \"adds ...\"). Cut that clause; keep the triggers.")

    if (dl !~ /use when|use this when|use it when|triggers? on|triggers? when|when the user|when asked|activates (when|for)/)
      report(nm[i],"NO-TRIGGER","no \"use when\" or \"triggers on\" phrasing.")

    # Quoted trigger phrases are user words, not instructions. Exempt them.
    dq=dl; gsub(/"[^"]*"/,"",dq)
    hit=""
    if (dq ~ /(^|[^a-z])(first|then|next|finally|afterwards),/) hit="sequence word"
    if (dq ~ /step [0-9]/)                                      hit="step number"
    if (dq ~ /(^|[^a-z])[0-9]\) /)                              hit="numbered list"
    if (dq ~ / -> /)                                            hit="arrow"
    if (hit != "") report(nm[i],"STEPS","reads as instructions (" hit "). Move it to the body.")

    TL[i]=tokens(d); CNT[i]=split(TL[i],junk," ")
  }

  for (i=1;i<n;i++) for (j=i+1;j<=n;j++) {
    if (CNT[i]==0 || CNT[j]==0) continue
    k=split(TL[i],a," "); inter=0
    for (x=1;x<=k;x++) if (index(TL[j]," " a[x] " ")) inter++
    uni = CNT[i] + CNT[j] - inter
    if (uni<=0) continue
    jac = inter/uni
    if (jac >= ovmin)
      report(nm[i] " <-> " nm[j],"OVERLAP", sprintf("%.2f shared content words. One of them will not fire.",jac))
  }

  printf "\n   %d skills read, %d findings\n", n, findings
  exit (findings>0)
}
function report(who,tag,msg) {
  findings++
  printf "%-11s %-34s %s\n", tag, who, msg
}
' "$TMP"
