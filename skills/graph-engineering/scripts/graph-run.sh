#!/usr/bin/env bash
# graph-run.sh - a minimal agent graph in shell. No framework.
#
#   splitter -> fan-out workers -> code-node merge -> gate -> [accept | return unit]
#                                                       |
#                                                       +-> learning edge (constraints file)
#
# Every piece of the SKILL.md vocabulary is here and nothing else is:
#   - width cap on the fan-out, with a named reason
#   - own context per worker (a separate process)
#   - a completeness check that is CODE, not a model
#   - a gate whose first input is deterministic
#   - a return that carries UNIT / VERDICT / REASON / EVIDENCE / SCOPE
#   - return the unit, never the batch
#   - three attempts, then stop and re-plan
#   - a learning edge that lands in the splitter's brief
#
# Usage:
#   ./graph-run.sh units.txt prompts/worker.tmpl.md
#
# Environment:
#   GRAPH_OUT          output directory                    (default: .graph-run)
#   GRAPH_WIDTH        max concurrent workers              (default: 4)
#   GRAPH_WIDTH_REASON why that number                     (default: unset -> refuses to run)
#   GRAPH_ATTEMPTS     corrections per unit before halting (default: 3)
#   GRAPH_WORKER_CMD   command template for one worker     (default: claude -p ...)
#   GRAPH_GATE_CMD     deterministic check for one unit    (default: result file is non-empty JSON)
#   GRAPH_CONSTRAINTS  the learning edge file              (default: $GRAPH_OUT/constraints.md)
#   GRAPH_MODEL        model alias passed to the default worker (default: haiku)
#   GRAPH_BUDGET_USD   per-worker spend cap                (default: 0.25)
#
# In the command templates, {{UNIT}} is replaced with the unit id, {{PROMPT}} with
# the rendered prompt file path, and {{OUT}} with the result file path.

set -euo pipefail

UNITS_FILE="${1:?usage: graph-run.sh UNITS_FILE PROMPT_TEMPLATE}"
PROMPT_TMPL="${2:?usage: graph-run.sh UNITS_FILE PROMPT_TEMPLATE}"

OUT="${GRAPH_OUT:-.graph-run}"
WIDTH="${GRAPH_WIDTH:-4}"
ATTEMPTS="${GRAPH_ATTEMPTS:-3}"
MODEL="${GRAPH_MODEL:-haiku}"
BUDGET="${GRAPH_BUDGET_USD:-0.25}"
CONSTRAINTS="${GRAPH_CONSTRAINTS:-$OUT/constraints.md}"

# A width cap with no named constraint is a guess, and guesses get raised under
# pressure. Refuse to run without one.
: "${GRAPH_WIDTH_REASON:?set GRAPH_WIDTH_REASON to the constraint that binds the fan-out (rate limit, dev server, machine load)}"

# Note the quoting: `{{PROMPT}}` cannot live inside a `${VAR:-default}` default,
# because the `}}` closes the expansion early. Build the default separately.
DEFAULT_WORKER_CMD='claude -p "$(cat {{PROMPT}})"'" --model $MODEL --output-format json --max-budget-usd $BUDGET --permission-mode dontAsk"
WORKER_CMD="${GRAPH_WORKER_CMD:-$DEFAULT_WORKER_CMD}"
GATE_CMD="${GRAPH_GATE_CMD:-}"

mkdir -p "$OUT/prompts" "$OUT/results" "$OUT/returns"
: > "$OUT/ledger.txt"
[ -f "$CONSTRAINTS" ] || printf '# Derived constraints\n\n' > "$CONSTRAINTS"

log() { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*" >&2; }

# ---------------------------------------------------------------- splitter ---
# Reads the units and renders one self-contained brief per unit. The constraints
# file is pasted in, not referenced: a worker has no "above" to look at.
render_brief() {
  local unit="$1" dest="$OUT/prompts/$unit.md"
  {
    printf '## Constraints from previous runs\n\n'
    cat "$CONSTRAINTS"
    printf '\n## Your unit\n\n%s\n\n' "$unit"
    printf '## Brief\n\n'
    sed "s|{{UNIT}}|$unit|g" "$PROMPT_TMPL"
  } > "$dest"
  printf '%s' "$dest"
}

# ------------------------------------------------------------------ worker ---
run_worker() {
  local unit="$1" prompt="$2" out="$OUT/results/$unit.json"
  local cmd="$WORKER_CMD"
  cmd="${cmd//\{\{UNIT\}\}/$unit}"
  cmd="${cmd//\{\{PROMPT\}\}/$prompt}"
  cmd="${cmd//\{\{OUT\}\}/$out}"
  # The pipefail trap: never `| tee` without capturing status first.
  if eval "$cmd" > "$out" 2> "$OUT/results/$unit.err"; then
    printf '%s\n' "$unit" >> "$OUT/ledger.txt"
  else
    # A failure is data. Record it and let the batch finish.
    printf '{"unit":"%s","status":"error"}\n' "$unit" > "$out"
    printf '%s\n' "$unit" >> "$OUT/ledger.txt"
    log "worker error: $unit (see $OUT/results/$unit.err)"
  fi
}

# ----------------------------------------------------------------- fan-out ---
fan_out() {
  local running=0 unit prompt
  while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    prompt="$(render_brief "$unit")"
    run_worker "$unit" "$prompt" &
    running=$((running + 1))
    if [ "$running" -ge "$WIDTH" ]; then wait -n 2>/dev/null || wait; running=$((running - 1)); fi
  done < "$1"
  wait
}

# --------------------------------------------------- code node: completeness --
# This is CODE. A model asked "did everything come back?" will synthesise over a
# gap. A script cannot.
completeness() {
  local expected received unit
  expected=$(grep -cve '^[[:space:]]*$' "$UNITS_FILE")
  # Count files that exist AND are non-empty. Counting the ledger instead would
  # miss a worker killed hard by the OOM killer or a timeout, which is exactly
  # the case this check exists for.
  : > "$OUT/landed.txt"
  while IFS= read -r unit; do
    [ -n "$unit" ] || continue
    [ -s "$OUT/results/$unit.json" ] && printf '%s\n' "$unit" >> "$OUT/landed.txt"
  done < "$UNITS_FILE"
  received=$(grep -cve '^[[:space:]]*$' "$OUT/landed.txt" || true)
  log "completeness: $received/$expected"
  if [ "$received" -ne "$expected" ]; then
    log "INCOMPLETE. missing:"
    comm -13 <(sort -u "$OUT/landed.txt") <(grep -ve '^[[:space:]]*$' "$UNITS_FILE" | sort -u) >&2
    return 1
  fi
}

# -------------------------------------------------------------------- gate ---
# Deterministic first. A model's own assessment is the last input, never the only
# one. Returns 0 for green, 1 for red, and writes the return payload on red.
gate() {
  local unit="$1" out="$OUT/results/$unit.json" reason evidence
  if [ -n "$GATE_CMD" ]; then
    local cmd="$GATE_CMD"
    cmd="${cmd//\{\{UNIT\}\}/$unit}"
    cmd="${cmd//\{\{OUT\}\}/$out}"
    if eval "$cmd" > "$OUT/returns/$unit.gate" 2>&1; then return 0; fi
    reason="gate command failed"
    evidence="$(tail -n 5 "$OUT/returns/$unit.gate" | tr '\n' ' ')"
  else
    # Default check: a non-empty result that is not an error. Weak on purpose,
    # so that shipping without a real GATE_CMD is visibly a placeholder.
    if [ -s "$out" ] && ! grep -q '"status":"error"' "$out"; then return 0; fi
    reason="empty or errored result"
    evidence="$(head -c 200 "$out" 2>/dev/null || echo '<no output>')"
  fi

  # Five fields travel with a return. SCOPE is the one that stops a one-unit
  # correction growing into a diff nobody reviewed.
  cat > "$OUT/returns/$unit.md" <<RET
UNIT       $unit
VERDICT    red
REASON     $reason
EVIDENCE   $evidence
SCOPE      fix this unit only, do not touch any other unit
RET
  return 1
}

# ------------------------------------------------------------ learning edge ---
# Lands in the splitter's brief for every later run, not in the worker's
# instructions. A confirmed cause becomes a rule.
learn() {
  printf -- '- %s\n' "$1" >> "$CONSTRAINTS"
  log "learned: $1"
}

# -------------------------------------------------------------------- main ---
log "width $WIDTH ($GRAPH_WIDTH_REASON), attempts $ATTEMPTS"
log "phase 1: fan-out"
fan_out "$UNITS_FILE"

log "phase 2: completeness (code node)"
completeness || { log "halting: synthesising over a gap is worse than reporting one"; exit 1; }

log "phase 3: gate"
red=0
while IFS= read -r unit; do
  [ -n "$unit" ] || continue
  attempt=1
  until gate "$unit"; do
    if [ "$attempt" -ge "$ATTEMPTS" ]; then
      log "$unit failed $ATTEMPTS corrections. The problem is in the plan, and the loop cannot see the plan. Stopping this unit."
      red=$((red + 1))
      break
    fi
    log "$unit red, attempt $attempt. Returning the UNIT, not the batch."
    # Re-render the brief from the template, then prepend the CURRENT return.
    # Prepending to the mutated brief instead would stack every previous verdict
    # on top of the new one, and the worker would fix the oldest failure.
    render_brief "$unit" > /dev/null
    cat "$OUT/returns/$unit.md" "$OUT/prompts/$unit.md" > "$OUT/prompts/$unit.retry.md"
    mv "$OUT/prompts/$unit.retry.md" "$OUT/prompts/$unit.md"
    run_worker "$unit" "$OUT/prompts/$unit.md"
    attempt=$((attempt + 1))
  done
done < "$UNITS_FILE"

log "phase 4: report"
printf 'units: %s   red: %s   results: %s\n' \
  "$(grep -cve '^[[:space:]]*$' "$UNITS_FILE")" "$red" "$OUT/results/"

# The public verdict. Someone who was not in the run can check this.
[ "$red" -eq 0 ] || exit 2
