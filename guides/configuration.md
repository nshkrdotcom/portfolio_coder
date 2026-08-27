# Configuration Guide

This guide documents configuration for LLM routing, agent sessions, and examples.

## LLM Providers and Routing

`portfolio_coder` routes stateless completions through `PortfolioManager.Router`.
You can configure providers in `config.exs` or via environment variables.

### Environment Variables (Quick Start)

Cloud providers:
- `GEMINI_API_KEY`
- `OPENAI_API_KEY`
- `CODEX_API_KEY` (for Codex LLM adapter)
- `ANTHROPIC_API_KEY`

Local providers:
- `OLLAMA_BASE_URL` or `OLLAMA_HOST`
- `VLLM_ENABLED=1` (or `VLLM_BASE_URL`/`VLLM_URL` if you proxy)

### Router Configuration (optional)

```elixir
config :portfolio_coder, :llm_router,
  strategy: :fallback,
  providers: [
    %{name: :gemini, module: PortfolioIndex.Adapters.LLM.Gemini, config: %{model: "gemini-1.5-flash"}, priority: 1},
    %{name: :anthropic, module: PortfolioIndex.Adapters.LLM.Anthropic, config: %{model: "claude-3-5-sonnet"}, priority: 2},
    %{name: :openai, module: PortfolioIndex.Adapters.LLM.OpenAI, config: %{model: "gpt-4o-mini"}, priority: 3}
  ]
```

You can also control provider order for defaults:

```elixir
config :portfolio_coder, :llm_provider_order, [:gemini, :anthropic, :openai, :codex, :ollama, :vllm]
```

### Graceful Degradation

`PortfolioCoder.LLM` automatically:
- retries transient errors (timeouts, 5xx, 429 rate-limits)
- cools down failing providers (circuit breaker)
- falls back to the next provider

When all providers fail, caller modules return context-only output where possible
(e.g., `mix code.ask` prints retrieved context with an error message).

## Agent Sessions (Claude + Codex)

Agent sessions are configured via `:portfolio_index, :agent_session`:

```elixir
config :portfolio_index, :agent_session,
  store: {AgentSessionManager.Adapters.InMemorySessionStore, []},
  claude: {AgentSessionManager.Adapters.ClaudeAdapter, [model: "claude-3-5-sonnet"]},
  codex: {AgentSessionManager.Adapters.CodexAdapter, [working_directory: "/path/to/repo"]}
```

Notes:
- Codex requires a `working_directory` for file/tool operations.
- Claude can authenticate via `ANTHROPIC_API_KEY` or `claude login`.

`PortfolioCoder.AgentSession.run/2` also accepts per-call overrides:
- `provider: :auto | :claude | :codex`
- `fallback_providers: [:claude, :codex]`
- `working_directory: "/path"`
- `model: "..."`
- `print_events: true`

CLI usage:

```bash
mix code.agent_session "Explain this repo" --provider claude --print-events
mix code.agent_session "Refactor module" --provider codex --working-dir /path/to/repo
```

## Examples and Prerequisites

Run all examples:

```bash
./examples/run_all.sh
```

Examples 03 and 06-15 require an LLM provider. Examples 16-17 require agent sessions.
Examples 18-19 require local LLM services (Ollama or vLLM).

Useful environment variables:

```bash
# Cloud LLMs
export GEMINI_API_KEY=...
export OPENAI_API_KEY=...
export CODEX_API_KEY=...
export ANTHROPIC_API_KEY=...

# Ollama
export OLLAMA_BASE_URL=http://localhost:11434/api
export OLLAMA_MODEL=llama3.2

# vLLM
export VLLM_ENABLED=1
export VLLM_MODEL=Qwen/Qwen2-0.5B-Instruct

# Agent sessions
export CODEX_WORKING_DIR=/path/to/repo
export CODEX_API_KEY=...
```

## RAG Indexing

`PortfolioCoder.Indexer.index_repo/2` delegates to `PortfolioManager.RAG.index_repo/2`.
For explicit file lists, use `PortfolioCoder.Indexer.index_files/2` which enqueues
files through `PortfolioIndex.Pipelines.Ingestion`.
