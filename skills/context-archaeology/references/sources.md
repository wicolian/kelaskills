# Sources

Six places a reason hides, with the exact calls, the exact parameter names, and
the ways each one lies to you. Everything here was verified with read-only calls.

Every call on this page is read only. None of these sources is ever written to,
commented on, resolved, updated or sent from this lens.

Placeholders throughout: `<owner>/<repo>`, `<org>`, `<project>`, `<CHANNEL_ID>`,
`<PROJECT-123>`, `<flag-key>`.

---

## 1. Git and the code host

**Use `gh` plus local `git`.** Not a graphical git integration, for three measured
reasons: its blame takes a directory and a file with no line range, so it returns
the whole file (a 100-line README cost about 2500 tokens); its graph call takes a
directory with no limit and no ref, which makes it a way to open a UI rather than
a data tool; and its pull-request detail call returned `author: {}`, empty.

**Keep exactly two of its tools, and use `gh` for everything else.**

| Keep | Because |
|---|---|
| `pull_request_get_comments` | It splits inline `prComments` from `reviewComments`, and the inline ones carry `inReplyToId`, so you can rebuild the reply chain. `gh` gives you the comments but not the thread shape. |
| `issues_get_detail` | The only way to reach a tracker that is not the code host: Jira, Linear, GitLab, Azure. `gh` cannot see any of them. |

One quirk to know about `issues_get_detail`: given a pull request number it returns
the pull request, because the code host shares one number space between issues and
pull requests.

### The chain, about 1.6 seconds wall clock for the core three

```bash
SHA=$(git blame -L 28,28 --porcelain -w -M -C path/to/file.ts | head -1 | cut -d' ' -f1)
git show -s --format=%B "$SHA"
PR=$(gh api "repos/<owner>/<repo>/commits/$SHA/pulls" --jq '.[0].number')
gh pr view "$PR" --repo <owner>/<repo> --json title,url,body,closingIssuesReferences
gh api "repos/<owner>/<repo>/pulls/$PR/comments" --jq '.[] | "\(.user.login) @\(.path):\(.line): \(.body)"'
gh api "repos/<owner>/<repo>/pulls/$PR/reviews"  --jq '.[] | {user:.user.login,state:.state,body:.body}'
```

`scripts/why-line.sh <file> <line>` runs all of it and degrades honestly.

### Also verified useful

| Call | Answers |
|---|---|
| `git log -S 'the exact string' --oneline -- path` | Which commit introduced this literal (the pickaxe) |
| `git log -L 28,28:path --oneline` | The whole evolution of one line |
| `git tag --contains "$SHA"` | Which release shipped it |
| `gh api -X GET search/issues -f q="repo:<owner>/<repo> path/to/file.ts"` | Who else argued about this file |

### Blame hygiene

- Always pass `-w -M -C`: ignore whitespace, follow moves, follow copies. Without
  them you blame a reformat.
- Check the repo root for `.git-blame-ignore-revs`. If it exists, blame with
  `--ignore-revs-file .git-blame-ignore-revs` or you will land on a bulk-format
  commit.
- Blame landing on a squash or a merge commit is fine. `commits/$SHA/pulls` still
  resolves it. Verified.

### The load-bearing finding

**`closingIssuesReferences` lies by omission.** On a traced pull request it
returned `[]` and the timeline had zero cross-referenced events, while the real
reason sat in the body as prose linking a prior pull request. Always grep:

```bash
gh pr view "$PR" --repo <owner>/<repo> --json body --jq '.body' \
  | grep -oE '(#[0-9]+|https://github\.com/[^ )]+/(issues|pull)/[0-9]+)' | sort -u
```

### Failure modes

| Signal | What it means | Do |
|---|---|---|
| `commits/$SHA/pulls` returns `[]` | **A real answer.** Pushed straight to trunk with no pull request. | Stop looking for one |
| HTTP 422 `No commit found for SHA` | Your SHA is wrong or unpushed | Fix the search, not the conclusion |
| `Could not resolve to a PullRequest` | Wrong number | Re-resolve from the commit |
| `fatal: no such path 'x' in HEAD` | Wrong path, or the file was renamed | Follow the rename with `git log --follow` |
| `gh search prs` or `gh search issues` returns `[]` | **Ambiguous, and it is not a finding.** Both run on the search index and silently return nothing on syntax the index dislikes. Verified twice: `[]` for a quoted phrase that `gh api search/issues` found 3 hits for, and `[]` for a pull request that exists and matches. | Use `gh api -X GET search/issues -f q=...` |
| `Could not resolve to a Repository` | **An auth signal, not a missing repo.** A different account may have access. | Check which account is active |

