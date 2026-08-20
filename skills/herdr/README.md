# herdr: not vendored here, on purpose

`agent-fleet` in this repo needs the **herdr** skill to be installed, but that skill
ships with herdr itself. It is not mine to redistribute, and a vendored copy would
go stale on every herdr release.

Install it from the tool, then both skills work together:

```bash
npx skills update        # herdr's own agent skill lands in ~/.agents/skills/herdr
```

Check it is live with `HERDR_ENV=1` set inside a herdr pane.
