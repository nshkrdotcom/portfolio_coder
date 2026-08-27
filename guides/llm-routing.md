# LLM Routing and Graceful Degradation

This guide explains stateless LLM routing, fallback, and error handling.

## Routing Authority

`PortfolioCoder.LLM` delegates provider selection to `PortfolioManager.Router` when
available, then applies retry/backoff and circuit breaker policy.

## Error Classification

`PortfolioCoder.LLM` classifies errors as:

- **Fatal**: insufficient quota, unauthorized, model not found
- **Transient**: rate limit (429), 5xx, network timeouts

Transient errors are retried with backoff. Fatal errors immediately fall back.

## Circuit Breaker

A lightweight ETS-based circuit breaker tracks failures per provider and cools
providers down for a TTL to avoid repeated failures.

Configure via `:circuit_breaker` options:

```elixir
LLM.complete(messages,
  circuit_breaker: [
    failure_threshold: 2,
    transient_cooldown_ms: 60_000,
    fatal_cooldown_ms: 900_000
  ]
)
```

## Context-Only Degradation

When all providers fail, callers can return context-only output. Example:
`mix code.ask` prints the retrieved context and an actionable error message.

## Provider Ordering

Default provider order is configurable:

```elixir
config :portfolio_coder, :llm_provider_order, [:gemini, :anthropic, :openai, :codex, :ollama, :vllm]
```

For explicit routing profiles, use `:llm_router` configuration (see
`guides/configuration.md`).