**Always search through the API form, never the `gh search` subcommand:**

```bash
gh api -X GET search/issues -f q="repo:<owner>/<repo> path/to/file.ts" --jq '.total_count'
```

It returns `total_count`. A zero from `total_count` is an **assertion** that
nothing matched. A `[]` from `gh search` is an absence, and an absence is not
evidence.

### Rate limits

Core REST is 5000 per hour. Search is 30 per minute. **Search is the real
ceiling.** Spend REST freely and budget search.

### Auth reality

Everything above was verified against a **public** repository. On a private one,
`Could not resolve to a Repository` is an auth signal, and the whole dig fails at
wave 2 until the right account is active. Check `gh auth status` and which account
is marked active before concluding that a repository has nothing to say.

### Never call

Slack aside, the code host is the one source here with cheap write tools sitting
next to the read ones. Do not touch `gh pr comment`, `gh pr review`, `gh pr merge`,
`gh issue comment`, `gh issue close`, or the graphical integration's
`issues_add_comment`, `issues_create`, `pull_request_create`,
`pull_request_create_review`, or any of its `git_*` mutating calls.

---

## 2. Chat search

### The chain

```
slack_search_public(query, response_format="detailed", limit=5)
  -> parse the channel id and the thread ts out of the permalink
slack_read_thread(channel_id, message_ts, limit=100)
```

### The trap, verified and silent

Search returns `Message_ts`, which is the timestamp of the **matching message**,
usually a reply. It also returns a `Permalink` containing
`?thread_ts=<parent>&cid=<channel>`.

Pass `Message_ts` to `slack_read_thread` and the call **succeeds**. It returns the
single reply plus "No thread messsages" and "There are no more messages in this
thread." An agent reads that as an empty thread and moves on. Pass the `thread_ts`
parsed out of the permalink and the same call returns the real root and its
replies.

**Both calls succeed. Only the content differs.** There is no error to catch.

> **Rule: parse `thread_ts` from the permalink. Never pass `Message_ts`.**

Second lesson from the same probe: the thread root was about a different topic from
the reply that matched. **Threads drift.** Read the root, then decide whether this
is even the right thread.

### Query syntax

| Works | Notes |
|---|---|
| `in:channel-name` | Plain name, no hash |
| `"exact phrase"` | |
| `health*` | Wildcard, 3 character minimum |
| `after:YYYY-MM-DD`, `before:YYYY-MM-DD` | Real and reliable |
| `is:thread`, `has:link`, `has:file`, `has:pin` | |
| `from:<@U123>`, `to:me` | |
| `-word` | Negation |
| `sort="timestamp"`, `only_my_channels=true` | Parameters, not query tokens |

| Does not work | What happens |
|---|---|
| `OR`, `AND`, `NOT` | A query containing `OR` returned "No results found.", byte-identical to a genuine miss |
| Semantic search | Reported unavailable |

Space-separated terms are already AND.

### Failure mode: the worst of the six

Bad syntax, a genuinely absent term, and a wrong channel name **all produce
byte-identical output**: "No results found." Chat search cannot tell you that your
query was wrong.

Disambiguation procedure:

1. **Control query.** One word you know exists in this workspace. If the control
   also returns zero, the search path is broken, not the evidence.
2. **Strip modifiers one at a time** and re-run. If dropping `in:x` produces hits,
   the channel name was wrong.
3. **Fall back to a channel window.** `slack_read_channel(channel_id,
   oldest=<unix_ts>, latest=<unix_ts>)` is verified working, and it is the move
   when search fails but you know the date.
4. `slack_search_channels` resolves names but is weak. It returned zero for a
   common department word in a workspace that certainly has such channels.

### Limits and cost

- `slack_search_public` is **public channels only.**
- `slack_search_public_and_private` exists, and its own description says to request
  and wait for user consent first. **Private search needs an explicit human OK.**
