# Integration Principles

This guide explains when to add facades and when to rely on upstream modules.

## Do Not Wrap Everything

Avoid creating full API mirrors for upstream modules. Instead:
- document dependency‑driven behavior in ExDoc guides
- reference upstream modules directly in docs
- treat `portfolio_core` ports as the stable contract

## Add Thin Facades Only When They Add Value

Legitimate reasons:
- centralized fallback/graceful‑degradation policy
- consistent config resolution + sane defaults for CLI
- consistent error normalization + user‑facing messages
- security/sandbox enforcement (paths, working dir, tool permissions)

In `portfolio_coder`, the thin‑facade pattern is:
- `PortfolioCoder.Search`
- `PortfolioCoder.Indexer`
- `PortfolioCoder.LLM`
- `PortfolioCoder.AgentSession`

## Port‑First Mental Model

Treat `portfolio_core` behaviours as the durable contract and rely on
`portfolio_index` adapters via config or manifest. This allows new providers
or pipelines to be introduced without changing `portfolio_coder`.

## When to Contribute Upstream

If you find repeated glue logic in multiple repos, consider adding a
shared resolver or middleware in `portfolio_manager` or `portfolio_core`:
- provider registries
- adapter discovery
- standardized error classification
