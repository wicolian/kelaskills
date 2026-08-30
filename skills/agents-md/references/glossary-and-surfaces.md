# The two sections worth the most

The glossary and the surface checklist. Both are usually missing. Both pay back
within a week.

---

# Part 1: the glossary

## What it is for

Not comprehension. A model reading your code will work out what a `Booking` is
without help.

The glossary exists so the agent **hands your words back to you**. When it says
"added the cancel path to the invitee view" instead of "updated the
notification-related component for the second user type", you can read the report
at a glance and catch a wrong assumption in it. A report in your vocabulary is
auditable. A report in the model's vocabulary is a translation exercise you do at
the end of every task.

Second effect, smaller but real: a defined word is a word the agent will not
invent a synonym for. Three names for one concept in a codebase starts with three
names for it in prose.

## How to pick the words

Do not start from the type definitions. Start from the places where humans talk:

| Source | What to take from it |
|---|---|
| The last 50 issue and pull-request titles | Nouns that appear more than twice |
| Support or feedback threads | The words users use, which are often not yours |
| Your own agent transcripts | Every word you had to correct the agent on |
| The onboarding explanation you give new people | The five things you always explain first |
| Names that disagree across the codebase | Each disagreement is one glossary entry |

Ten to twenty entries. Past thirty you are writing a data dictionary, and nobody
reads those, including the agent, because it is now cheaper to read the code.

## How to write an entry

**Say what a thing is, not what it does.**

| Weak | Strong |
|---|---|
| **slot** - handles availability logic | **slot** - one bookable span of time on a host's calendar. |
| **workspace** - the top-level container class | **workspace** - one team's isolated data. Nothing crosses a workspace boundary. |
| **digest** - sends a summary email | **digest** - one batched notification covering a period. Not "summary" or "roll-up". |

One or two sentences. Where the concept has a boundary worth stating, state the
boundary, because the boundary is what stops a wrong change.

**Be opinionated and list the rejected synonyms.** This is the half that changes
behaviour:

```markdown
- **invitee** - the person a booking is made for. Not "guest", "attendee",
  "participant" or "the other user".
```

Without the rejected list, the agent picks a different one every session and your
reports stop being greppable.

## The pronouns, first

In a file written by maintainers, for an agent, about a product, three referents
collide on nearly every line. "The user should not be able to do that" is
ambiguous between the product's user and the person prompting.

```markdown
- **you** - the agent reading this file.
- **we**, **us** - the maintainers of this repository.
- **the user** - the person the product serves. Never the person prompting you.
- **the operator** - the person prompting you right now.
- **the team** - [everyone with write access / the named group].
```

Cheap to write. It removes a whole class of misread instruction.

## When a term means two things

Common and worth handling explicitly, because the agent will silently pick one
meaning and be wrong half the time.

Three moves, in order of preference:

**1. Rename one of them.** Best outcome, highest cost. If `account` means both a
billing entity and a login identity, one of them becomes `subscription` or
`identity` in the code, and the glossary records the rename so the agent updates
old call sites as it meets them.

**2. Qualify both, and ban the bare word.** Cheap and effective:

```markdown
- **billing account** - the entity a subscription is attached to.
- **login account** - one set of sign-in credentials.
- The bare word "account" is ambiguous here. Always qualify it.
```

**3. Define the default and name the exception.** Use only when one meaning
genuinely dominates:

```markdown
- **calendar** - a host's own availability. In the `sync/` package only, it means
  a connected external provider calendar.
```

Never leave two live meanings undocumented and hope. That is the case where the
agent's confident wrong guess costs you the most.

## Keeping it current

Three triggers, all cheap:

- **You corrected the agent's word.** Add the entry, with the wrong word in the
  rejected list. This is the highest-signal trigger and it is free: the correction
  already happened.
- **A rename landed.** Update the entry in the same pull request. A glossary
  that lags the code is worse than none, because it is now confidently wrong.
- **A concept died.** Delete the entry. Dead words in a glossary invite an agent
  to resurrect the concept.

Do not schedule a quarterly glossary review. It will not happen. Attach the
maintenance to events that already occur.

## Worked example, in an invented domain

A team scheduling tool. Nothing real, and the shape is what matters.

```markdown
## Words we use

- **you** - the agent reading this file.
- **we**, **us** - the maintainers of this repository.
- **the user** - a host or an invitee. Not the person prompting you.
- **the operator** - the person prompting you right now.

- **workspace** - one team's isolated data. Nothing crosses a workspace boundary,
  ever. Not "org", "tenant" or "account".
- **host** - the person whose availability is being booked. Not "owner",
  "organiser" or "provider".
- **invitee** - the person a booking is made for. Not "guest", "attendee" or
  "participant".
- **slot** - one bookable span of time on a host's calendar. A slot exists
  whether or not anything is booked in it.
- **booking** - one confirmed claim on a slot. Not "event", "meeting" or
  "appointment".
- **hold** - a slot reserved but not confirmed. Expires. A hold is not a booking
  and must never be counted as one.
- **connected calendar** - an external calendar we read availability from. Read
  only. We never write to it.
- **digest** - one batched notification covering a period. Not "summary".
```

Notice what the entries carry beyond naming. "Nothing crosses a workspace
boundary, ever" is a constraint. "A hold is not a booking" prevents a category of
counting bug. "Read only, we never write to it" is a refusal the agent can act
on. **The glossary is where a surprising number of your invariants naturally
live**, because an invariant is usually a fact about what a thing *is*.

## Glossary anti-patterns