- `limit` maxes at 20 per page, with cursor pagination.
- Bot messages are excluded by default.
- `include_context=true` is the **default** and roughly triples the payload. Sweep
  with `include_context=false, response_format="concise"`, then re-run `detailed`
  on the one hit you want, because you need `detailed` to get the channel id and
  the permalink.

### Never call

Anything that sends, schedules, reacts or writes a canvas:
`slack_send_message`, `slack_send_message_draft`, `slack_schedule_message`,
`slack_add_reaction`, `slack_create_canvas`, `slack_update_canvas`,
`slack_create_conversation`. Reading a thread is archaeology. Replying in it is
contamination.

---

## 3. Error tracking

### Find incidents touching this code

```
search_issues(organizationSlug=<org>,
              query='stack.filename:"*<partial-name>*"',
              period='90d',
              includeExplanation=true)
```

**Write the wildcard yourself.** Natural language "issues in authFailure.ts" got
rewritten to a weaker exact-match `filename:authFailure.ts` and returned **zero**
on a file that is a frequent real stack frame. The explicit
`stack.filename:"*authFailure*"` form returned 5 real issues.

| Field | Verdict |
|---|---|
| `stack.filename:"*x*"` | The one that works. Always wildcarded. |
| `stack.function:<name>` | Useless on minified bundles. Frames came back as `(o)` and `(t)`. |
| `culprit:` | In practice held a route path, not a filename. **Do not treat it as a code location.** |
| `is:regressed`, `firstSeen:-20d` | Real filters, verified |

### It is an entry point to wave 1, not only a corroborator

`get_sentry_resource` on an issue returns the stack trace **with source-context
lines**: file, line, column, and the surrounding source. It also returns a
`release` tag that is a 40 character git sha. Both feed straight back into wave 1:

```bash
git show -s --format=%B <sha>
gh api "repos/<owner>/<repo>/commits/<sha>/pulls" --jq '.[0].number'
```

So an incident is a legitimate **starting point** for a dig, not just a thing you
check afterwards. A stack frame gives you the file and the line to blame, and the
release sha gives you the commit without blaming anything.

### The causal story takes two calls

```
get_sentry_resource(resourceType='issue', organizationSlug=<org>, resourceId='<PROJECT-123>')
```

Returns description, culprit, first seen, last seen, occurrences, users impacted,
status, substatus (`ongoing` or `regressed`), issue type, platform, project, url,
and one sample event with stack trace, HTTP request, tags and context.

It does **not** return first release, last release, a suspect commit, or
breadcrumbs. For the release that introduced it:

```
search_events(organizationSlug=<org>, dataset='errors', projectSlug=<project>,
              query='issue:<PROJECT-123>', fields=['release','timestamp'],
              sort='timestamp', limit=1)
```

Caveat found live: a release string came back as literally `HEAD` while a real
commit sha sat in the event tag. **Check the naming scheme before treating a
release string as an identifier.**

### The failure mode that will burn an agent

**An invalid field name is silently stripped and the query then runs unfiltered.**
`bogus_field:someval` returned the same results as a bare organisation-wide
baseline. Nothing errored. Only `includeExplanation: true` revealed it:

> Removed 'bogus_nonexistent_field:someval' because ... is not a valid Sentry
> issue search field.

> **Rule: always pass `includeExplanation: true` and read the echoed query line
> back. If your filter term is not in it, the results are not evidence. They are
> the unfiltered default.**

An honest zero looks different, and says so: "No issues found matching your search
criteria."

### And then the good news: a checked zero here is trustworthy

With `includeExplanation: true` the response carries a `## Query Translation` block
echoing the query that was actually run. **If your filter term appears in the echo
and the count is zero, the absence is real.**

That makes this the only one of the three ambiguous-looking sources that can prove
its own zero. Chat search and meeting search cannot. The rule to read the echo does
not relax; the echo is exactly what buys you the trust.

### Issue titles can leak

One real issue title held a provider key masked in the middle and **not at the
ends**. Never echo an issue title verbatim into a report, a note, a commit message
or a handoff line. Paraphrase it, or quote the issue short id instead.

### Cost

| Call | Cost |
|---|---|
| `search_issues`, `get_sentry_resource` | Fast. Fire speculatively. |
| `search_events` aggregations | Slowest and least reliable. One aggregation with a `transaction:` filter **timed out**, while the same query filtered by `issue:<shortId>` succeeded instantly. |
| `analyze_issue_with_seer` | 2 to 5 minutes on first run, cached after. **Never chain it automatically.** Only on a named issue, as a last step. |

