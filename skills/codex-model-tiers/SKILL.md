---
name: codex-model-tiers
description: Use when configuring or explaining a shared `gpt` shell wrapper for Codex model selection, service-tier routing, or a 1M context window. Triggers on "Codex tier", "Luna fast", "Terra standard", "Sol flex", "Astra flex", "gpt alias", "Codex context window", or "which Codex model should an agent use".
---

# Route Codex models through `gpt`

Make one `gpt` command choose the right Codex service tier for the selected
model. This is a local developer-machine setup task. It does not change a
repository, an API project's billing settings, or another person's shell.

## The shared convention

| Model | Tier | Use it with |
|---|---|---|
| `gpt-5.6-terra` | standard, represented by `default` | the default, or `-m gpt-5.6-terra` |
| `gpt-5.6-luna` | `fast` | `-m gpt-5.6-luna` |
| `gpt-5.6-sol` | `flex` | `-m gpt-5.6-sol` |
| `gpt-6-astra` | `flex` | `-m gpt-6-astra` |

Set the default model and 1M window in `~/.codex/config.toml`:

```toml
model = "gpt-5.6-terra"
service_tier = "default"
model_context_window = 1048576
```

Codex has one global `service_tier` setting. Do not create model profiles for
this convention. A profile only helps when a person explicitly selects that
profile; it cannot switch tiers when `-m` selects a model. The shell wrapper
below supplies the invocation-level override instead.

## Install the wrapper

Replace an existing `alias gpt=...` with this zsh function in `~/.zshrc`. Keep
the existing Codex safety flags if the developer already chose different ones.

```zsh
gpt() {
  local model="" arg expect_model=false tier

  for arg in "$@"; do
    if [[ "$expect_model" == true ]]; then
      model="$arg"
      break
    fi
    case "$arg" in
      -m|--model) expect_model=true ;;
      -m=*) model="${arg#-m=}"; break ;;
      --model=*) model="${arg#--model=}"; break ;;
    esac
  done

  case "$model" in
    ""|gpt-5.6-terra) tier="default" ;;
    gpt-5.6-luna) tier="fast" ;;
    gpt-5.6-sol|gpt-6-astra) tier="flex" ;;
    *) command codex "$@"; return $? ;;
  esac

  command codex -c "service_tier=\"$tier\"" "$@"
}
```

The `-c` override must come before `"$@"`. That keeps an explicit
`-c service_tier=...` supplied by the developer as the final override. Do not
guess a tier for an unknown model.

If the wrapper must retain unrestricted local-agent flags, use the same command
shape in both branches:

```zsh
command codex --dangerously-bypass-approvals-and-sandbox --sandbox danger-full-access -c "service_tier=\"$tier\"" "$@"
```

## Verify and synchronize safely

Start a new shell, then validate syntax and Codex configuration:

```bash
zsh -n ~/.zshrc
zsh -ic 'whence -w gpt; functions gpt'
codex --strict-config doctor --summary
```

For a development sandbox, inspect its shell startup file and
`~/.codex/config.toml` first. Apply the same wrapper and the three config keys
there, then run the same checks over SSH. Do not copy an entire `config.toml`:
it can contain machine-specific MCP endpoints, auth configuration, and secrets.
Do not assume a sandbox hostname or authentication method.

## Give agents this instruction

Tell agents to use `gpt`, not `codex`, and to select a model with `-m`:

```text
Use gpt for Codex work. Leave service_tier alone: the wrapper selects it.
Default to Terra, or select one explicitly with:
gpt -m gpt-5.6-luna "..."
gpt -m gpt-5.6-terra "..."
gpt -m gpt-5.6-sol "..."
gpt -m gpt-6-astra "..."
Do not use Codex profiles (-p) for model selection.
```

Flex pricing requires API-key billing. If Codex warns that `flex` is not
supported for a selected model and omits the tier, report that warning rather
than claiming Flex processing was used.
