# Proving a zero

"No evidence" and "my query was wrong" look identical in most of these systems.
This page is how you tell them apart, so that `CONFIDENCE: absent` is a finding a
host can act on rather than a shrug.

**The claim you are about to make.** `absent` says: the reason is not recorded in
any system I can reach. That is a strong claim about the world. A silent search
path makes the same output with no claim behind it at all. The control query is
what buys you the right to the claim.

Read this before you write `absent`. Not after.

---

## Which zeroes are honest

| Source | Zero shape | Trust it? |
|---|---|---|
| Product analytics | **Typed miss.** `found: false` plus a `message` naming the missing key. An empty listing is a valid paginated envelope with `count: 0`. | **Yes.** Branch on `found`. No control needed. |
| Bug recordings | Empty envelope means empty. A bad id errors loudly. | **Yes.** No control needed. |
| Code host, REST | `commits/$SHA/pulls` returning `[]` is an answer: no pull request exists. A wrong SHA gives HTTP 422 instead. | **Yes.** The two cases are distinguishable. |
| Code host, search | `gh search prs` and `gh search issues` return `[]` on syntax the index dislikes. Verified twice, including for a pull request that exists and matches. | **No.** Re-run through `gh api -X GET search/issues`, which returns `total_count`. |
| Error tracking | Says "No issues found matching your search criteria", **and** echoes the query it ran under `## Query Translation` when you ask for an explanation. | **Conditionally.** Honest once you have read the echo and found your filter in it. An invalid field is stripped silently and the search then runs unfiltered. |
| Chat search | "No results found." | **No.** Byte-identical for bad syntax, an absent term, and a wrong channel name. |
| Meeting search | `{"query":"...","results_count":0,"results":"[]"}` | **No.** Deliberately broken grammar produced a byte-identical response. Unrecognised tokens are dropped and never flagged. |

Three of the seven rows need no control. Two need a cheap check you were going to
run anyway. **Two are genuinely blind**, and they are the two where "we discussed
it somewhere" usually lives.

---

## The protocol

Run it once per source that returned zero. Not once per query.

### Step 1: the control query

Search the same source for **one term you already know exists in it**. Same tool,
same parameters, no filters.

- A hit means the path works. Your zero is about the evidence.
- A zero means the **path is broken**: wrong workspace, no permission, an
  unreachable server, an expired token. Your zero is about your plumbing, and it
  says nothing about the code.

**A broken path is never `absent`.** It is `NOT REACHED`, and you report it as
that, naming the source you could not read.

### Step 2: strip the modifiers, one at a time

Only if the control passed. Remove one modifier per run, in this order, and stop at
the first that produces hits:

1. The scope filter (channel, project, participant)
2. The date bounds
3. The quoting on the phrase
4. The wildcards

The modifier that was hiding the hits is the one you got wrong. A scope filter
producing hits when dropped means the channel or project name was wrong, not that
nothing was discussed.

### Step 3: the bounded window

If search still returns nothing and you know roughly **when**, stop searching and
read the window directly. Reading a time range is a different code path from
searching, and it does not go through the search index at all.

### Step 4: write it down

Only now may you write `CONFIDENCE: absent`, and it carries the receipts:

```
FINDING    No recorded reason for the retry cap on <path>:88.
SOURCE     commit <sha>; PR #<n>; chat control passed, 0 hits in <window>;
           error tracking echo confirmed stack.filename filter, 0 issues in 90d
CONFIDENCE absent
DECIDES    Treat the cap as unexplained. Widen the test around it before changing it.
```

The `SOURCE` line on an `absent` finding is **longer** than on a `stated` one, not
shorter. It has to name every path that was proven working and still came back
empty. That is the evidence that the dig happened.

---

## Control query shapes, per source

Placeholders: `<org>`, `<project>`, `<CHANNEL_ID>`, `<owner>/<repo>`.

### Chat search

```
slack_search_public(query='<a word certain to exist in this workspace>',
                    response_format="concise", limit=3)
```

Then, in order:

