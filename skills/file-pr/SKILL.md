---
name: file-pr
description: Use when asked to "file a PR", "open a pull request", "create a PR", "PR this", "ship this branch", "raise a PR for this", or to write a pull request title and description. Covers checking whether a PR already exists, learning the repo's own title conventions, writing a problem-first description, opening ready-for-review instead of draft, model attribution, and evidence for user-visible change. For watching a PR after it is open, use babysit-pr.
---

# File a PR

## Why this is two skills

This started as one skill and split in two. The triggers are different: writing a
pull request is not the same job as watching one. You normally want one and not
the other. Once the trigger words were sharp, each fired on its own without
dragging the other in. `file-pr` writes and opens. `babysit-pr` watches and
answers.

## The problem

Agents can already open pull requests. They open the kind humans hate: a title
that names the code that got touched, a description that opens with an inventory
of changed files, no statement of what was actually wrong, and draft status, so
no review bot ever runs.

## The one rule

**Open the description with the problem, in the words the user used when they
asked. Then the solution. Never lead with an implementation inventory.**

The person reading has not seen your diff. They have seen the bug. Meet them
there.

## Titles

A title is read in a list of forty. It has one job: say what changed for a human.

| Bad | Good | The difference |
|---|---|---|
| `fix: server parse CLI version in update preflight` | `fix: version drift warning fired when versions actually matched` | Bad names the code touched. Good names the symptom a human saw. |
| `perf: negotiate per-message deflate on the websocket` | `perf: cut websocket frame size by 70 percent with compression` | Bad names the mechanism. Good names the result and its size. |
| `refactor: extract useSyncedPreference hook from six components` | `fix: settings toggles disagreed with each other across tabs` | Bad names the move. Good names why anyone would want the move. |

More pairs, across bug fix, performance, refactor, dependency bump and revert:
`references/titles-and-descriptions.md`.

## Description openings

| | Opening line |
|---|---|
| Bad | "Removed implicit workspace carryover from every new thread entry point. New threads now inherit only the project from context." |
| Good | "My new-worktree default was ignored when starting a thread on an existing worktree. Now your preference always applies." |
| Bad | "Added a debounce wrapper around the search input handler and memoised the result list." |
| Good | "Typing in search froze the list for about a second on every keystroke. It now keeps up." |

The bad ones are changelogs. The good ones are the bug the human hit.

## Procedure

### 1. Check whether a PR already exists

Filing a second pull request for the same branch is the most common wasted
action in this whole job.

```bash
gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --state all --json number,state,title,url
```

If one exists and is open, you are not filing. You are updating it, or you are in
`babysit-pr` territory. Say which.

### 2. Read the diff against the base

```bash
git fetch origin
git diff --stat origin/main...HEAD
git diff origin/main...HEAD
```

Confirm the contents match the goal that was asked for. If the diff carries work
nobody asked for, that is a finding. Report it. Do not write a description that
smooths it over.

### 3. Learn the repo's title conventions, do not impose yours

Titles usually become commit messages. The repo already has a house style.

```bash
gh pr list --state merged --limit 20 --json title
git log --oneline -20
```

Copy what you see: conventional prefixes or not, sentence case or lower, ticket
keys or none. Your preference loses to theirs.

### 4. Write the description

Short. In this order:

```markdown
<The problem, in the user's words. One or two sentences.>

<The solution. What now happens instead.>

## What to check
- <the one thing a reviewer should actually exercise>

## Out of scope
- <what this deliberately does not do>
```

The out-of-scope line stops a reviewer assuming a related bug was covered.

### 5. Open a real PR, not a draft

```bash
gh pr create --base main --title "<title>" --body-file <path>
```

**Do not pass `--draft` by default.** Draft blocks review bots and often CI, so a
draft PR looks filed and gets nothing. Draft is only for when the author says
plainly that they want no review yet. Opening drafts by default is a real and
frequent failure.

### 6. Attribution

Add one short line at the end naming the model and harness that produced the
change:

```markdown
---
Changes produced by <model> running in <harness>.
```

This is honest, and later it tells you which setup produces which quality. Some
harnesses do not expose their own model identity. Say what you actually know
(`produced by an agent running in <harness>`) rather than guessing a model name.

### 7. Evidence

Anything user-visible gets a screenshot or a short recording. A reviewer should
not have to check out the branch to see a colour change.

- Do not paste huge base64 blobs into a description. It makes the page unusable.
- If a file host or an image upload is available, upload and link.
- If none is available, say what you would have attached and where the reviewer
  can reproduce it.

## When the diff is too large to describe honestly

If you cannot write a two-sentence problem statement that covers the whole diff,
the diff is more than one change. That is a stack, not a pull request. Go to
`stacked-prs` and carve it. Filing it anyway produces a description that is true
about a third of the change and vague about the rest.

## A description is durable

It is read months later from the merge commit and from release notes. So:

- No file paths and line numbers as the main content. They go stale on the next
  refactor and then the description actively lies.
- No "see the comment above" or "as discussed". Neither survives.
- Name behaviour, not symbols. Symbols get renamed.

Paths are fine inside a "what to check" line. They must not be the description.

## Write boundary

You may: read the repo, push the branch the user is on, open the pull request.

You may not, without the human asking in that session: merge, close, force-push,
change the base branch of an existing PR, or open a PR from a branch the user did
not ask you to ship.

## After it is open

If the user also wants it watched to green, `babysit-pr` takes over from here.

## Files

- `references/titles-and-descriptions.md` - a longer bank of bad/good pairs by
  category, and the pre-filing checklist
