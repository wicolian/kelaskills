#!/usr/bin/env bash
# fleet-plan.sh - resolve which skills this machine should have, and say why.
#
# DRY RUN ONLY. This script reads. It never copies, symlinks, removes, writes,
# or connects to another machine. It prints a plan and exits.
#
# usage: fleet-plan.sh [--repo DIR] [--tier NAME]... [--machine NAME]
#                      [--runtime NAME] [--dest DIR]
#
# Exit 0 with a plan, 2 on a bad invocation.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf 'fleet-plan: %s\n' "$1" >&2; exit 2; }

usage() {
  cat <<'U'
usage: fleet-plan.sh [--repo DIR] [--tier NAME]... [--machine NAME]
                     [--runtime NAME] [--dest DIR]

  --repo DIR      the fleet repository. Default: $FLEET_REPO, else a search
                  upward from here, else ~/fleet.
  --tier NAME     a tier this machine gets. Repeatable, or comma separated.
                  Default: universal.
  --machine NAME  this machine's inventory name, so skills targeted at a
                  named machine resolve. Default: the short hostname.
  --runtime NAME  claude-code | codex | cursor | hermes-agent | pi | universal.
                  Default: universal. Picks the directory checked for skills
                  that are already installed.
  --dest DIR      check this directory instead of the runtime default.

This is a dry run. Nothing is installed, linked, or removed.
U
}

# ---------------------------------------------------------------- runtime map
# These paths come from the install table in the repository README. Do not
# invent new ones here.
dest_for_runtime() {
  case "$1" in
    claude|claude-code) printf '%s\n' "$HOME/.claude/skills" ;;
    codex)              printf '%s\n' "${CODEX_HOME:-$HOME/.codex}/skills" ;;
    cursor)             printf '%s\n' "$HOME/.cursor/skills" ;;
    hermes|hermes-agent) printf '%s\n' "$HOME/.hermes/skills" ;;
    pi)                 printf '%s\n' "${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}/skills" ;;
    universal)          printf '%s\n' "$HOME/.agents/skills" ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------ argument parsing
