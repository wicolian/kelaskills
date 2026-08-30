# What a lens needs, and how to offer to wire it

A lens fails in a specific and unhelpful way when its source is not configured:
it looks like the evidence does not exist, rather than like the tool is missing.
So check first, say which sources are live, and offer to wire the rest.

**Never install or reconfigure anything without being asked.** Report what is
missing, name the one command, and let the human run it.

## Check before you dig

Run this at the start of any run carrying `-why` or `-obsidian`. It is cheap and
it stops the worst failure in the system, which is reporting "no evidence" from a
source that was never connected.

```bash
# git and GitHub, the only source that is usually already there
git rev-parse --git-dir >/dev/null 2>&1 && echo "git: yes" || echo "git: NO"
command -v gh >/dev/null && gh auth status >/dev/null 2>&1 \
  && echo "gh: authed as $(gh api user --jq .login)" || echo "gh: NO"

# a vault for the learning edge
[ -n "${VAULT_DIR:-}" ] && [ -d "$VAULT_DIR" ] \
  && echo "vault: $VAULT_DIR" || echo "vault: NO, degraded mode writes ./.agent-notes"
```

For MCP-backed sources there is no shell probe worth trusting. Read the tool list
you were given. If a server's tools are absent, it is not configured. If they are
present but every call errors, it is configured and down, which is a different
problem with a different fix.

## The coverage table

State this once, plainly, before the dig. It is the difference between a real
negative and a blind spot.

| Source | Needed for | Missing means |
|---|---|---|
| local `git` | every dig, wave 1 | the lens cannot run at all |
| `gh`, authenticated | pull requests, reviews, issues | you get commits but never the argument |
| Chat search | wave 4, where decisions get argued | the most common home of a "why" is dark |
| Error tracking | defensive code, retries, odd guards | you cannot tell a scar from a mistake |
| Product analytics | flag and experiment branches | a dead branch looks like live code |
| Meeting transcripts | last resort | a decision made in a call is unrecoverable |
| Session recordings | UI oddities | you lose the reproduction |
| A vault | `-obsidian` | the run cannot get smarter, only correct |

Say it like this, once:

> `-why` is running with git and GitHub only. Chat, error tracking and analytics
> are not wired here, so a "no recorded reason" from me means "not in the repo or
> the pull requests", not "nowhere".

## Offering to wire one

Only after the run, and only if the missing source would actually have helped.
One line, the exact command, no pitch.

```
The reason was not in the commit or the PR. This is the shape of thing that
usually lives in a chat thread, and chat search is not wired here.

  claude mcp add --transport http <name> <url>

Want me to add it, or would you rather do it yourself?
```

Two rules. Do not offer a source you did not need on this run. Do not offer the
same one twice in a session.

## Other agent runtimes

The lens contract is plain markdown and a phase order, so it carries to any
runtime that can read a skill folder. What does not carry is the tooling.

- **Claude Code**: MCP servers via `claude mcp add`, skills in `~/.claude/skills/`.
- **Codex, Cursor, Pi, Hermes**: skills install to their own directories; see the
  install table in the repository README. MCP support varies by runtime and by
  version, so check rather than assume.
- **Anything else**: the shell parts of `-why` (git, `gh`) work everywhere. The
  MCP parts do not. Say which half you have.

`graph-engineering` carries the fuller cross-runtime picture in
[its other-runtimes reference](../../graph-engineering/references/other-runtimes.md),
including the setup interview to run before wiring an orchestration layer. Read
that before offering to set up a runtime, rather than improvising one here.

## The failure this prevents

An agent runs `-why`, finds nothing, and writes "no recorded reason for this
code". A human reads that as "we checked everywhere". In fact three of the five
places a reason lives were never reachable.

A negative finding is only worth as much as the coverage behind it. State the
coverage, every time.
