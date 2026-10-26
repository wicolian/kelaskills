---
name: takeover
description: Use when the user says "take over this PR", "take this over", "takeover", "finish their branch", or "pick up where that agent stopped".
---

# Takeover

Finish the original goal of someone else's PR, branch, or agent thread, and keep
their credit. Do not defend their implementation only because it exists.

Adapted from Theo Browne's [tstack](https://github.com/t3dotgg/tstack) (MIT), fitted
to our rules.

## Steps

1. **Read all of it:** the PR or thread, review findings, later corrections, the
   current head, and any uncommitted work. The handoff is context, not proof.
2. **New branch from their commits.** Bring their commits onto a new branch, then
   add your fixes as separate commits. Keep their Git authorship and co-author
   lines. Continue in place or as a stack only when the user asks for that.
3. **Bring it up to date** with `modernize`. Rework only what the same goal needs.
4. **Prove it** as `full-send` says: the original failure, then the real flow in a
   running product. Say what stays unproved.
5. **File it** with `file-pr`, then `babysit-pr`. In the description, add:

   ```markdown
   ## Original authors
   - @<login>, #<original PR>
   ```

   Request review from each original author.
6. **The original PR:** do not change, merge or close it unless the user asks. When
   you close it, first post a comment (with `leaving-pr-comments`) that links the
   new PR.

If the work will be squashed, put the human authors in the merge commit as
`Co-authored-by:` lines, with identities you checked in Git history. Model
attribution is not author credit.

## Report

What you got, what you changed, how you proved it, how credit is kept, and any
decision that is left.