| Anti-pattern | Why it fails |
|---|---|
| Sixty entries | Nobody reads it. Reading the code is now cheaper. |
| Defining what a thing does | Behaviour changes. Identity does not. |
| Restating a type definition | The type is already right and never drifts. |
| No rejected synonyms | The agent rotates through them anyway. |
| Terms only maintainers use, with no user-facing word | The agent writes internal words into user-facing copy. |

---

# Part 2: surfaces

## The defect this stops

A feature is added. It works on the path that was tested. It is absent from the
command palette, missing on one platform, unimplemented in two of five providers,
and has no un-do. Every test passes. The pull request looks complete.

This is the single most common multi-surface defect, and it is a **listing**
problem, not a skill problem. The agent did not know the other places existed.

## Deriving the checklist for a codebase you did not write

Five sweeps. Run them, read the output, and write down what is real. The output
is a candidate list, not the answer.

### 1. Entry points

Every way a person can start the feature. Look for registries, because entry
points are almost always registered somewhere central.

```bash
grep -ril --include='*.*' \
  -e 'command_palette' -e 'commandPalette' -e 'registerCommand' \
  -e 'keybinding' -e 'shortcut' -e 'contextMenu' -e 'menuItem' \
  -e 'deepLink' -e 'urlScheme' -e 'quickAction' .
```

Then look for a settings screen, a search or launcher, a notification action, a
public API route, and a command-line surface. Each is an entry point that
routinely gets missed.

### 2. Platforms and clients

Directories are the strongest signal here.

```bash
ls -d */ apps/*/ packages/*/ clients/*/ 2>/dev/null
```

Look for names like `web`, `desktop`, `mobile`, `ios`, `android`, `cli`,
`extension`, `server`. Also check the manifest or workspace file, since a
monorepo lists its members in one place.

### 3. Adapters and providers

The highest-yield sweep, because these are the places where "it works" is true
for one implementation and false for four.

```bash
find . -type d \( -name 'adapters' -o -name 'providers' -o -name 'drivers' \
  -o -name 'integrations' -o -name 'backends' -o -name 'plugins' \
  -o -name 'connectors' \) -not -path '*/node_modules/*'
```

Also find them from the interface side: any type or abstract class with three or
more implementations is an adapter set, whatever the folder is called.

**Every adapter needs an explicit decision, even when the decision is "not
supported here".** An unstated gap looks identical to an oversight six months
later.

### 4. Shared contracts

Anything that crosses a boundary and therefore has to change on both sides at
once.

```bash
find . -type d \( -name 'shared' -o -name 'common' -o -name 'contracts' \
  -o -name 'types' -o -name 'schema' -o -name 'proto' -o -name 'api' \) \
  -not -path '*/node_modules/*'
```

Look also for a code-generation step. Generated clients mean a contract change
has a build step attached, and forgetting it produces a mismatch that only shows
at runtime.

### 5. Docs roots

```bash
find . -maxdepth 3 -type d \( -name 'docs' -o -name 'doc' -o -name 'website' \
  -o -name 'documentation' \) -not -path '*/node_modules/*'
```

If there is exactly one, that is the finding: the user and maintainer split does
not exist yet, and internal detail is leaking into user-facing pages.

`../scripts/propose-surfaces.sh` runs these sweeps for you and prints a draft
checklist. Treat it as a starting list to prune, not an answer.

---

## The reverse-state audit

The most commonly missed surface, and the easiest to check for mechanically.

**The rule: every state you can enter, you must be able to leave, from the same
places you entered it, with the same care.**

Adding a state is satisfying and gets designed. Removing it is plumbing and gets
skipped. So the mute has no un-mute in the list view, the archive has no restore,
the snooze cannot be cancelled early, and the invite cannot be revoked.

### The procedure

Run this on any change that adds a state. It takes about ten minutes.

**Step 1. Name the state.** One noun and its two values. `muted` / `not muted`.
If you cannot name it, there is no new state and you can stop.

**Step 2. List the ways in.** Every entry point from sweep 1 that can set it.

**Step 3. For each way in, find the matching way out.** Same surface, same number
of clicks or keystrokes, discoverable by someone who did not set it. A reverse
that only exists in a settings page three levels down does not count as reachable
from a list row.

**Step 4. Check the four states that are always forgotten:**

| Question | The bug when the answer is missing |
|---|---|
| Does it expire on its own, and can someone see when? | A permanent state the user believed was temporary. |
| Can it be undone by someone other than the person who set it? | A team blocked by one person's absence. |
| What happens if the underlying object is deleted while the state is set? | An orphan row and a filter that never matches. |
| Is the state visible at all when it is on? | A silent state. The worst kind, because nobody knows to reverse it. |

**Step 5. Check bulk.** If a user can set the state on 200 items one at a time,
they need a way to clear it that is not 200 more actions.

**Step 6. Check the storage.** A reverse that flips a flag but leaves the row,
the scheduled job, the cache entry or the queued notification behind is not a
reverse. Grep for everything the forward path wrote.

### Reverse pairs worth checking by name

| Forward | Reverse that usually does not exist |
|---|---|
| mute, silence | un-mute, and a way to see what is muted |
| snooze, defer | wake now, and cancel the snooze |
| archive, hide | restore, and a view that lists archived items |
| invite, share | revoke, and a list of who currently has access |
| pin, favourite | unpin, and a limit on how many can be pinned |
| enable a feature flag | disable it, and what happens to data created while it was on |
| connect an integration | disconnect, and what happens to synced data |
| subscribe, follow | unsubscribe, from the notification itself |
| import | delete what was imported, as one action |
| start a long job | cancel it, and clean up partial work |

### Write the finding down

When the audit finds a missing reverse, that is a line for the project file's
surface checklist, not just a bug to fix. The next feature will have the same
gap. A found failure that does not become a permanent constraint is a failure you
will meet again.
