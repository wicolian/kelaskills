#!/usr/bin/env bash
#
# retro-scan.sh - count what your coding agents actually got wrong.
#
# READ ONLY. This script opens transcript files for reading and never writes,
# moves, truncates or deletes one. It creates two scratch files under the system
# temporary directory via mktemp and removes them on exit. Nothing else is
# written, and the only output is text on stdout.
#
# PRIVACY. Transcripts hold your source code, your customers' data, your
# secrets and your private conversation. This script runs entirely on your
# machine and sends nothing anywhere. It truncates and redacts the command
# snippets it prints, but a printed line can still carry a path or a filename
# you would not publish. Read the output before you paste it into anything.
#
# Compatible with macOS bash 3.2. No associative arrays, no ${x^^}.
# Uses python3 for JSON. Degrades to a grep-only count when python3 is absent.
#
# Usage:
#   ./retro-scan.sh                      discover stores, then scan each one
#   ./retro-scan.sh --discover           discover only, print nothing else
#   ./retro-scan.sh --store DIR          scan one store
#   ./retro-scan.sh --since 2026-08-01   only sessions modified on or after
#   ./retro-scan.sh --max-files 500      cap files per store (0 = no cap)
#   ./retro-scan.sh --max-mb 8           cap bytes read per file (0 = no cap)
#   ./retro-scan.sh --top 15             how many destructive hits to print
#   ./retro-scan.sh --examples           also print the matched correction text
#                                        (PRIVATE: this prints your own words)
#
set -uo pipefail

MODE="full"
STORES_ARG=""
SINCE=""
MAX_FILES=300
MAX_MB=8
TOP=15
EXAMPLES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --discover)   MODE="discover" ;;
    --store)      STORES_ARG="${STORES_ARG} $2"; shift ;;
    --since)      SINCE="$2"; shift ;;
    --max-files)  MAX_FILES="$2"; shift ;;
    --max-mb)     MAX_MB="$2"; shift ;;
    --top)        TOP="$2"; shift ;;
    --examples)   EXAMPLES=1 ;;
    -h|--help)    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

HAVE_PY=0
command -v python3 >/dev/null 2>&1 && HAVE_PY=1

hr() { printf '%s\n' "----------------------------------------------------------------"; }

# ---------------------------------------------------------------- discovery --
# Do not hardcode a list. These paths move between versions. Find the transcript
# stores by looking for clusters of .jsonl files under the dot-directories in
# $HOME, then rank them by total size.

DISCOVERED=""

discover() {
  local tmp roots
  tmp="$(mktemp -t retroscan)" || return 1
  : >"$DISCOVERED"

  roots=""
  for d in "$HOME"/.[a-zA-Z]*; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in
      .Trash|.cache|.npm|.bun|.cargo|.rustup|.gem|.git|.docker|.vscode*|.node*|.pyenv|.nvm|.local)
        continue ;;
    esac
    roots="${roots} ${d}"
  done
  [ -z "$roots" ] && { rm -f "$tmp"; return 1; }

  # shellcheck disable=SC2086
  find $roots -maxdepth 6 -type d -name node_modules -prune -o \
       -type f \( -name '*.jsonl' -o -name '*.log' \) -print 2>/dev/null \
    | while IFS= read -r f; do
        sz=$(wc -c <"$f" 2>/dev/null | tr -d ' ')
        [ -z "$sz" ] && sz=0
        # group key: the two path components below $HOME
        key=$(printf '%s' "${f#"$HOME"/}" | awk -F/ '{ if (NF>=3) print $1"/"$2; else print $1 }')
        printf '%s\t%s\n' "$key" "$sz"
      done > "$tmp"

  if [ ! -s "$tmp" ]; then rm -f "$tmp"; return 1; fi

  awk -F'\t' '{ n[$1]++; b[$1]+=$2 }
    END { for (k in n) printf "%d\t%d\t%s\n", b[k], n[k], k }' "$tmp" \
    | sort -rn | head -20 > "${tmp}.g"

  awk -F'\t' '
      function human(x) {
        if (x > 1073741824) return sprintf("%.1fG", x/1073741824)
        if (x > 1048576)    return sprintf("%.1fM", x/1048576)
        if (x > 1024)       return sprintf("%.0fK", x/1024)
        return x "B"
      }
      { printf "  %-8s %6d files  ~/%s\n", human($1), $2, $3 }' "${tmp}.g"

  # A store worth scanning: many files, not a log directory. Five or more
  # session files is the cut. Everything below that is config or a stray log.
  awk -F'\t' -v home="$HOME" '$2 >= 5 { print home "/" $3 }' "${tmp}.g" \
    | grep -vE '/(logs|log|cache|browser-profile|debug)$' > "$DISCOVERED"

  rm -f "$tmp" "${tmp}.g"
  return 0
}

