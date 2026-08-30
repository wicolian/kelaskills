# Triaging automated review comments

An automated reviewer is a fast reader with no memory of your repo and no way to
run the code. It is genuinely useful and it is wrong often enough that acting on
its output unverified is how a small pull request becomes a big one.

This file is how to sort what it says.

## The one procedure

For every finding, in this order:

1. **Open the file and read the lines.** Not the snippet in the comment. The real
   file at the current head.
2. **Try to reproduce the claim in the source.** Trace the call. Find the caller.
   Check whether the guard the bot missed is three lines up.
3. **Decide: real, false positive, or real but out of scope.**
4. **Fix, or reply with the reason and resolve.** Never leave it unanswered.

A finding you cannot reproduce in the source is a false positive. Say that
plainly. Do not add a defensive check "just in case" to make a thread go away:
that is how dead code accumulates, and it is a change nobody asked for.

## Almost always real

Verify these anyway, but expect them to hold up.

| Finding | Why it holds up |
|---|---|
| A leaked secret, key or token in the diff | Pattern matching is exactly what this class of tool is good at |
| An `await` missing on a promise-returning call | Purely syntactic, no context needed |
| A resource opened and not closed on the error path | Local, visible in one function |
| An off-by-one in a slice or a loop bound | Local and checkable |
| A `.env`, a lockfile, a build artefact or a large binary committed by accident | File-level fact |
| An unhandled rejection or a swallowed exception | Visible in the diff itself |
| A SQL string built by concatenating a request value | Local pattern, and expensive when wrong |
| A hardcoded URL, port or path that should be config | Visible, and cheap to fix |
| A test that asserts nothing | Structural |

Fix these inside the pull request. They are in your diff and they are your job.

## Almost always safe to dismiss, with a reason

| Finding | The reason to give |
|---|---|
| "Consider extracting this into a service layer" | Architectural preference, out of scope for this change |
| "This function is doing too much" on code you did not write | Pre-existing, not touched by this PR |
| "Add tests for this module" beyond what you changed | Tests added for the changed behaviour, the rest is a separate PR |
| "Add JSDoc to every exported symbol" | Repo does not require it, no linter enforces it |
| A naming preference the repo does not enforce | Matches the surrounding file's convention |
| "Consider using X instead of Y" where both work | Y is what this codebase already uses |
| A performance suggestion on a path that runs once at startup | Not a hot path, no measurement supports the change |
| A null check on a value the type system already narrows | The type guarantees it, adding the check is dead code |
| "This could throw" on a call inside an existing try block | Already handled by the enclosing handler |
| Advice about a framework or a version this repo does not use | Wrong stack, the bot guessed |

Every one of these needs a written reply. The reason is the deliverable, not the
dismissal.

## The ambiguous middle

These need real thought and cannot be resolved by a rule.

- **A real bug in a file you touched, but not on a line you changed.** Default:
  decline politely and offer a follow-up. Exception: it is severe, it is one
  line, and it is obviously related to the change. Then fix it and say in the
  description that you did.
- **A missing edge case in new code.** If the case can actually occur, it is real
  and it is yours. If it cannot occur given the callers, say which callers and
  why.
- **A security finding you cannot reproduce.** Do not silently dismiss security.
  If you cannot confirm or refute it, escalate to the human with what you checked.
- **Two bots that disagree.** Read the source and decide. Say which one you
  followed and why. Do not try to satisfy both.
- **A bot that repeats a finding you already declined.** Link your earlier reply.
  Do not re-argue it.

## Reply templates

Keep them short. A long reply reads as defensive.

**Fixing it**

```
<model or harness> responding on behalf of <user>.

Good catch, fixed in <sha>.
```

**False positive**

```
<model or harness> responding on behalf of <user>.

Checked the source: <what you actually found, one sentence>. The condition here
cannot occur because <reason>. Not changing this.
```

**Real but out of scope**

```
<model or harness> responding on behalf of <user>.

Correct, but pre-existing and not touched by this PR. Keeping the diff to the
original goal. Worth a follow-up.
```

**Cannot resolve, escalating**

```
<model or harness> responding on behalf of <user>.

Cannot confirm or rule this out from the source. Flagging for <user> rather than
guessing.
```

Then resolve the thread. An answered but unresolved thread still shows as
outstanding, and the next reviewer counts it against you.

## Closing a thread cleanly

A thread is closed cleanly when all three are true:

1. There is a reply that states what you did or why you did nothing.
2. The reply carries the agent attribution line.
3. The thread is marked resolved.

Resolving without replying is the failure that reads worst to a human. It looks
like you made the comment disappear.

## What never justifies a change

- The bot sounded confident.
- The count of open comments looked bad.
- It was quicker to comply than to explain.
- Another pull request in this repo did it that way once.

Each of these produces a diff that no human asked for, in a pull request that
already had a goal.
