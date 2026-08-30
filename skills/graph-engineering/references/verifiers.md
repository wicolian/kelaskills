# Verifiers: the compiler the work never came with

Read this when writing the check for a node, when a gate keeps passing work that
turns out to be wrong, or when a reviewer agent agrees with everything.

## What a compiler actually is, to the person using it

Not "a thing that turns source into a binary". To someone writing code, a
compiler is three things welded together:

1. **Something that pushes back when you err.** You write a type mismatch, it
   stops you cold.
2. **Something that cannot be argued out of its judgement.** You cannot rephrase
   the mistake until it relents.
3. **A verdict that is public and repeatable.** Run the same code on another
   machine and get the same answer.

Programming is unusual in that all three arrive free, bundled with the language.
You do not build the resistance. You inherit it.

This is the quiet reason coding agents work as well as they do. Not because the
models are sharper at code than at prose, but because code is the rare domain
where reality checks the work automatically, every time you hit run. The agent
proposes and the world disposes, at no cost to anyone.

**Loop and graph engineering are what you do when that gift is absent.** The
first move is diagnostic, not constructive: what would a compiler be for this
task, and does one already exist? If it does, use it. If it does not, you have
found the thing the graph has to fabricate.

## The ladder: every abstraction level wants its own compiler

A real codebase already runs a stack of them, and each rung checks something the
rung below cannot see.

| Rung | Verifier | Rules on | Verdict is |
|---|---|---|---|
| 1 | Formatter | Whitespace | Instant, automatic, external |
| 2 | Linter | Style, banned patterns | Instant, automatic, external |
| 3 | Type checker | Whether the pieces fit | Fast, automatic, external |
| 4 | Test suite | Whether the program behaves | Minutes, automatic, external |
| 5 | Rendered output / screenshot diff | Whether a human sees the right thing | Slow, semi-automatic |
| 6 | Independent reviewer | Whether the design is sound | Slow, judgement, semi-external |
| 7 | Pilot, canary, real usage | Whether it works in the world | Very slow, expensive, genuinely external |
| 8 | Taste, strategy, "is this the right question" | Nothing external is left | **No compiler can exist here** |

What changes as you climb: the verdict gets slower, less automatic and less
external. The check at the top still does the same essential thing as the one at
the bottom, take a claim and force it against something real, but it has to reach
much further to touch reality, and the touch is less certain when it gets there.

**The practical question for any node: which rung am I on, and what would a
verifier have to be here, for this kind of claim?**

Most graph designs quietly assume rung 4 and then verify at rung 6 with a second
model. That is a two-rung gap, and it is where false "looks good" lives.

## The replicas are samplers, not oracles

A real compiler is total and deterministic. It checks every case, every time,
with no gaps and no opinions. The verifiers you build by hand are partial and
probabilistic:

- A test suite only checks the cases you thought to write.
- A reviewer only catches what it happens to notice.
- A pilot only measures the slice of the world you instrumented.

Each is a sample of reality standing in for complete coverage. You never quite
get the compiler's guarantee out the other end. You get a probabilistic shadow of
it, and the size of the shadow is the real craft.

The skill is choosing **the cheapest sample of reality that still genuinely
resists**: a check small enough to run constantly but real enough that the work
cannot fake its way past it.

Say which one you built. "Tests only, no visual check" is a useful sentence. "It
is verified" is not.

## Independence is the part that is easy to fake

A compiler's authority comes from one property above the others: **it cannot
share your framing.** It engages your work on its own terms, so when it disagrees
the disagreement is information rather than an echo.

Reproduce everything about a compiler except this and you have built something
worse than nothing, because it emits crisp pass/fail verdicts while sharing the
worker's blind spot. A thing can be shaped exactly like a compiler, same inputs,
same crisp outputs, and still not be one, because the property that made the
compiler trustworthy is the invisible one.

Ranked, most independent to least:

| Verifier | Independence | Use for |
|---|---|---|
| A deterministic program (tests, types, counts, diffs) | Total | Everything you possibly can |
| A different model, fresh context, given only claims and sources | High | High-stakes output |
| The same model, fresh context, given only claims and sources | Medium | Most reviews |
| The same model, fresh context, given your synthesis | Low | Nearly worthless. It ratifies the summary. |
| The same agent, same context, asked "is this right?" | **None** | Never. This is theatre. |