# ----------------------------------------------------------------- fallback --
# python3 is present on every macOS and every mainstream Linux, but say so
# plainly rather than silently reporting nothing.

grep_only() {
  local store="$1" nfiles ncorr
  nfiles=$(find "$store" -type f -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')
  ncorr=$(find "$store" -type f -name '*.jsonl' 2>/dev/null \
    | head -200 \
    | xargs grep -icE "that is wrong|not what i asked|i did ?n.?t ask|undo that|stop doing" 2>/dev/null \
    | awk -F: '{s+=$NF} END {print s+0}')
  printf '  python3 not found. grep-only mode, counts are approximate.\n'
  printf '  files: %s   lines matching a correction phrase: %s\n' "$nfiles" "$ncorr"
}

# ------------------------------------------------------------------ scanner --

scan_store() {
  local store="$1"
  hr
  printf 'STORE  %s\n' "${store/#$HOME/~}"
  hr
  if [ ! -d "$store" ]; then
    printf '  not a directory, skipped\n'
    return 0
  fi
  if [ "$HAVE_PY" = "0" ]; then
    grep_only "$store"
    return 0
  fi

  RS_STORE="$store" RS_SINCE="$SINCE" RS_MAXFILES="$MAX_FILES" \
  RS_MAXMB="$MAX_MB" RS_TOP="$TOP" RS_EXAMPLES="$EXAMPLES" python3 - <<'PYEOF'
import json, os, re, sys, collections, datetime

store    = os.environ["RS_STORE"]
since    = os.environ.get("RS_SINCE") or ""
maxfiles = int(os.environ.get("RS_MAXFILES") or 0)
maxmb    = int(os.environ.get("RS_MAXMB") or 0)
top      = int(os.environ.get("RS_TOP") or 15)
cap      = maxmb * 1024 * 1024 if maxmb else 0

# --- what counts as the human saying no ------------------------------------
# Tuned against real transcripts. Every loosening of these costs precision
# fast: a bare "stop" matched a hundred worker dispatch prompts before it was
# tightened, and "i said" matched agreement as often as complaint. Match only
# the head of the message, because a correction arrives at the top and a long
# spec that mentions "revert the migration" halfway down is not one.
CORRECTION = [
    (r"^\s*(no|nope|nah)\b[\s,.!]", "flat no"),
    (r"\b(that|this|it)('| i)?s (just )?(wrong|incorrect|not right)\b", "that is wrong"),
    (r"\bnot what i (asked|wanted|said|meant)\b", "not what I asked"),
    (r"\bi did ?n[o']?t ask (for|you)\b", "I did not ask"),
    (r"^\s*\W*(undo|revert|roll ?back) (that|this|it|those)\b", "undo that"),
    (r"\bstop\b.{0,20}\b(doing|that|it|now)\b", "stop"),
    (r"\byou (broke|deleted|removed|killed|overwrote|reverted)\b", "you broke it"),
    (r"\bdo ?n[o']?t (do|touch|change|add|create) (that|this|it)\b", "do not do that"),
    (r"\bwhy (did|would) you\b", "why did you"),
    (r"\bi (already )?(said|told you) (to|not to|that)\b", "I already said"),
    (r"\bthat[' ]?s not (the|what)\b", "not the thing"),
    (r"\bread (the|my) (instructions|prompt|message) again\b", "re-read it"),
    (r"\byou (missed|skipped|forgot)\b", "you skipped"),
    (r"\bwrong (file|branch|repo|directory|command|approach)\b", "wrong target"),
]
CORRECTION = [(re.compile(p, re.I), label) for p, label in CORRECTION]
CORRECTION_HEAD = 300

# --- destructive or wrong-target shell ------------------------------------
# Matched per command segment, never against the whole block. A block that
# writes a document mentioning `pkill` is not a process kill, and matching the
# block gets you that false positive every time.
DESTRUCTIVE = [
    (r"^rm\s+(-[a-zA-Z]*[rf][a-zA-Z]*\s+)+", "rm recursive/force"),
    (r"^git\s+reset\s+--hard\b", "git reset --hard"),
    (r"^git\s+checkout\s+(--\s+)?\.\s*$", "git checkout ."),
    (r"^git\s+clean\s+-[a-zA-Z]*[fd]", "git clean"),
    (r"^git\s+push\b.*(--force(-with-lease)?|\s-f\b)", "force push"),
    (r"^git\s+branch\s+-D\b", "branch force delete"),
    (r"^git\s+commit\b.*--amend\b", "amend"),
    (r"^git\s+stash\b(?!\s+(list|show))", "git stash"),
    (r"--no-verify\b", "hooks bypassed"),
    (r"^(pkill|killall)\b", "pkill / killall"),
    (r"^kill\s+-9\b", "kill -9"),
    (r"(DROP\s+TABLE|TRUNCATE\s+TABLE|DELETE\s+FROM\s+\w+\s*;)", "destructive SQL"),
    (r"^chmod\s+-R\s+777\b", "chmod 777"),
    (r"^(npm|yarn|pnpm)\s+publish\b", "publish"),
    (r"^docker\s+(system\s+prune|volume\s+rm)\b", "docker prune"),
]
DESTRUCTIVE = [(re.compile(p), label) for p, label in DESTRUCTIVE]

# An `rm -rf` inside a scratch directory is housekeeping. An `rm -rf` on a
# home path, a parent, a bare glob or the root is the one that ends a night.
RM_SAFE = re.compile(r"^rm\s+(-\S+\s+)*(/tmp/|/var/folders/|\.?/?\S*\.DS_Store|\$TMPDIR)")

SEGMENT = re.compile(r"(?:\n|;|&&|\|\||\|)+")

def segments(cmd):
    """A shell block split into command segments, each stripped of leading noise."""
    for raw in SEGMENT.split(cmd):
        s = raw.strip()
        # strip leading redirections, subshell parens, env assignments, sudo
        s = re.sub(r"^[(\s]+", "", s)
        s = re.sub(r"^(sudo|command|time|nohup|env)\s+", "", s)
        s = re.sub(r"^([A-Za-z_][A-Za-z0-9_]*=\S*\s+)+", "", s)
        if s:
            yield s

SECRET = re.compile(r"(sk-[A-Za-z0-9_-]{8,}|ghp_[A-Za-z0-9]{8,}|xox[abprs]-[A-Za-z0-9-]{8,}"
                    r"|AKIA[0-9A-Z]{12,}|eyJ[A-Za-z0-9_-]{20,}|Bearer\s+[A-Za-z0-9._-]{12,})")

# Synthetic "user" turns the harness injects. Counting these as human messages
# inflates the denominator and hides a real correction rate.
SYNTHETIC = re.compile(
    r"^\s*(<command-name>|<command-message>|<local-command|<bash-|<system-reminder>"
    r"|Caveat:|\[Request interrupted|<environment_context>|<user_instructions>"
    r"|# Context from my IDE setup|<task_context>|API Error|tool_use_id)")

def redact(s):
    s = SECRET.sub("<redacted>", s)
    s = " ".join(s.split())
    return s[:150] + ("..." if len(s) > 150 else "")

def as_text(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        out = []
        for b in c:
            if isinstance(b, dict):
                if b.get("type") in ("text", "input_text", "output_text"):
                    out.append(b.get("text") or "")
                elif b.get("type") == "tool_result":
                    return ""          # a tool result is not a human message
            elif isinstance(b, str):
                out.append(b)
        return "\n".join(out)
    return ""

# --- normalise both known schemas into one record stream -------------------
# Claude Code: {"type":"user|assistant","message":{"role","content","model"},
#               "timestamp","cwd","sessionId","isSidechain"}
# Codex:       {"type":"event_msg|response_item|turn_context","payload":{...},
#               "timestamp"}
# Anything else falls through and is counted as unparsed.

def records(path, fh):
    model = None
    read = 0
    for line in fh:
        read += len(line)
        if cap and read > cap:
            yield ("truncated", None, None, None)
            return
        line = line.strip()
        if not line or line[0] != "{":
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        t = d.get("type")
        ts = d.get("timestamp") or d.get("ts")
        if not isinstance(ts, str):
            ts = None          # some stores use an epoch int; do not sort on it

        # ---- Cursor shape: {"role":..., "message":{"content":[...]}}
        # No type, no timestamp, no model id. The per-model split is simply not
        # available from this store. Say that rather than inventing a bucket.
        if t is None and d.get("role") in ("user", "assistant") \
                and isinstance(d.get("message"), dict):
            if d["role"] == "assistant":
                yield ("assistant", model, ts, d["message"].get("content"))
            else:
                txt = as_text(d["message"].get("content"))
                mq = re.search(r"<user_query>\s*(.*?)\s*</user_query>", txt, re.S)
                yield ("human", model, ts, mq.group(1) if mq else txt)
            continue

        # ---- Claude Code shape
        if t in ("user", "assistant") and isinstance(d.get("message"), dict):
            m = d["message"]
            if t == "assistant":
                model = m.get("model") or model
                yield ("assistant", model, ts, m.get("content"))
            else:
                if d.get("isSidechain"):
                    yield ("sidechain", model, ts, None)
                else:
                    yield ("human", model, ts, as_text(m.get("content")))
            continue

        # ---- Codex shape
        if t == "turn_context" and isinstance(d.get("payload"), dict):
            model = d["payload"].get("model") or model
            continue
        if t == "event_msg" and isinstance(d.get("payload"), dict):
            p = d["payload"]
            if p.get("type") == "user_message":
                yield ("human", model, ts, p.get("message") or "")
            elif p.get("type") == "agent_message":
                yield ("assistant", model, ts, None)
            continue
        if t == "response_item" and isinstance(d.get("payload"), dict):
            p = d["payload"]
            if p.get("type") == "function_call":
                yield ("tool", model, ts, shell_arg(p.get("arguments")))
            elif p.get("type") == "message":
                # Older sessions carry no event_msg records at all. Keep these
                # as a fallback and only use them when the file had nothing else,
                # because in newer sessions they duplicate the event_msg stream.
                role = p.get("role")
                if role == "user":
                    yield ("alt_human", model, ts, as_text(p.get("content")))
                elif role == "assistant":
                    yield ("alt_assistant", model, ts, None)
            continue

        yield ("other", model, ts, None)

def shell_arg(raw):
    """Codex stores tool arguments as a JSON string. Pull the command out of it.
    Matching the raw JSON instead splits on the quoting and reports garbage."""
    if not raw:
        return ""
    try:
        a = json.loads(raw)
    except Exception:
        return raw
    if isinstance(a, dict):
        c = a.get("command") or a.get("cmd") or a.get("script")
        if isinstance(c, list):
            # ["zsh","-lc","<the actual command>"] is the usual shape
            return c[-1] if c and isinstance(c[-1], str) else " ".join(map(str, c))
        if isinstance(c, str):
            return c
    return ""

def find_destructive(cmd):
    """(label, offending segment) for the first destructive segment, or None."""
    if not cmd:
        return None
    for seg in segments(cmd):
        for rx, label in DESTRUCTIVE:
            if rx.search(seg):
                if label == "rm recursive/force" and RM_SAFE.match(seg):
                    continue
                return (label, seg)
    return None

def tool_commands(content):
    """Shell command strings out of an assistant content block."""
    if not isinstance(content, list):
        return
    for b in content:
        if isinstance(b, dict) and b.get("type") == "tool_use":
            inp = b.get("input")
            if isinstance(inp, dict):
                c = inp.get("command")
                if isinstance(c, str):
                    yield c
                elif isinstance(c, list):
                    yield " ".join(str(x) for x in c)

# --- gather files ----------------------------------------------------------
files = []
for root, dirs, names in os.walk(store):
    dirs[:] = [d for d in dirs if d != "node_modules"]
    for n in names:
        if n.endswith(".jsonl"):
            p = os.path.join(root, n)
            try:
                st = os.stat(p)
            except OSError:
                continue
            files.append((st.st_mtime, st.st_size, p))

if not files:
    print("  no .jsonl session files here. try --store on a different path.")
    sys.exit(0)

if since:
    try:
        floor = datetime.datetime.strptime(since, "%Y-%m-%d").timestamp()
        files = [f for f in files if f[0] >= floor]
    except ValueError:
        print("  --since must be YYYY-MM-DD, ignoring it")

files.sort(reverse=True)                      # newest first
total_found = len(files)
if maxfiles and len(files) > maxfiles:
    files = files[:maxfiles]

# --- count -----------------------------------------------------------------
by_model_assistant = collections.Counter()
by_model_human     = collections.Counter()
by_model_corr      = collections.Counter()
corr_kind          = collections.Counter()
corr_examples      = []
destr_kind         = collections.Counter()
destr_hits         = []
sessions_ok = sessions_unparsed = truncated = 0
sidechain = 0
tmin = tmax = None
bytes_read = 0

for mtime, size, path in files:
    got = False
    # A human message that arrives before the first assistant reply has no model
    # on it yet. Hold it and attribute it to this session's model at end of file,
    # otherwise every session's opening request lands in an "unknown" bucket and
    # the first turn, which is the one most likely to be misread, disappears.
    pending = []
    fallback = []
    file_model = None
    last_model = None
    try:
        fh = open(path, "r", errors="replace")
    except OSError:
        continue
    with fh:
        for kind, model, ts, payload in records(path, fh):
            if kind in ("alt_human", "alt_assistant"):
                fallback.append((kind, model, ts, payload))
                continue
            if kind == "truncated":
                truncated += 1
                break
            m = model or "unknown"
            if model: last_model = model
            if ts:
                if tmin is None or ts < tmin: tmin = ts
                if tmax is None or ts > tmax: tmax = ts
            if kind == "assistant":
                got = True
                if file_model is None and model:
                    file_model = model
                by_model_assistant[m] += 1
                for cmd in tool_commands(payload):
                    hit = find_destructive(cmd)
                    if hit:
                        destr_kind[hit[0]] += 1
                        destr_hits.append((ts or "?", hit[0], os.path.basename(path), redact(hit[1])))
            elif kind == "human":
                text = payload or ""
                if not text.strip() or SYNTHETIC.match(text):
                    continue
                got = True
                head = text[:CORRECTION_HEAD]
                label = None
                for rx, lab in CORRECTION:
                    if rx.search(head):
                        label = lab
                        break
                if model is None:
                    pending.append((label, head))
                else:
                    by_model_human[m] += 1
                    if label:
                        by_model_corr[m] += 1
                        corr_kind[label] += 1
                        if len(corr_examples) < 40:
                            corr_examples.append((label, m, redact(head[:120])))
            elif kind == "tool":
                got = True
                hit = find_destructive(payload or "")
                if hit:
                    destr_kind[hit[0]] += 1
                    destr_hits.append((ts or "?", hit[0], os.path.basename(path), redact(hit[1])))
            elif kind == "sidechain":
                sidechain += 1

    if not got and fallback:
        for kind, model, ts, payload in fallback:
            m = model or "unknown"
            if ts:
                if tmin is None or ts < tmin: tmin = ts
                if tmax is None or ts > tmax: tmax = ts
            if kind == "alt_assistant":
                got = True
                if file_model is None and model:
                    file_model = model
                by_model_assistant[m] += 1
            else:
                text = payload or ""
                if not text.strip() or SYNTHETIC.match(text):
                    continue
                got = True
                head = text[:CORRECTION_HEAD]
                label = None
                for rx, lab in CORRECTION:
                    if rx.search(head):
                        label = lab
                        break
                if model is None:
                    pending.append((label, head))
                else:
                    by_model_human[m] += 1
                    if label:
                        by_model_corr[m] += 1
                        corr_kind[label] += 1
                        if len(corr_examples) < 40:
                            corr_examples.append((label, m, redact(head[:120])))

    resolved = file_model or last_model or "unknown"
    for label, head in pending:
        by_model_human[resolved] += 1
        if label:
            by_model_corr[resolved] += 1
            corr_kind[label] += 1
            if len(corr_examples) < 40:
                corr_examples.append((label, resolved, redact(head[:120])))

    bytes_read += min(size, cap) if cap else size
    if got: sessions_ok += 1
    else:   sessions_unparsed += 1

# --- report ----------------------------------------------------------------
tot_h = sum(by_model_human.values())
tot_a = sum(by_model_assistant.values())
tot_c = sum(by_model_corr.values())

print("  sessions found      %d" % total_found)
print("  sessions scanned    %d  (%d yielded no known record shape)"
      % (len(files), sessions_unparsed))
if truncated:
    print("  files truncated     %d  (hit the --max-mb cap)" % truncated)
print("  bytes read          %.1f MB" % (bytes_read / 1048576.0))
print("  date range          %s  to  %s" % ((tmin or "?")[:19], (tmax or "?")[:19]))
print("  human messages      %d" % tot_h)
print("  assistant messages  %d" % tot_a)
if sidechain:
    print("  subagent messages   %d  (excluded from the rate)" % sidechain)

if sessions_ok == 0:
    print()
    print("  This store parsed but matched no known schema. Dump one record and")
    print("  adapt the normaliser:  head -1 <file> | python3 -m json.tool")
    sys.exit(0)

print()
print("  CORRECTIONS PER 100 HUMAN MESSAGES")
if tot_h:
    print("  %-34s %7s %7s %9s" % ("model", "human", "corr", "per 100"))
    rows = sorted(by_model_human.items(), key=lambda kv: -kv[1])
    for m, h in rows:
        c = by_model_corr.get(m, 0)
        rate = (100.0 * c / h) if h else 0.0
        print("  %-34s %7d %7d %9.1f" % (m[:34], h, c, rate))
    print("  %-34s %7d %7d %9.1f" % ("ALL", tot_h, tot_c, 100.0 * tot_c / tot_h))
    print()
    print("  Raw counts follow whichever model you used most. Read the rate, and")
    print("  read it knowing task difficulty is not held constant.")
else:
    print("  no human messages matched. check the SYNTHETIC filter.")

if corr_kind:
    print()
    print("  WHAT THE CORRECTION SOUNDED LIKE")
    for label, n in corr_kind.most_common(10):
        print("    %-22s %5d" % (label, n))
    if os.environ.get("RS_EXAMPLES") == "1":
        print()
        print("  matched messages (first 120 chars, redacted, PRIVATE)")
        for label, m, snip in corr_examples[:top]:
            print("    [%s] %s" % (label, snip))
        print()
        print("  Read these. A phrase match is a candidate, not a correction.")

print()
print("  DESTRUCTIVE OR WRONG-TARGET COMMANDS")
if destr_kind:
    for label, n in destr_kind.most_common():
        print("    %-22s %5d" % (label, n))
    print()
    print("  most recent hits (command text truncated and redacted):")
    for ts, label, fn, cmd in sorted(destr_hits, reverse=True)[:top]:
        print("    %s  %-20s %s" % (ts[:19], label, fn[:20]))
        print("        %s" % cmd)
    print()
    print("  Every one of these is a candidate, not a verdict. An intentional")
    print("  `git reset --hard` you asked for is a false positive. Open the")
    print("  session before you write a rule.")
else:
    print("    none matched. That is a clean result only if the patterns cover")
    print("    the tools you actually use.")
PYEOF
}

# --------------------------------------------------------------------- main --

printf 'retro-scan  read only, nothing leaves this machine\n\n'

DISCOVERED="$(mktemp -t retroscan-found)" || exit 2
trap 'rm -f "$DISCOVERED"' EXIT INT TERM

if [ -n "$STORES_ARG" ]; then
  STORES="$STORES_ARG"
else
  printf 'TRANSCRIPT STORES FOUND UNDER ~/ (by total size)\n'
  if ! discover; then
    printf '  none found. Your agent may keep transcripts elsewhere. Check its\n'
    printf '  docs, then rerun with --store <path>.\n'
    exit 0
  fi
  printf '\n'
  STORES="$(tr '\n' ' ' <"$DISCOVERED")"
fi

if [ "$MODE" = "discover" ]; then
  exit 0
fi

if [ -z "$STORES" ]; then
  printf 'No known session store to scan. Rerun with --store <path>.\n'
  exit 0
fi

for s in $STORES; do
  scan_store "$s"
  printf '\n'
done

hr
printf 'Before you change any config, read references/failure-taxonomy.md.\n'
printf 'A count is a candidate. The session is the evidence.\n'
