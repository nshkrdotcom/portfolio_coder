# Architecture Overview

This guide explains the layering and ownership model of the Portfolio ecosystem and how
`portfolio_coder` fits into it.

## Layering (who owns what)

```
portfolio_coder (CLI + code intelligence + thin facades)
    |
    v
portfolio_manager (app-level facade: RAG, graph, router)
    |
    v
portfolio_index (adapters + pipelines + query enhancers)
    |
    v
portfolio_core (port/behavior contracts + registry)
    |
    v
agent_session_manager (session store + provider adapters)
    |
    v
Claude/Codex SDKs (provider-specific implementations)
```

### portfolio_coder
- Owns CLI UX, code intelligence tooling, and examples.
- Adds thin facades only for cross‑cutting concerns:
  - `PortfolioCoder.LLM` (routing + graceful degradation + circuit breaker)
  - `PortfolioCoder.AgentSession` (provider selection + fallback for autonomous sessions)
- Delegates core capabilities to `portfolio_manager` and `portfolio_index`.

### portfolio_manager
- Application-level facade for RAG, graph analysis, and stateless LLM routing.
- `PortfolioManager.RAG` is the default entry point for indexing/querying.
- `PortfolioManager.Router` handles provider selection for completions/streaming.

### portfolio_index
- Implements adapters and pipelines used by `portfolio_manager` and `portfolio_coder`.
- Hosts query enhancers and ingestion pipelines (`PortfolioIndex.Pipelines.Ingestion`).
- Provides agent-session adapters that delegate to `agent_session_manager`.

### portfolio_core
- Defines stable port contracts (LLM, AgentSession, vector store, graph store, etc.).
- Keeps the application layers insulated from SDK churn.

### agent_session_manager
- Orchestrates autonomous sessions and persists runs/events.
- Maps provider-specific events into normalized event streams.

## Stateless vs. Autonomous Agent Sessions

**Stateless LLM calls** (RAG answers, summaries, classification):
- Use `PortfolioCoder.LLM` -> `PortfolioManager.Router` -> LLM adapter.
- Adds retry/backoff, circuit breaker, and graceful degradation.

**Autonomous agent sessions** (Claude/Codex):
- Use `PortfolioCoder.AgentSession` -> `PortfolioIndex.Adapters.AgentSession.*`.
- Providers control the tool loop; the app observes events and outputs.
- Fallback occurs by starting a new session on another provider.

## Graceful Degradation

`PortfolioCoder.LLM` classifies errors as fatal vs. transient:
- Fatal: quota exhausted, unauthorized, model not found.
- Transient: 429 rate‑limit, 5xx, timeouts/network.

Behavior:
- Transient errors are retried with backoff.
- Providers are temporarily cooled down via circuit breaker.
- If all providers fail, callers can surface context‑only output.

## Indexing Responsibilities

- `PortfolioCoder.Indexer.index_repo/2` delegates scanning + ingestion to
  `PortfolioManager.RAG.index_repo/2`.
- `PortfolioCoder.Indexer.index_files/2` uses
  `PortfolioIndex.Pipelines.Ingestion.enqueue/2` for explicit file lists.

## Practical Integration Points

- Search/RAG flows: `PortfolioCoder.Search` -> `PortfolioManager.RAG`.
- Graph flows: `PortfolioCoder.Graph.*` -> `PortfolioManager.Graph`.
- Agent sessions: `PortfolioCoder.AgentSession` -> `PortfolioIndex.Adapters.AgentSession.*`.
- Stateless completions: `PortfolioCoder.LLM` -> `PortfolioManager.Router`.

For configuration details, see `guides/configuration.md`.