Three practical rules that follow:

1. **Never let an agent verify its own work in its own context.** Not "prefer
   not to". Never.
2. **Give the verifier the sources, not your synthesis.** A critique pass over a
   summary agrees with the summary. Hand it the claims and the raw material and
   make it re-derive at least one claim from source.
3. **Constrain the verifier's tools.** An agent with `Read` and `Write` only
   cannot go and find justifying context. The tool surface is a stronger gate
   than any instruction, because it is not negotiable.

## Anchors: the failure that gets a graph, specifically

Imagine an organisation that builds the full graph. Paired metrics, audit nodes,
a meta-node tuning the lower nodes' thresholds. And every one of those nodes
consumes reports. The audit node checks the ops numbers against the finance
numbers; the finance numbers come from the same systems ops feeds; the meta-node
tunes thresholds using dashboards built on all of it.

Every node watches another node and no node touches the ground.

This graph is circular. An elaborate network of mutual confirmation in which
everything is consistent and nothing is verified. It fails exactly as a single
loop fails, only later and more expensively, with far more green lights on the
way down. **The topology bought sophistication. It did not buy contact with
reality.**

So the graph needs anchors: measurements that cannot be argued with.

| Anchor | Not an anchor |
|---|---|
| The test process exited 0 | An agent reported that tests pass |
| `git diff --stat` shows 23 files, all under `src/utils/` | An agent said it only touched utils |
| The screenshot's pixel diff is under threshold | An agent said the layout looks correct |
| The export list before and after are byte-identical | An agent said the public API is unchanged |
| The row is in the database | The write returned no error |
| HTTP 200 and the response body contains the expected id | HTTP 200 |

At least one anchor per graph. Preferably one per lane.

## Frozen nodes

Some rules must be ones the graph is never allowed to tune, precisely because
they are the rules an optimiser would be tempted to weaken.

- The held-out check the workers never see.
- The lane that does not open.
- The approval gate.
- The scope constraint on a returned unit.

**If a run "needs" to relax one of these to finish, that is the finding, not the
workaround.** Write it down and stop.

## Goodhart, and why a metric never travels alone

A measure optimised hard enough stops measuring what it once did. The reason is
structural, not moral: a loop can only see its metric, so it will find every way
to move that metric, including the ways that betray its purpose. The loop is not
malfunctioning when it games its own measure. It is doing exactly what it was
built to do, on a number that quietly detached from the thing it stood for.

The topological answer is pairing. Every optimising check gets a watching check
on a counter-metric that catches the cheap way to win.

| Optimising for | Cheap way to win | Pair it with |
|---|---|---|
| Tests passing | Delete or skip the failing test | Test count and coverage must not fall |
| Type errors at zero | `any`, `@ts-ignore`, `as unknown as` | Grep the diff for suppressions |
| Lint clean | Inline disable comments | Count of disable directives must not rise |
| Small diff | Doing less of the task | Acceptance criteria checked separately |
| Fast completion | Skipping the hard slice | Every planned unit accounted for |
| "No findings" in a review | Reviewing shallowly | Seed a known defect and check it is caught |

That last row is the cheapest high-value trick available. If your review node has
never found a real problem, it cannot. Prove otherwise by planting one.

## Where the tower ends

Keep climbing and the thing you check against gets steadily less external. The
linter checks against a written rule. The test checks against an execution. The
pilot checks against the world, slowly and expensively but really. Then you reach
"is this wise", "is this in good taste", "is this even the right question", and
there is no external referent left at all.

Treat that as a level where **no compiler can exist**, not as a gap better tooling
will close. Above that line the strategy changes rather than scales. Stop trying
to compile the judgement. Make it auditable: surface the reasoning and the
evidence so completely that a person can take the verdict themselves, then hand
it over.

And note the other half the metaphor leaves out. A compiler presupposes a
specification. It can only check your code because "correct" already exists,
fixed and external, before the checking begins. A large share of serious work is
the part *before* the spec exists: deciding what the question is, inventing the
frame that makes the problem tractable, deciding what would even count as a good
answer. No verifier performs that for you. A sharper gate tells you whether you
met a standard. It never tells you which standard was worth meeting.
