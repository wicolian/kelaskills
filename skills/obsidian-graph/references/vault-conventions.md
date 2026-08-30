# Vault conventions

The taxonomy, the layout, the tag scheme, and how to put all three into a vault
that already has opinions.

Read this when you are setting the lens up in a vault for the first time, or when
a note does not obviously fit one of the three types.

## Three types, and why there are only three

| `type` | The claim it makes | Example |
|---|---|---|
| `cause` | X produced Y, observed, not inferred | "Two agents writing the same lockfile lose the first agent's dependency; the second write wins." |
| `decision` | We chose X over Y, for this reason | "Retries are capped rather than queued, because the upstream bans on failure count, not on rate." |
| `constraint` | This must hold, or something breaks | "The bundler needs the fetch global, so the Node floor is 20." |

Everything else people want to write is one of these in disguise, or it is a log
entry.

- "How the auth module works" is a restatement of code. The code is the record.
- "What I did tonight" is the git log.
- "Ideas for later" is a task, and it belongs wherever tasks live.
- "This API is slow" is an observation. It becomes a `cause` when you know why,
  and a `constraint` when you know what it forces.

If a fact resists all three types, that is the filter working. Do not add a
fourth type to make it fit.

### Confidence, honestly

| Level | Means |
|---|---|
| `high` | Observed directly this run. A test went green, a log line was read, a value was measured. |
| `medium` | Derived from strong evidence but not directly observed, or observed once, a while ago. |
| `low` | Inferred. Written down because the reasoning is useful, and flagged so nobody builds on it. |

A vault full of `high` is a vault where confidence means nothing. If a run
produces three notes and all three are `high`, check that all three were actually
observed.

## Folder layout

One folder. Not a tree.

```
<vault>/
  Agent/
    Learned/
      queue-worker-retry-cap-is-3.md
      queue-worker-retry-cap-is-3-2.md      <- supersedes the above
      parallel-agents-clobber-the-lockfile.md
      node-floor-is-20-for-the-fetch-global.md
```

Configured as `VAULT_DIR` plus `VAULT_SUBFOLDER` (default `Agent/Learned`).

Why flat:

- Folders are a second, competing classification system. `type` and `tags`
  already classify. A folder tree adds a third and they will disagree.
- Edges do the organising. A subject with five notes is a cluster in the graph
  view without anyone filing anything.
- A flat folder is one `rg` away from any question. A tree is a traversal.

Split into a second folder only when one folder passes a few hundred notes, and
split by **project**, never by subject. Subjects overlap; projects do not.

## File names are slugs, and slugs are the addressing scheme

`kebab-case-of-the-title.md`. No date prefix, no numeric prefix, no spaces.

This matters more than it looks, because the slug **is** the edge target.
`supersedes: ["[[queue-worker-retry-cap-is-3]]"]` resolves by note name, not by
path, which is what lets a degraded-mode folder be moved into a real vault later
with every edge intact.

Rules:

- **No date in the filename.** The date is in frontmatter. A dated filename makes
  the same fact written twice look like two facts, which defeats the
  refuse-to-clobber check that keeps the vault clean.
- **A revision gets a numeric suffix**: `-2`, `-3`. The suffix is a chain
  position, not a version number to reason about. Read the `supersedes` edges.
- **The title is a claim, not a topic.** "queue worker retry cap is 5" beats
  "queue worker retries". A file list of claims is readable. A file list of topics
  makes you open every one.
- Keep it under about 60 characters. The bundled script truncates there.

## Tag scheme

Hierarchical, so an existing vault's tag pane gets one new top-level entry
instead of thirty.

| Tag | On | Purpose |
|---|---|---|
| `#agent/learned` | every note this lens writes, no exceptions | The handle. Select, review, or delete everything an agent ever wrote, in one query. |
| `#type/constraint`, `#type/decision`, `#type/cause` | every note | Mirrors the `type` field so the tag pane is usable without queries. |
| `#domain/<area>` | optional, one per note | The subject area: `#domain/queue`, `#domain/build`, `#domain/auth`. Reuse the vault's existing area words. |

Three rules:

1. **Never invent a top-level tag.** `#agent/...`, `#type/...`, `#domain/...` and
   nothing else. A vault's tag namespace belongs to its owner.
2. **One domain tag maximum.** A note that needs three domain tags is three notes,
   or it is too vague to be a fact.
3. **Do not adopt the vault's status tags.** If the vault uses `#status/done` for
   its own workflow, leave it alone. This lens tracks state in the `status`
   frontmatter field, which cannot collide with a human's kanban.

## Landing this in a vault that already has conventions

Two shapes turn up constantly. Neither of them should be reshaped.

### The entity graph

Notes are things: organisations, people, meetings, recurring series, all
cross-linked. Frontmatter already carries `type`, `status` and `tags`.
Hierarchical tags like `#status/done` are in use. Wikilinks are everywhere.
Dataview inline fields (`key:: value`) are usually **not** in use.

How to fit in:

- The vault already has `type` and `status`. **Use the same keys**, add your
  values to their vocabulary rather than inventing `note_type` and `note_status`.
  Check what values already exist first: `rg -I -N '^type:' <vault> | sort -u`.
- Link **out** to the vault's entity notes with `references`, when a learned fact
  genuinely relates to one. Never create an entity note yourself. Entity notes are
  the human's, and an agent-created near-duplicate of one is the fastest way to
  get the whole experiment deleted.
- If an entity note does not exist, do not stub it. A wikilink to a note that does
  not exist yet is a broken link in that vault's own hygiene checks.

### The numbered docs vault

Ordered folders (`01-overview`, `02-architecture`), prose-heavy, often with an
entrypoint note that tells an agent where to start.

How to fit in:

- **Do not number your folder.** Numbering claims a position in a sequence a human
  designed. `Agent/Learned` sits outside the sequence, which is exactly right for
  something appended by a machine.
- Add one line to the entrypoint note pointing at the folder, and only if the
  human asks for it. That is an edit to a human's file, so it is a request, not a
  write.
- The prose style of that vault is for humans reading top to bottom. Learned
  notes are for lookup. Do not stretch a one-fact note into an essay to match the
  house voice.

### The generic checklist

Before the first write into any vault:

- [ ] `VAULT_DIR` and `VAULT_SUBFOLDER` are set, and the subfolder is one the
      human agreed to.
- [ ] `rg -I -N '^type:' "$VAULT_DIR" | sort -u` and the `tags:` equivalent, so you
      are reusing the vault's vocabulary instead of forking it.
- [ ] Dataview: assume it is absent. Frontmatter fields only.
- [ ] Is a folder-level sync running (iCloud, Dropbox, a sync plugin)? If yes and
      the app is closed, write one note, not fifty. Conflict copies from a bulk
      write are tedious to clean up by hand.
- [ ] If the vault is a git repo, `.obsidian/plugins/*/data.json` is ignored
      before anything else happens. It holds a plaintext bearer token and a port.
- [ ] `.obsidian/workspace.json` is never touched. It is UI state.

## The review loop

The vault gets worse over time unless somebody looks at it. This is the cheapest
version that works:

```bash
# every learned note, newest first, so a human can skim a month in a minute
rg -l --glob '*.md' '^tags: \[agent/learned' "$VAULT_DIR/$VAULT_SUBFOLDER" \
  | xargs ls -t

# low-confidence notes nobody upgraded or superseded: the rot
rg -l --glob '*.md' '^confidence: low$' "$VAULT_DIR/$VAULT_SUBFOLDER"
```

A `low` note that is six months old and was never superseded and never upgraded
was never worth writing. That is the signal to tighten the filter, not to write a
cleanup script.
