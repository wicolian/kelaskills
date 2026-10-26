---
name: full-stop
description: Use when the user says "full stop", "full-stop this", "get it ready but do not merge", or "make it ready for me to merge".
---

# Full stop

Same work as `full-send`, but you stop with the PR ready for the user to merge. You
never merge it.

Adapted from Theo Browne's [tstack](https://github.com/t3dotgg/tstack) (MIT), fitted
to our rules.

Read [full-send](../full-send/SKILL.md) and follow its steps, proof, review, babysit
and asking rules. A "full stop" request grants its test permission too. Its merge
permission does not apply. The rules below win.

## Never merge

You may commit, push, merge the base in, and fix conflicts on this task's branch.

You may not merge, turn on auto-merge, enter a merge queue, push to the default
branch, bypass branch protection, or hand any of that to another agent. Force push
is not allowed here either.

Auto-merge already on, or the PR in a queue? Turn it off before you start, check
again before each push, and say so in the report. Cannot stop it? Report that first.

## Stop at the gate

Use full-send's merge gate as the ready check. Proof and review must cover the final
diff. Then read the live PR: head, base, checks, reviews, mergeable, not a draft.

End in one of three states:

- **Ready to merge:** the gate passes. Leave it open.
- **Waits for approval:** only a human approval remains, and that is the real block.
- **Blocked:** what blocks it, what you tried, what is needed. Ask as full-send says.

Report: PR link, final head SHA, the state above, proof, review outcome, risks left,
and that the PR is still open and not merged.
