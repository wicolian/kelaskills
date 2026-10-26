---
name: leaving-pr-comments
description: Use whenever you post, reply to, or resolve a GitHub PR comment or review on the user's behalf, or answer a review bot.
---

# Leaving PR comments

Every comment an agent posts through the user's account says so, and still reads
like the user.

Adapted from Theo Browne's [tstack](https://github.com/t3dotgg/tstack) (MIT), fitted
to our rules.

## The note

Start the comment with this callout. Say the real model name the harness reports;
if it reports none, say the harness name.

```md
> [!NOTE]
> 🤖 **<model> speaking for <user's GitHub login>**

the comment starts here.
```

Attribution stays inside the note. No signature, footer, heading or second
attribution. Use it on top-level comments, inline review comments, bot replies, and
the reason you write before you resolve a thread. Not on PR descriptions or commit
messages.

## The voice

- all lowercase, no em or en dashes. check the draft with
  `grep -nP '\x{2014}|\x{2013}'` before you post.
- the decision first, then the reason. one or two things that matter, then stop.
- cite the code, the check, or the output. keep fact apart from opinion.
- no thanks, no status story, no repeat of the author's own description.
- post as a **comment** review, never approve or request changes.
- a real `lgtm` is a full review.

```
Bad:  Great work on this PR! I've taken a look and there's a potential issue
      worth considering, since the cache key may not include the tenant id.
Good: blocking: cache key in metricCache.ts:42 has no tenant id, so two tenants
      share rows. add clientId to the key.
```

## Before you post

- No secrets, no box links, no local paths (`/home/...`, `~/...`, `localhost`).
- No AI trailers (`Generated with`, `Co-authored-by` a model, `Claude-Session`) in
  databrainhq repos. CI rejects them.
- Nothing the user said in private.
- Preview the markdown. After posting, check GitHub returned the URL. Resolve a
  thread only after the reply is posted.
