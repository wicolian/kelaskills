---
name: switch-env
description: Use when pointing a local frontend dev server at a different backend - a local stack versus a shared cloud/staging environment. Triggers on "switch env", "point at localhost", "go back to the dev backend", "run against the local stack", API or GraphQL calls hitting the wrong environment, or a dev server that keeps serving stale env values after you changed them.
---

# Switch a dev server's backend

Swap which backend a local frontend talks to, without touching `.env` and
without losing your secrets.

## The pattern

Vite, Next and most modern dev servers load `.env` first, then `.env.local`, and
the later file wins. So:

- **`.env`** holds the committed defaults and your secrets. Never write to it.
- **`.env.local`** is the override. Write it to switch, delete it to switch back.
  It is gitignored in every framework default.

One script, three verbs:

```bash
./scripts/switch-env.sh local     # write .env.local pointing at the local stack
./scripts/switch-env.sh cloud     # delete .env.local, fall back to .env
./scripts/switch-env.sh status    # what actually resolves, and is it reachable
```

Keep the script in the repo, not in your dotfiles. Then it exists in whatever
checkout you are already standing in, and it cannot write the override into a
sibling checkout you are not working in.

There is no version of this that can lose your secrets, because `.env` is never
read, rewritten or backed up.

## The trap: switching restarts the dev server, and the restart can fail

**Dev servers watch env files.** Writing or deleting `.env.local` makes the
server restart itself. You did not ask for it and you cannot opt out.

A restart re-reads the config file and re-resolves every plugin. If
`node_modules` is incomplete - mid dependency migration, a half-finished
install, a branch switch with different deps - the restart fails:

```
failed to load config from .../vite.config.ts
Cannot find package '@vitejs/plugin-react-swc'
[vite] server restart failed
```

**The old process keeps holding the port.** So `curl` still returns 200 while
the app serves a broken bundle and the UI shows a generic error. The env switch
gets blamed. The real cause is the unresolvable dependency.

Before switching while a server is running, confirm deps resolve:

```bash
node -e "require.resolve('@vitejs/plugin-react-swc')" && echo OK
```

If that fails, fix the install first. Switching will take the server down.

## What belongs in the override

Only the values that actually differ. A short table in the script's header, so
the next person can read it without running anything:

| Variable | local | cloud |
|---|---|---|
| API base URL | `http://localhost:3000` | the shared service host |
| GraphQL endpoint | `http://localhost:8080/v1/graphql` | the shared endpoint |
| Auth issuer URL | `http://localhost:8089` | the shared identity provider |
| Auth realm / tenant | the locally provisioned one | the shared one |
| Environment name | `development` | whatever `.env` says |

**The auth realm is the one people forget.** A local identity provider is
usually seeded with a different realm or tenant than the shared one. The
committed `.env` is right for the shared server and wrong for yours, so login
fails with a message that says nothing about realms.

## status should check reachability, not just print values

Printing the resolved variables is half the job. When the override points at
localhost, the script should also say whether each of those ports answers.
Otherwise "the switch did not work" and "the backend is not running" look
identical.

## Common mistakes

| Symptom | Cause |
|---|---|
| Generic error page right after switching | The auto-restart failed on an unresolvable plugin. Read the dev-server output. `curl` will still say 200. |
| The switch appears to do nothing | Same thing. The old process is still serving old env values. |
| Login fails locally | Auth realm or tenant mismatch, or the local identity provider has no user seeded yet. |
| API 401s locally | The local admin secret is a dev default, not the cloud value. |
| Still hitting cloud after switching | A stale `.env.local` from another tool, or someone edited `.env` by hand. Run `status`. |
| Feature flags behave differently | The environment-name variable changed, and flags are usually scoped to non-production values. |

## Do not confuse this with container switching

Switching which **container image** serves the app on a port is a different
operation from switching which **backend** the local dev server talks to. Use
this skill when running the dev server directly. Use your container tooling when
running the app from an image.
