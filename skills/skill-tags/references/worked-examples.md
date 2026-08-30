# Worked examples

Four composed runs. Each shows what the lens actually changed, which is the only
way to judge whether it earned its cost.

---

## 1. `/graph-engineering -why`

**Ask:** "Split this 400-file migration into a graph and run it."

**What the bare host would do.** Audit dependencies, find the fan-out, batch the
files, run workers, gate the merge.

**What `-why` changed.** Before the audit, the archaeology found that 31 of the
400 files were touched by a single revert six months ago, and the PR that
reverted them says the batch import corrupted a foreign key.

**The effect on the graph.** Those 31 files stopped being 31 independent nodes.
They became one node with a hard gate, because the last time somebody treated
them as independent it broke production. The lens did not add work. It changed
one edge in the dependency audit, which is exactly what a lens is for.

**What it cost.** Four minutes and about a dozen read-only calls.

---

## 2. `/overnight-dev -why -obsidian`

**Ask:** "QA the app overnight, report in the morning."

**`-why` before.** Pulled the last 90 days of error telemetry and the three
incident threads. Two of the four "bugs" the QA loop was about to file were
already known, already triaged, and deliberately deferred.

**The effect.** The morning report separated *new* from *known-and-deferred*.
Without the lens the human opens a report with four items and has to remember
which two do not matter, which is the tax that makes people stop reading reports.

**`-obsidian` after.** Wrote one note per confirmed finding, each with a
`caused` edge to the commit and a `references` edge to the incident thread.

**The payoff is the second night.** The next run reads those notes first and
starts from a shorter list. This is the learning edge from
[graph-engineering](../../graph-engineering): a confirmed cause becomes a
permanent constraint, so the next run starts where this one ended.

---

## 3. `/stacked-prs -whatwillmattdo`

**Ask:** "Carve this 300-commit branch into a stack."

**What the bare host would do.** Find the layer boundaries, cut the stack,
verify each layer builds, open the PRs.

**What the lens changed.** At the layer-boundary decision, the host had one
defensible cut. The lens requires a second one before committing to the first,
then a stated reason for the choice. The second cut was worse, and the written
reason is now in the PR description, so the reviewer does not have to ask.

**What it also changed.** "Each layer builds" stopped being the bar. Each layer
has to be independently revertible, because a stack that builds but cannot be
partially reverted is a stack that has to land all at once.

**What it cost.** Roughly a third more tokens and one extra rework loop. Worth
it here because the output is going to be reviewed by other people. Not worth it
on a throwaway spike.

---

## 4. `/agent-fleet -ask`

**Ask:** "Run six workers over the repo and fix the accessibility failures."

**Why a lens instead of just starting.** Six workers on a guess is six times the
wrong work. The fork here is real: some failures need a design decision that no
worker can make, and running first means finding that out six times in parallel.

**What `-ask` did.** Collected the open questions, auto-answered four of them
from the repo and the archaeology, and found that the remaining two collapsed
into one actual decision: whether the contrast fix is allowed to change the brand
palette.

**One question went to the human.** Not six. The other five were answered from
evidence, and each answer was recorded with its source so the human can check the
reasoning instead of taking it on trust.

**The budget worked.** `-ask` had a budget of 1 and spent it on the only question
that changed what the fleet would do.

---

## Reading these

The pattern in all four: the lens changed **one decision**, early, and the run
was different from there on. That is what a good lens does.

If you can describe a lens's effect only as "it was more careful", it did not
earn its cost. Find the decision it changed, or drop it.
