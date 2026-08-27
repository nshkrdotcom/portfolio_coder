# Indexing and RAG

This guide covers indexing and retrieval‑augmented generation (RAG).

## Indexing a Repo

```bash
mix code.index /path/to/repo --index my_project
```

Internally:
- `PortfolioCoder.Indexer.index_repo/2` delegates to `PortfolioManager.RAG.index_repo/2`.
- `PortfolioManager.RAG` uses `PortfolioIndex.Pipelines.Ingestion` to enqueue files.

## Indexing Specific Files

```elixir
PortfolioCoder.index_files(["/path/to/file.ex"], index_id: "my_project")
```

This uses `PortfolioIndex.Pipelines.Ingestion.enqueue/2` for each file.

## Asking Questions

`PortfolioCoder.Search.ask/2` retrieves context via `PortfolioManager.RAG.query/2`.
If the strategy returns a generated answer, it is returned directly; otherwise
`PortfolioCoder.LLM` generates the answer using the retrieved context.

## Streaming Answers

`PortfolioCoder.Search.stream_ask/3` retrieves context then streams the LLM
response with fallback policy.
