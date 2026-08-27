# Portfolio Coder Examples

This directory contains working examples that operate on real data from your portfolio.

## Prerequisites

1. Ensure you have a portfolio repository set up at `~/p/g/n/portfolio` (or set `PORTFOLIO_DIR`)
2. The portfolio should have:
   - `config.yml` with scan directories configured
   - `registry.yml` for tracked repos
   - `relationships.yml` for repo relationships
3. Examples 03 and 06-15 require an LLM provider configured:
   - Cloud: `GEMINI_API_KEY`, `OPENAI_API_KEY`, or `ANTHROPIC_API_KEY`
   - Codex LLM: `CODEX_API_KEY` (optional alternative to OpenAI adapter)
   - Local: `OLLAMA_BASE_URL`/`OLLAMA_HOST`, or `VLLM_ENABLED`/`VLLM_BASE_URL`
4. Examples 16-17 require agent-session providers:
   - Claude: `ANTHROPIC_API_KEY` (or `ALLOW_CLAUDE_SESSION=1` with `claude login`)
   - Codex: `OPENAI_API_KEY` or `CODEX_API_KEY` and `CODEX_WORKING_DIR`
5. Examples 18-19 require local LLM services (Ollama / vLLM)

## Running Examples

Run individual examples with `mix run`:

```bash
mix run examples/01_indexing_demo.exs
```

Run all numbered examples (01-19) with the helper script:

```bash
./examples/run_all.sh          # run all 19
./examples/run_all.sh 1 5      # run 01 through 05 only
./examples/run_all.sh 6 15     # run 06 through 15 only
```

## Code Intelligence Examples (No External Services)

| # | File | Description |
|---|------|-------------|
| 01 | `01_indexing_demo.exs` | Code parsing and chunking pipeline |
| 02 | `02_search_demo.exs` | In-memory code search with TF-IDF scoring |
| 04 | `04_graph_build_demo.exs` | Build a code graph from parsed files |
| 05 | `05_dependency_analysis_demo.exs` | Code-level dependency analysis |

## Code Intelligence Examples (Require LLM Provider)

| # | File | Description |
|---|------|-------------|
| 03 | `03_query_enhancement_demo.exs` | Query rewriting, expansion, and decomposition |
| 06 | `06_rag_hybrid_demo.exs` | RAG with hybrid search + LLM |
| 07 | `07_rag_graph_demo.exs` | Graph-augmented RAG |
| 08 | `08_rag_self_demo.exs` | Self-RAG with reflection |
| 09 | `09_agent_basic_demo.exs` | Basic code agent with tools |
| 10 | `10_agent_debug_demo.exs` | Debug agent for code analysis |
| 11 | `11_router_demo.exs` | Multi-provider LLM routing |
| 12 | `12_pipeline_demo.exs` | Complete code indexing pipeline |
| 13 | `13_evaluation_demo.exs` | RAG evaluation metrics |
| 14 | `14_telemetry_demo.exs` | Telemetry collection demo |
| 15 | `15_full_demo.exs` | Complete end-to-end demo |

## Agent Session Examples

| # | File | Description |
|---|------|-------------|
| 16 | `16_agent_session_claude_demo.exs` | Claude autonomous agent session |
| 17 | `17_agent_session_codex_demo.exs` | Codex autonomous agent session |

## Local LLM Examples

| # | File | Description |
|---|------|-------------|
| 18 | `18_llm_ollama_demo.exs` | Ollama adapter demo |
| 19 | `19_llm_vllm_demo.exs` | vLLM adapter demo |

## Portfolio Management Examples

| File | Description |
|------|-------------|
| `scan_repos.exs` | Scan directories for repositories |
| `show_portfolio_status.exs` | Display portfolio status report |
| `list_by_language.exs` | List repos by language |
| `find_stale_repos.exs` | Find stale/blocked repos |
| `sync_all_repos.exs` | Sync computed fields |
| `analyze_dependencies.exs` | Analyze relationships |

## Configuration

Examples use the default portfolio path `~/p/g/n/portfolio`. Override with:

```bash
PORTFOLIO_DIR=~/my/portfolio mix run examples/scan_repos.exs
```

## Notes

- Examples read from your real portfolio data
- Some examples may modify files (sync operations update context.yml)
- Always backup important data before running modification examples