REPO=""
MACHINE=""
RUNTIME="universal"
DEST=""
TIERS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)    [ "$#" -ge 2 ] || die "--repo needs a value"; REPO="$2"; shift 2 ;;
    --machine) [ "$#" -ge 2 ] || die "--machine needs a value"; MACHINE="$2"; shift 2 ;;
    --runtime) [ "$#" -ge 2 ] || die "--runtime needs a value"; RUNTIME="$2"; shift 2 ;;
    --dest)    [ "$#" -ge 2 ] || die "--dest needs a value"; DEST="$2"; shift 2 ;;
    --tier)
      [ "$#" -ge 2 ] || die "--tier needs a value"
      old_ifs="$IFS"; IFS=','
      for t in $2; do
        t="$(printf '%s' "$t" | tr -d '[:space:]')"
        [ -n "$t" ] && TIERS[${#TIERS[@]}]="$t"
      done
      IFS="$old_ifs"
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

[ "${#TIERS[@]}" -gt 0 ] || TIERS=(universal)
[ -n "$MACHINE" ] || MACHINE="$(hostname -s 2>/dev/null || hostname)"

# ------------------------------------------------------------- find the repo
if [ -z "$REPO" ]; then
  if [ -n "${FLEET_REPO:-}" ]; then
    REPO="$FLEET_REPO"
  else
    d="$SELF"
    while [ "$d" != "/" ]; do
      if [ -f "$d/fleet.md" ] && [ -d "$d/skills" ]; then REPO="$d"; break; fi
      d="$(dirname "$d")"
    done
    [ -n "$REPO" ] || REPO="$HOME/fleet"
  fi
fi

if [ ! -d "$REPO" ]; then
  printf 'fleet-plan: no fleet repository at %s\n' "$REPO" >&2
  printf '  set FLEET_REPO, or pass --repo DIR. A fleet repository has a\n' >&2
  printf '  fleet.md inventory and a skills/ directory of tier folders.\n' >&2
  exit 2
fi
if [ ! -d "$REPO/skills" ]; then
  printf 'fleet-plan: %s has no skills/ directory, so it is not a fleet repository\n' "$REPO" >&2
  exit 2
fi
REPO="$(cd "$REPO" && pwd)"

# ------------------------------------------------------------ destination dir
if [ -z "$DEST" ]; then
  DEST="$(dest_for_runtime "$RUNTIME")" || die "unknown runtime: $RUNTIME (claude-code, codex, cursor, hermes-agent, pi, universal)"
fi

# --------------------------------------------------------------- known tiers
# A tier is a directory under skills/. universal and control always count,
# even before anyone has created the folder.
KNOWN=" universal control "
for d in "$REPO"/skills/*/; do
  [ -d "$d" ] || continue
  n="$(basename "$d")"
  case "$KNOWN" in *" $n "*) ;; *) KNOWN="$KNOWN$n " ;; esac
done

is_known_tier() { case "$KNOWN" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

for t in ${TIERS[@]+"${TIERS[@]}"}; do
  if ! is_known_tier "$t"; then
    printf 'fleet-plan: unknown tier "%s"\n' "$t" >&2
    printf '  tiers in %s: %s\n' "$REPO/skills" "$(printf '%s' "$KNOWN" | sed 's/^ //; s/ $//')" >&2
    exit 2
  fi
done

machine_wants() { # machine_wants <target-token>
  [ "$1" = "$MACHINE" ] && return 0
  for t in ${TIERS[@]+"${TIERS[@]}"}; do
    [ "$1" = "$t" ] && return 0
  done
  return 1
}

# ------------------------------------------------- frontmatter, parsed by awk
# Emits at most three lines: "targets<TAB>a,b", "bins<TAB>a,b", "env<TAB>A,B".
# Handles inline lists (`targets: [universal]`) and block lists (`- universal`).
read_meta() {
  awk '
    function flat(s,   n, i, parts, out, p) {
      gsub(/^[ \t]*\[/, "", s); gsub(/\][ \t]*$/, "", s)
      n = split(s, parts, ",")
      out = ""
      for (i = 1; i <= n; i++) {
        p = parts[i]
        gsub(/^[ \t]+|[ \t]+$/, "", p)
        gsub(/^["'"'"']|["'"'"']$/, "", p)
        if (p != "") out = (out == "" ? p : out "," p)
      }
      return out
    }
    NR == 1 && $0 == "---" { inb = 1; next }
    inb && $0 == "---" { exit }
    !inb { exit }
    inb {
      line = $0
      sub(/[ \t]+#.*$/, "", line)
      match(line, /^[ \t]*/); ind = RLENGTH
      t = line; gsub(/^[ \t]+|[ \t]+$/, "", t)
      if (t == "") next

      if (substr(t, 1, 2) == "- ") {
        v = flat(substr(t, 3))
        if (sub_key != "") acc[sub_key] = (acc[sub_key] == "" ? v : acc[sub_key] "," v)
        else if (top == "targets") acc["targets"] = (acc["targets"] == "" ? v : acc["targets"] "," v)
        next
      }

      i = index(t, ":")
      if (i == 0) next
      k = substr(t, 1, i - 1); v = substr(t, i + 1)
      gsub(/^[ \t]+|[ \t]+$/, "", k); gsub(/^[ \t]+|[ \t]+$/, "", v)

      if (ind == 0) {
        top = k; sub_key = ""
        if (k == "targets" && v != "") acc["targets"] = flat(v)
        next
      }
      if (top == "requires") {
        if (k == "bins" || k == "env") {
          if (v != "") { acc[k] = flat(v); sub_key = "" }
          else sub_key = k
        } else sub_key = ""
      }
    }
    END {
      if (acc["targets"] != "") printf "targets\t%s\n", acc["targets"]
      if (acc["bins"]    != "") printf "bins\t%s\n",    acc["bins"]
      if (acc["env"]     != "") printf "env\t%s\n",     acc["env"]
    }
  ' "$1" 2>/dev/null
}

field() { printf '%s\n' "$1" | awk -F'\t' -v k="$2" '$1==k {print $2; exit}'; }

# --------------------------------------------------------------------- plan
INSTALL=()
SKIP=()
PRESENT=()