### Never call

`update_issue`. It resolves, assigns and changes status. It is one autocomplete
away from the read calls and it changes another team's triage queue.

---

## 4. Product analytics

`exec` takes exactly two required parameters: `command` (string) and `context`
(string, 15 to 25 words, third person, no first-person pronouns, no secrets).

### Explain a feature-flag branch in code

```
call feature-flag-get-definition-by-key {"key":"<flag-key>"}
call feature-flags-activity-retrieve   {"id":<numeric_id>}
call feature-flags-status-retrieve     {"id":<numeric_id>}
call experiment-list                   {"feature_flag_id":<numeric_id>}
```

**Read the flag's `name` field first. It is the highest hit rate per token of any
source on this page.** Not the key, the `name`. Keys are terse by convention;
`name` is a free-text field and people put the rationale in it. One real flag's
name held a full paragraph: what it gates, the design document it implements, the
rollout groups, and the default. One call, no search, and the reason is already
written down.

Then branch on `status`. **`STALE` means the flag branch is dead code and the
decision has already been made.** The host does not need archaeology on a branch
nobody is choosing between any more; it needs to know it can delete it.

**`feature-flags-activity-retrieve` is the archaeology tool** when `name` did not
answer it. Audit entries carry
the user email, an exact ISO `created_at`, a `client` field where a value of `mcp`
tells you it was changed by API and not by a human in the UI, and `detail.changes`
with field-level before-and-after diffs including targeting rule changes.

Gap to know: `feature-flag-get-all` returns id, key, name, `updated_at`, status,
tags and url, but **no `created_at`**, so you cannot date a flag's birth from the
list. Go to the activity endpoint and find the `created` entry.

`experiment-list` accepts `feature_flag_id`, and its rows carry the flag key, so
the link works in both directions.

### Did a metric actually move

1. `annotations-list` **first.** Fields: `date_marker` (the pinned date, separate
   from `created_at`), `content`, `creation_type`, `scope`, `created_by`,
   `deleted`. Deploys get pinned here. **Check it before concluding that a code
   change caused a dip.**
2. `read-data-schema {"query":{"kind":"events"}}` to confirm the event name exists.
3. `query-trends`.

Cost: 5 calls cold, 2 warm with schemas cached in the session.

### Failure mode: the cleanest of the six

A **typed miss**. `found: false` plus a `message` naming the missing key. Branch on
`found`.

An empty listing returns a valid paginated envelope with `count: 0`, which means
nothing was recorded, **not** that the query was bad. These two are distinguishable
and that makes this source trustworthy.

### Never call

Any `*-create`, `*-update` or `*-delete` command. The `exec` tool is one string
away from writing: it exposes flag, experiment, dashboard, insight, annotation and
cohort mutation through the same entry point you are reading with. Read commands
only, and keep the `context` string free of secrets, as its own contract requires.

---

## 5. Meeting transcripts

### The hard answer, verified across five keyword probes

**Search does not return sentence text.** Every hit returns id, title, dateString,
duration, organizerEmail, meetingLink, a summary object, attendees and
participants. **No field contains the matched sentence or a snippet.**
`scope:sentences` only changes what the service matches against internally, not
what it hands back.

So a search hit is a pointer, never a quote.

### The chain to an actual quote

1. `fireflies_search(query='keyword:"<term>" scope:sentences from:YYYY-MM-DD limit:5', format='json')`
2. `fireflies_get_summary(transcriptId)` **This is the cost saver.** Cheap, and its
   notes and action items carry embedded `(MM:SS)` timestamps. Use them to know
   where to look.
3. `fireflies_get_transcript(transcriptId)` Sentences as
   `[MM:SS - MM:SS] Speaker Name: text`. An 11 minute standup was about 140 lines,
   roughly 2500 to 3500 tokens.
4. Deep link the decision: `https://app.fireflies.ai/view/{transcriptId}?t={seconds}`

### Failure mode: as bad as chat search, plus a silent partial

A zero returns `{"query":"...","results_count":0,"results":"[]"}`. **Deliberately
broken grammar produced a byte-identical response.** Unrecognised grammar tokens
are silently dropped and never flagged. Quoting made no difference.

