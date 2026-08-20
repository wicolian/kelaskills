# Telling a quota wall from a real failure

The watchdog has to answer one question correctly: *should I wait, or should I
stop?* Get it wrong in one direction and it sits idle through a healthy night.
Wrong in the other and it burns the rest of your budget respawning a broken run.

## Three outcomes, three responses

| Outcome | Response | Why |
|---|---|---|
| **Quota wall** - spend cap, usage limit, rate limit | **wait and retry, forever** | The wall goes away on its own. Nothing else to do. |
| **Auth failure** - expired token, logged out | **stop and log loudly** | Retrying cannot fix it, and each retry looks like a wall. |
| **Crash** - the orchestrator started and died | **restart, but count it** | Might be transient. Might be a loop. The counter decides. |

The dangerous confusion is auth-vs-quota: an expired credential fails on every
retry, so a naive watchdog treats it as a very long blackout and waits until
morning doing nothing. Match on the message, not just the exit code.

## Matching

Quota, treat as a wall:

```
spend limit      usage limit      rate limit       quota
too many requests                 429              resets at
```

Auth, treat as fatal:

```
unauthorized     invalid api key  authentication   401     please log in
```

Anything else with a non-zero exit is a crash.

```bash
classify() {
  local out; out="$(scripts/probe-agent.sh "${AGENT_RUNTIME:-codex}" 2>&1)"; local rc=$?
  if   printf '%s' "$out" | grep -qiE 'spend limit|usage limit|rate limit|quota|too many requests|429|resets at'; then echo wall
  elif printf '%s' "$out" | grep -qiE 'unauthorized|invalid api key|authentication|401|please log in|not logged in'; then echo auth
  elif [ $rc -ne 0 ]; then echo crash
  else echo ok; fi
}
```

**Keep the probe as cheap as possible.** It runs on a loop for hours. Smallest
model, shortest prompt, and remember that during a blackout the call fails
before it costs anything.

## Which wall, and when it lifts

Do not schedule around a reset you have not checked.

| Limit | Resets | Watchdog behaviour that is correct |
|---|---|---|
| Per-minute rate limit | seconds | short backoff, recovers on its own |
| Session / rolling window | a few hours | backoff to the cap, recovers overnight |
| Weekly cap | a fixed day | backoff forever; it will not lift tonight |
| **Monthly spend cap** | the billing date | backoff forever; **it will not lift tonight** |

Exponential backoff with a cap handles all four without knowing which one it is,
which is exactly why it beats a scheduled wake-up. The wake-up has to guess.

But **you** should still know which one you are near, because for the bottom two
rows the honest answer is "the night is over, go to bed" rather than "the guard
has it". Write it in `LIMITS.md` before you go dark:

```markdown
# Limits, checked 2026-08-19 01:40
- Session window:  ~90% used, resets ~03:00. This is the one tonight.
- Weekly:          40% used, resets Monday.
- Monthly spend:   62% used, resets the 1st.
Verdict: the 03:00 reset is real. Backoff will get through it.
```

## Backoff shape

Double it, cap it, and never reset the cap on a failure:

```
60s -> 120 -> 240 -> 480 -> 960 -> 1800 (cap) -> 1800 -> ...
```

Reaching the cap in about half an hour and then polling every 30 minutes is the
right shape for a multi-hour wall. It is roughly 20 probes across a whole night -
negligible - and it recovers within 30 minutes of the wall lifting.

**Reset the backoff only on success**, never on a loop iteration. A backoff that
resets because the fleet happened to look alive for one tick will hammer the API
the moment the fleet empties again.

## The failure this prevents

An in-session scheduler set for 03:07 assumes two things: that the session is
alive at 03:07, and that the wall is gone by then. A quota blackout breaks the
first, and a monthly cap breaks the second.

A shell loop with backoff assumes neither. That is the whole argument.
