# Agent Sessions (Claude + Codex)

Agent sessions are stateful and provider‑controlled. They are separate from
stateless LLM completions.

## Port Contract

Agent sessions implement `PortfolioCore.Ports.AgentSession`. The adapters live
in `portfolio_index` and delegate to `agent_session_manager`.

- `PortfolioIndex.Adapters.AgentSession.Claude`
- `PortfolioIndex.Adapters.AgentSession.Codex`

## Why Not Use Agent Sessions for Basic Completions?

Agent sessions are a different product surface:
- They maintain state across turns
- They emit structured events
- They can run tools (file ops, bash, etc.)

For single‑shot completions, use the LLM port instead (`PortfolioCoder.LLM`).

## Running Sessions

Programmatic:

```elixir
{:ok, result} = PortfolioCoder.agent_session("Summarize this repo", provider: :claude)
```

CLI:

```bash
mix code.agent_session "Refactor module" --provider codex --working-dir /path/to/repo
```

## Fallback Policy

`PortfolioCoder.AgentSession` will:
- try the preferred provider
- retry transient errors
- start a new session with the next provider on failure

## Required Inputs

- Codex requires `working_directory`.
- Claude can authenticate via `ANTHROPIC_API_KEY` or `claude login`.

See `guides/configuration.md` for full configuration options.