Date filtering **is** real and verified, which makes it the one modifier you can
trust.

So: run a control query first, stick strictly to the documented tokens, and treat
any zero as **inconclusive**, never as a negative finding.

Documented tokens: `keyword:`, `scope:title|sentences|all`, `from:`, `to:`,
`limit:`, `skip:`, `organizers:`, `participants:`, `mine:`, `channel:`.

**Quote the keyword.** Write `keyword:"foo"`, not `keyword:foo`.

**The parameter naming is inconsistent and it will bite.**

| Call | Parameter |
|---|---|
| `fireflies_get_transcript` | `transcriptId`, camelCase |
| `fireflies_get_summary` | `transcriptId`, camelCase |
| `fireflies_get_soundbites` | `transcript_id`, **snake_case** |

**Extra trap.** `fireflies_get_transcript` can return a trailing "Partial results:
some fields may be missing due to N error(s)" with no detail on which fields. Check
for that string. A transcript that returned is not necessarily complete.

### Never call

`fireflies_share_meeting`, `fireflies_move_meeting`,
`fireflies_update_meeting_title`, `fireflies_update_meeting_privacy`,
`fireflies_revoke_meeting_access`, `fireflies_create_soundbite`. Two of those
change who can see a recording of real people talking. That is the worst
irreversible action available anywhere in this skill.

---

## 6. Bug recordings

### Order, and the order is the point

1. **`getDetails(jamId)` first.** It appends its own Investigation Guide and a
   `postprocessing.byWorkload` block that tells you which later calls will even
   work.
2. `getConsoleLogs(jamId, logLevel:['error','warn'])`
3. `getNetworkRequests(jamId, statusCode:['4xx','5xx'])`, widening only if empty.
4. `getVideoTranscript` **only if** postprocessing shows the transcript ready.
5. `getUserEvents` **last**, scoped to the window the earlier calls pointed at.

**`getUserEvents` is a token bomb.** 28 events expanded to thousands of tokens
because it dumps full CSS class lists twice, once in `interactivity_target_class`
and again in `interactivity_target_selector`. Never call it speculatively.

### Security, and this is a hard rule

**Two probes disagreed here, so this is written to the conservative reading and
neither claim is asserted.**

| Probe | Reported |
|---|---|
| One | `getNetworkRequests` with `bodies:"all"` returns request and response bodies, truncated at 4 KB, and the service does not scrub the application's own headers or bodies |
| Two | Only **sizes** come back (`network_request_body_size`, `network_response_body_size`, `*_truncated`), and the service scrubs at capture, replacing a third-party key with the literal string `JAM_DOES_NOT_SAVE_SECRETS` |

What is safe to say: the service scrubs its own captured secrets, and in testing it
returned sizes rather than bodies. But **the `bodies` parameter exists**, and one
probe saw content.

> **So: never echo anything credential-shaped out of any response from this source,
> whatever it turns out to contain. Write `[REDACTED]`.**

The rule costs nothing when it is unnecessary and saves a leaked session cookie
when it is not. That asymmetry is the whole argument.

### Finding a recording

`search` **only extracts a UUID.** A raw UUID or a recording URL works. Plain text
returns `{"results":[]}` with no error at all.

Given a bug title, use `listJams` instead. Verified filters:

| Filter | Matches |
|---|---|
| `query` | Text, on title and description |
| `url` | Partial page URL, case-insensitive. **This is the archaeology filter:** which bug reports touched this page. |
| `createdAt` | ISO 8601 duration, for example `-P7D` |
| `type` | |

`getVideoTranscript` on a recording with no microphone fails with a hard error, and
note that it gives **two different error strings for the same condition** depending
on whether you asked the tool directly or read `getDetails`.

### Failure mode: the best behaved of the six

An empty envelope means empty. A bad id errors loudly. You can trust a zero here
without a control query.

### Never call

`createComment`, `editComment`, `deleteComment`, `addReaction`, `removeReaction`,
`updateJam`, `deleteJam`, `createFolder`, `updateFolder`, `deleteFolder`,
`createRecordingLink`, `updateRecordingLink`, `deleteRecordingLink`. A comment left
on someone's bug report is the most visible way this lens can break its own read-only
promise.
