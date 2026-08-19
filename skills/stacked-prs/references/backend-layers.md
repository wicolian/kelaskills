# Layer order for backend work

The generic ladder in `carving.md` orders by import direction. A backend change
has a second constraint on top of that: **a migration is not dark.**

Application code can land unreachable - nothing calls it, nothing breaks. A
migration runs on deploy and changes production the moment the layer merges. So a
migration layer has to be safe against the code that is **already deployed**, not
just against the layers above it.

That single fact sets the whole order.

## The ladder

```
1  migration (expand)     additive DDL only: new tables, new nullable or defaulted
                          columns, new indexes. Safe against currently-live code.
2  generated types        ORM models, schema types, codegen output
3  API contract           DTOs, request/response schemas, OpenAPI, validators.
                          Types and shapes only - no handler is reachable yet.
4  shared services        repositories, query builders, the utils handlers need
5  implementation         the business logic. Complete, tested, wired to nothing.
6  routing / wire-up      the endpoint becomes reachable. THE SWITCH.
7  contract migration     drop columns, delete tables. A LATER STACK, not this one.
```

## The two things people get wrong

**1. Treating "the API" as one layer.**

It is two, and they sit at opposite ends:

| Half | Where | Why |
|---|---|---|
| **Contract** - DTOs, schemas, validators, generated clients | layer 3, early | Everything above compiles against it. Put it late and layers 4-5 typecheck against a shape that is about to change. |
| **Routing** - the router entry, the handler registration, the serverless config | layer 6, last | This is the only layer that changes what production does. |

Keep them apart and layer 6 comes out at 2-5 files. That is the layer a reviewer
should read twice, and in a single fat PR it is invisible.

**2. Putting the migration in the same layer as the code that needs it.**

Then you cannot roll back the code without rolling back the schema, and rolling
back a schema with live data in it is not a revert - it is an incident.

Separate layers means: revert layer 5, schema stays, nothing is lost.

## Expand and contract, across two stacks

**Never put an additive and a destructive migration in the same stack.**

```
stack A   1 expand -> ... -> 6 route at the new column
          (deploy, soak, watch)
stack B   1 contract: drop the old column
```

The soak between them is the point. A destructive migration is only safe once
you have evidence that nothing reads the old shape any more, and you cannot have
that evidence until the new code has been live for a while.

If your carve produces a layer that both adds and drops, split it. The drop
belongs to the next stack, not the last layer of this one.

## Verifying a migration layer

A migration layer's gate is not "does it compile". It is:

```bash
# against a scratch database, not a shared one
migrate up      && \
migrate down    && \
migrate up
```

Up, down, up. **A migration without a working down is not a layer, it is a
one-way door.** If the tool cannot generate a down, write it by hand or say
plainly in the PR body that this layer is not reversible.

Then the real check: **start the currently-deployed application code against the
migrated schema.** Layer 1 is safe only if the old code still runs on the new
shape. That is what "expand" means, and it is the check most people skip.

## Ordering inside the migration layer

More than one migration in a layer runs in filename order. Two rules:

- One logical change per migration file. A file that adds a table and backfills
  it cannot be rolled back halfway.
- **A backfill is not a migration.** Long-running data movement belongs in a job
  the routing layer can turn on, not in DDL that blocks a deploy.

## Trunk choice for backend stacks

Backend stacks usually want the **integration branch**, not `main`, because the
layers merge one at a time and each one deploys.

| Landing | Trunk |
|---|---|
| Layers merge over days, each deploying to an environment | integration branch |
| Whole stack lands at once via `gh stack merge` | `main` |

A migration that merges on Tuesday and a route that merges on Friday is normal
and fine. A half-deployed stack is only dangerous when a layer is destructive -
which is why layer 7 lives in a different stack.

## When the change spans backend and frontend

The backend stack lands first, entirely. The frontend stack is a separate stack
that assumes the API exists.

Do not interleave them. A cross-repo stack has no tooling, no atomic merge and no
way to express the dependency, so the only thing holding it together is someone
remembering the order.
