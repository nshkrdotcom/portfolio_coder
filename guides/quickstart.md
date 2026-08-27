# Quick Start

This quickstart shows a minimal setup and a few key workflows.

## Install

```elixir
def deps do
  [
    {:portfolio_coder, "~> 0.4.0"}
  ]
end
```

## Index a Repo

```bash
mix code.index /path/to/repo --index my_project
```

## Search

```bash
mix code.search "authentication middleware" --index my_project
```

## Ask (RAG)

```bash
mix code.ask "How does authentication work?" --index my_project
```

## Agent Session (Claude / Codex)

```bash
mix code.agent_session "Explain this repo" --provider claude --print-events
mix code.agent_session "Refactor module" --provider codex --working-dir /path/to/repo
```

## Next Steps

- See `guides/cli.md` for all CLI commands.
- See `guides/configuration.md` for provider and agent-session settings.
- See `guides/examples.md` to run demo scripts.