```
slack_search_public(query='"<phrase>"')                    strip in:
slack_search_public(query='<term> in:<channel-name>')      strip the dates
slack_read_channel(channel_id='<CHANNEL_ID>',
                   oldest=<unix_ts>, latest=<unix_ts>)     bypass search entirely
```

Notes that decide whether the zero was ever possible:

- `OR`, `AND` and `NOT` **do not work**. A query containing `OR` returns "No
  results found.", identical to a genuine miss. Space-separated terms are already
  AND.
- `in:channel-name` takes a plain name, no hash.
- Wildcards need 3 characters minimum.
- Search is **public channels only**. A private-channel discussion is invisible,
  and the private search tool requires explicit human consent first, which this
  lens has no budget to ask for. So report it as unreached, not as absent.
- Bot messages are excluded by default.
- `slack_search_channels` is weak as a name resolver. It returned zero for a common
  department word in a workspace that certainly has such channels. Do not use its
  zero to conclude a channel does not exist.

### Meeting search

```
fireflies_search(query='keyword:"<a word certain to appear in any meeting>" limit:3',
                 format='json')
```

Then:

```
fireflies_search(query='keyword:"<term>" limit:5')                strip scope
fireflies_search(query='keyword:"<term>" from:YYYY-MM-DD limit:5') keep dates only
```

- Date filtering **is** real and verified. It is the one modifier here you can
  trust, which makes it the right thing to keep when you strip the others.
- Everything else is silently dropped when it is not understood. Broken grammar and
  a real miss are byte-identical.
- Quote the keyword: `keyword:"foo"`, not `keyword:foo`.
- A search hit is a **pointer, never a quote**. No field carries the matched
  sentence. Confirming that a meeting exists is not the same as confirming what was
  said in it, so a hit still needs the summary and then the transcript.
- **This source's silence means nothing at all.** Never let it be the reason you
  wrote `absent`.

### Error tracking

The control is built into the call. Always:

```
search_issues(organizationSlug=<org>, query='<your filter>',
              period='90d', includeExplanation=true)
```

Then read the `## Query Translation` block back:

| Echo says | Verdict |
|---|---|
| Your filter term is present, count is zero | **A real zero.** Trustworthy. Write it. |
| "Removed '<term>' because ... is not a valid ... search field" | Your filter never ran. The results are the **unfiltered organisation-wide baseline**, and they are not evidence of anything. |
| Your natural-language phrase was rewritten to something weaker | Re-run with the explicit form. `stack.filename:"*<partial>*"` returned 5 issues where an unwildcarded rewrite returned 0. |

The separate baseline control, if you want one anyway: run the same call with no
query at all. If that is also zero, the project or the period is wrong.

Two field traps that manufacture false zeroes:

- `stack.function:<name>` is useless against minified bundles. Frames come back as
  `(o)` and `(t)`.
- `culprit:` held a route path, not a filename. Filtering it by a file name returns
  zero for a file that is all over the stack traces.

### Code host

```bash
gh api -X GET search/issues -f q="repo:<owner>/<repo> <term>" --jq '.total_count'
```

`total_count` is the control. A zero from it is an assertion. A `[]` from
`gh search prs` is an absence, and the two are not the same thing.

If the repository itself will not resolve:

```bash
gh auth status
```

`Could not resolve to a Repository` is an **auth signal**, not a missing repository.
A different account may have access. Everything on this page was verified against a
public repository; on a private one the dig stops at wave 2 until the right account
is active.

### Product analytics and bug recordings

No control query. Branch on the typed miss and on the empty envelope. If you find
yourself wanting a control here, you are treating a `count: 0` as suspicious when
it is an answer.

---

## The failure this whole page exists to stop

An agent runs four sources, gets four zeros, writes "no evidence found, proceeding
with the change", and deletes a guard clause that an incident put there.

Three of those four zeros were the tool telling it the query was malformed.

Absence of a result is not evidence of absence. The control query is the cheapest
way to tell the two apart, and it costs one call per source.