while IFS= read -r skill_md; do
  [ -n "$skill_md" ] || continue
  sdir="$(dirname "$skill_md")"
  name="$(basename "$sdir")"
  tier_dir="$(basename "$(dirname "$sdir")")"
  [ "$tier_dir" = "skills" ] && tier_dir="universal"

  meta="$(read_meta "$skill_md")"
  targets="$(field "$meta" targets)"
  note=""
  if [ -z "$targets" ]; then
    if is_known_tier "$tier_dir"; then
      targets="$tier_dir"
    else
      targets="universal"
    fi
    note=" (no targets declared, defaulted to $targets from its directory)"
  fi

  # does this machine want it?
  wanted=1
  unknown_targets=""
  old_ifs="$IFS"; IFS=','
  for tk in $targets; do
    if machine_wants "$tk"; then wanted=0; fi
    if ! is_known_tier "$tk" && [ "$tk" != "$MACHINE" ]; then
      unknown_targets="$unknown_targets $tk"
    fi
  done
  IFS="$old_ifs"

  if [ "$wanted" -ne 0 ]; then
    if [ -n "$unknown_targets" ]; then
      SKIP[${#SKIP[@]}]="$name|targets [$targets], not a tier in this repo and not machine $MACHINE"
    else
      SKIP[${#SKIP[@]}]="$name|targets [$targets], this machine has [$(printf '%s ' ${TIERS[@]+"${TIERS[@]}"} | sed 's/ $//')]"
    fi
    continue
  fi

  # requirements
  missing=""
  bins="$(field "$meta" bins)"
  envs="$(field "$meta" env)"
  old_ifs="$IFS"; IFS=','
  for b in $bins; do
    [ -n "$b" ] || continue
    command -v "$b" >/dev/null 2>&1 || missing="$missing bin:$b"
  done
  for e in $envs; do
    [ -n "$e" ] || continue
    eval "val=\${$e:-}"
    [ -n "$val" ] || missing="$missing env:$e"
  done
  IFS="$old_ifs"

  if [ -n "$missing" ]; then
    SKIP[${#SKIP[@]}]="$name|missing$missing. A skill that cannot run is worse than an absent one."
    continue
  fi

  target="$DEST/$name"
  if [ -L "$target" ]; then
    link="$(readlink "$target")"
    if [ "$link" = "$sdir" ]; then
      PRESENT[${#PRESENT[@]}]="$name|symlink is correct"
    else
      INSTALL[${#INSTALL[@]}]="$name|relink, symlink points at $link"
    fi
  elif [ -d "$target" ]; then
    PRESENT[${#PRESENT[@]}]="$name|a real directory, compare contents before you trust it"
  else
    INSTALL[${#INSTALL[@]}]="$name|from $tier_dir/$name$note"
  fi
done < <(find "$REPO/skills" -name SKILL.md -type f 2>/dev/null | LC_ALL=C sort)

# -------------------------------------------------------------------- output
printf 'fleet-plan  DRY RUN, nothing is changed\n'
printf '  repo     %s\n' "$REPO"
printf '  machine  %s\n' "$MACHINE"
printf '  tiers    %s\n' "$(printf '%s ' ${TIERS[@]+"${TIERS[@]}"} | sed 's/ $//')"
printf '  runtime  %s\n' "$RUNTIME"
printf '  dest     %s%s\n' "$DEST" "$([ -d "$DEST" ] || printf ' (does not exist yet)')"
printf '\n'

show() { # show <heading> <count> <lines...>
  printf '%s\n' "$1"
  shift
  if [ "$#" -eq 0 ]; then
    printf '  none\n\n'
    return
  fi
  for row in "$@"; do
    printf '  %-22s %s\n' "${row%%|*}" "${row#*|}"
  done
  printf '\n'
}

show "INSTALL"       ${INSTALL[@]+"${INSTALL[@]}"}
show "SKIP"          ${SKIP[@]+"${SKIP[@]}"}
show "ALREADY THERE" ${PRESENT[@]+"${PRESENT[@]}"}

printf 'summary  %d to install, %d skipped, %d already there\n' \
  "${#INSTALL[@]}" "${#SKIP[@]}" "${#PRESENT[@]}"
printf 'Run the apply step yourself. This script does not touch the machine.\n'
exit 0
