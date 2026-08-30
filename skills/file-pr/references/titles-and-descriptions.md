# Titles and descriptions: a bank of pairs

Every pair below is the same change described twice. The bad one is what an agent
writes by default: accurate, and useless to the person reading the list.

The test for a title: **would the person who reported the problem recognise it?**

The test for a description opening: **does the first sentence say what was wrong,
in their words?**

---

## Bug fix

| | |
|---|---|
| Bad | `fix: server parse CLI version in update preflight` |
| Good | `fix: version drift warning fired when versions actually matched` |
| Bad | `fix: guard null in session hydrate` |
| Good | `fix: refreshing the page while signed in logged you out` |
| Bad | `fix: correct timezone offset in report aggregation` |
| Good | `fix: daily totals were a day behind for anyone outside UTC` |
| Bad | `fix: add missing await in upload handler` |
| Good | `fix: uploads reported success before the file finished` |

Bug titles have a symptom available for free. Use it. The stack trace is not the
symptom. The thing the user saw is.

**Description opening, bad**

> Removed implicit workspace carryover from every new thread entry point. New
> threads now inherit only the project from context.

**Description opening, good**

> My new-worktree default was ignored when starting a thread on an existing
> worktree. Now your preference always applies.

---

## Performance

| | |
|---|---|
| Bad | `perf: negotiate per-message deflate on the websocket` |
| Good | `perf: cut websocket frame size by 70 percent with compression` |
| Bad | `perf: add composite index on events(org_id, created_at)` |
| Good | `perf: dashboard load went from 8s to under 1s` |
| Bad | `perf: memoise the row renderer` |
| Good | `perf: scrolling a large table no longer drops frames` |

Performance titles need a number. A performance PR with no number in the title or
the first line of the description has not been measured, and a reviewer is right
to assume so.

**Description opening, bad**

> Added a debounce wrapper around the search input handler and memoised the
> result list.

**Description opening, good**

> Typing in search froze the list for about a second on every keystroke. It now
> keeps up.

---

## Refactor

A refactor has no user-visible symptom, so the title has to carry the reason.

| | |
|---|---|
| Bad | `refactor: extract useSyncedPreference hook from six components` |
| Good | `fix: settings toggles disagreed with each other across tabs` |
| Bad | `refactor: move auth helpers into shared package` |
| Good | `refactor: one copy of the auth check instead of four that had drifted` |
| Bad | `refactor: split UserService` |
| Good | `refactor: split UserService so billing stops importing session code` |

If you cannot name the reason, the refactor may not be worth reviewing. That is
useful to find out before you file.

**Description opening, good**

> Four files each had their own copy of the permission check and two of them were
> already out of date. This leaves one.

---

## Dependency bump

| | |
|---|---|
| Bad | `chore: bump acme-parser from 4.1.2 to 5.0.0` |
| Good | `chore: acme-parser 5 to pick up the CVE fix, with the two breaking calls updated` |
| Bad | `chore: update lockfile` |
| Good | `chore: refresh lockfile after the transitive resolution drifted on CI` |

A bump description must answer three things a reviewer will ask anyway:

1. Why now. A security advisory, a bug you hit, or routine hygiene.
2. What broke. Name the breaking changes you had to handle, or say "none".
3. How you know. The command you ran and what passed.

---

## Revert

| | |
|---|---|
| Bad | `Revert "feat: new onboarding flow"` |
| Good | `revert: new onboarding flow, it broke signup on Safari` |
| Bad | `Revert "perf: cache the org lookup"` |
| Good | `revert: org lookup cache, it served stale permissions after a role change` |

A revert always states the reason in the title. The bare auto-generated revert
title tells the next person nothing, and they will find it in six months while
wondering whether it is safe to try again.

The description must also say whether a retry is planned, and what would have to
be true for it to land.

---

## Before you file: the checklist

1. `gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --state all` returns
   nothing open. If it does, you are updating, not filing.
2. You have read the whole diff against the base, not just your own commits.
3. The diff contains nothing nobody asked for. If it does, that is reported, not
   smoothed over.
4. The title matches the repo's convention, learned from
   `gh pr list --state merged --limit 20 --json title` and `git log --oneline -20`.
5. The title names a symptom or a result, not the code you touched.
6. The first sentence of the description is the problem, in the user's words.
7. Performance claims carry a number you actually measured.
8. There is an out-of-scope line.
9. No file path or line number is doing load-bearing work in the description.
10. Anything user-visible has a screenshot or a recording attached, or an honest
    statement of what you would have attached.
11. There is an attribution line naming the model and the harness, or naming only
    what you actually know.
12. You are not passing `--draft` unless the author asked for no review yet.
