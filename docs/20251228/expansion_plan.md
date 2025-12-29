# Portfolio Coder Expansion Plan

## Analysis Date: 2025-12-28

## Executive Summary

This document analyzes the gap between portfolio_coder's current implementation and the capabilities provided by its 3 core dependencies (portfolio_core v0.3.0, portfolio_index v0.3.0, portfolio_manager v0.3.0), identifies unfinished documentation, and proposes a plan for expanding the core feature set.

---

## 1. Dependency Feature Analysis

### 1.1 portfolio_core (v0.3.0) - Hexagonal Architecture Foundation

**Available Ports (16 total):**
| Port | Used in portfolio_coder | Notes |
|------|------------------------|-------|
| VectorStore | Indirectly (via RAG) | Not using fulltext_search, hybrid mode |
| GraphStore | Yes | Using basic CRUD, not using traversal, community ops |
| Embedder | Indirectly (via RAG) | Not exposed directly |
| LLM | Indirectly (via RAG) | Not exposed directly |
| Chunker | Indirectly (via RAG) | Not exposing chunker strategy selection |
| Retriever | Indirectly (via RAG) | Not using capability detection |
| Reranker | **No** | Not using reranking at all |
| Evaluation | **No** | RAG Triad not being used |
| Router | **No** | Multi-provider routing not used |
| Cache | **No** | No caching layer |
| Pipeline | **No** | Not using pipeline orchestration |
| Agent | Partially | Only tool registration, not session API |
| Tool | Yes | 4 tools registered |
| DocumentStore | **No** | Not using pre-chunk storage |

**Key gaps:**
- Evaluation port for RAG quality assessment
- Router for multi-provider LLM fallback
- Cache for performance optimization
- Pipeline for workflow orchestration
- Reranker for result quality improvement

### 1.2 portfolio_index (v0.3.0) - RAG Adapters & Strategies

**Available Features:**

| Feature | Used | Notes |
|---------|------|-------|
| Hybrid RAG Strategy | Via RAG.ask/search | Default strategy |
| Self-RAG Strategy | **Exposed but not used** | Could improve answer quality |
| GraphRAG Strategy | **No** | Entity-based retrieval not used |
| Agentic Strategy | **No** | Tool-based retrieval not used |
| Character Chunker | Indirectly | Via index pipeline |
| Semantic Chunker | **No** | Could improve chunk quality |
| Paragraph Chunker | **No** | Better for documentation |
| LLM Reranker | **No** | Post-retrieval quality |
| Entity Extractor | **No** | GraphRAG prerequisite |
| Community Detector | **No** | GraphRAG global search |
| Community Summarizer | **No** | GraphRAG global search |
| Ingestion Pipeline | Via RAG.index_repo | Basic usage |
| Fulltext Search | **No** | Only semantic search exposed |

**Key gaps:**
- GraphRAG components (entity extraction, communities)
- Advanced chunking strategies selection
- Reranking for search quality
- Self-RAG for improved answers

### 1.3 portfolio_manager (v0.3.0) - Application Layer

**Available Features:**

| Feature | Used | Notes |
|---------|------|-------|
| RAG.query/search/ask | Yes | Core functionality |
| RAG.stream_query | Yes | Streaming support |
| RAG.index_repo | Yes | Indexing |
| Router.execute | **No** | Multi-provider not used |
| Agent.process | **No** | Session-based agent not used |
| Agent.process_with_tools | **No** | Tool-enabled sessions not used |
| Pipeline DSL | **No** | Workflow not used |
| Generation container | **No** | RAG lifecycle tracking not used |
| Evaluation.evaluate_rag_triad | **No** | Quality metrics not used |
| Graph.create_graph | Yes | Basic usage |
| Graph.add_node/edge | Yes | Basic CRUD |
| Graph.neighbors | Yes | Dependency traversal |
| Graph.traverse | **No** | Advanced BFS/DFS not used |

**Key gaps:**
- Router for resilient LLM access
- Session-based agent for multi-turn conversations
- Pipeline for complex code analysis workflows
- Generation tracking for debugging/evaluation

---

## 2. Unfinished Documentation

### 2.1 Current Documentation

| File | Status | Content |
|------|--------|---------|
| README.md | Complete | Overview, installation, quick start, architecture |
| CHANGELOG.md | Complete | v0.1.0 release notes |
| docs/20251228/architecture.md | Complete | Architecture diagram, module descriptions, data flows |

### 2.2 Missing Documentation

| Document | Priority | Description |
|----------|----------|-------------|
| Getting Started Guide | High | Step-by-step tutorial with examples |
| API Reference | High | Full function documentation |
| CLI Reference | High | Detailed CLI usage with examples |
| Configuration Guide | Medium | Manifest config, adapters, strategies |
| Integration Guide | Medium | How to integrate with other apps |
| Development Guide | Medium | Contributing, testing, architecture decisions |
| RAG Strategies Guide | Medium | When to use which strategy |
| Language Parser Guide | Low | How parsers work, adding new languages |
| Troubleshooting Guide | Low | Common issues and solutions |

---

## 3. Implementation Gaps

### 3.1 Stubbed/Incomplete Features

| Feature | Location | Status | Fix Priority |
|---------|----------|--------|--------------|
| Cycle detection | `Graph.Dependency.find_cycles/1` | Stubbed (returns []) | High |
| Text search | `Search.text_search/2` | Delegates to semantic | Medium |
| find_references tool | CHANGELOG claims it exists | Not implemented | Medium |

### 3.2 Missing Tests

Current test files exist but coverage is minimal:
- `portfolio_coder_test.exs` - Only tests `supported_languages/0`
- Integration tests for RAG operations are missing
- No tests for Graph.Dependency beyond basic

---

## 4. Expansion Plan

### Phase 1: Core Feature Completion (Foundation)

**Goal:** Complete stubbed features and fix documentation claims

#### 1.1 Implement Cycle Detection
```elixir
# lib/portfolio_coder/graph/dependency.ex
def find_cycles(graph_id) do
  # Implement Tarjan's SCC algorithm or delegate to Neo4j's algo
  case PMGraph.query(graph_id, "CALL gds.cycles.find(...)") do
    {:ok, cycles} -> {:ok, format_cycles(cycles)}
    err -> err
  end
end
```

#### 1.2 Implement Text Search
```elixir
# lib/portfolio_coder/search.ex
def text_search(query, opts \\ []) do
  index_id = Keyword.get(opts, :index_id, default_index())

  # Use portfolio_index's fulltext search
  case VectorStore.fulltext_search(index_id, query, opts[:limit] || 10) do
    {:ok, results} -> {:ok, format_results(results)}
    err -> err
  end
end
```

#### 1.3 Add find_references Tool
```elixir
# lib/portfolio_coder/tools/find_references.ex
defmodule PortfolioCoder.Tools.FindReferences do
  @behaviour PortfolioCore.Ports.Tool

  def name, do: "find_references"
  def description, do: "Find all references to a symbol in the codebase"
  # ... implementation
end
```

### Phase 2: Advanced RAG Strategies

**Goal:** Expose and leverage advanced retrieval strategies

#### 2.1 Add Strategy Selection to Search

```elixir
# lib/portfolio_coder/search.ex
@spec search_code(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
def search_code(query, opts \\ []) do
  strategy = Keyword.get(opts, :strategy, :hybrid)

  rag_opts = Keyword.merge(opts, [
    strategy: strategy,
    index_id: Keyword.get(opts, :index_id, default_index())
  ])

  case RAG.query(query, rag_opts) do
    {:ok, result} -> {:ok, format_results(result.items)}
    err -> err
  end
end
```

#### 2.2 Add Self-RAG Support

```elixir
# lib/portfolio_coder/search.ex
def ask_with_critique(question, opts \\ []) do
  RAG.query(question, Keyword.put(opts, :strategy, :self_rag))
end
```

#### 2.3 Add Reranking Option

```elixir
# lib/portfolio_coder/search.ex
def search_code(query, opts \\ []) do
  with {:ok, results} <- do_search(query, opts),
       {:ok, reranked} <- maybe_rerank(results, query, opts) do
    {:ok, reranked}
  end
end

defp maybe_rerank(results, query, opts) do
  if Keyword.get(opts, :rerank, false) do
    Reranker.rerank(results, query, opts)
  else
    {:ok, results}
  end
end
```

### Phase 3: GraphRAG Integration

**Goal:** Enable entity-based code understanding

#### 3.1 Code Entity Extraction

```elixir
# lib/portfolio_coder/graph/entities.ex
defmodule PortfolioCoder.Graph.Entities do
  @moduledoc """
  Extract and store code entities for GraphRAG.
  """

  alias PortfolioIndex.GraphRAG.EntityExtractor

  def extract_from_repo(repo_path, graph_id, opts \\ []) do
    files = PortfolioCoder.Indexer.scan_files(repo_path, opts[:languages], opts[:exclude])

    Enum.each(files, fn file ->
      content = File.read!(file.path)
      parsed = PortfolioCoder.Parsers.parse(content, file.type)

      # Extract entities (modules, functions, classes)
      entities = parsed_to_entities(parsed, file)

      # Store in graph
      store_entities(graph_id, entities)
    end)
  end

  defp parsed_to_entities(parsed, file) do
    # Convert parser output to GraphRAG entities
    # modules -> entities with type: "module"
    # functions -> entities with type: "function"
    # relationships: calls, imports, defines
  end
end
```

#### 3.2 Code Community Detection

```elixir
# lib/portfolio_coder/graph/communities.ex
defmodule PortfolioCoder.Graph.Communities do
  @moduledoc """
  Detect logical groupings in code for global search.
  """

  alias PortfolioIndex.GraphRAG.CommunityDetector
  alias PortfolioIndex.GraphRAG.CommunitySummarizer

  def build_communities(graph_id, opts \\ []) do
    with {:ok, communities} <- CommunityDetector.detect(graph_store(), graph_id, opts),
         {:ok, summaries} <- summarize_communities(communities, graph_id, opts) do
      {:ok, summaries}
    end
  end

  defp summarize_communities(communities, graph_id, opts) do
    # Summarize each community with code-aware prompts
    Enum.map(communities, fn {id, members} ->
      CommunitySummarizer.summarize(%{id: id, members: members}, graph_store(), graph_id, opts)
    end)
  end
end
```

#### 3.3 GraphRAG Search Mode

```elixir
# lib/portfolio_coder/search.ex
def search_with_graph(query, opts \\ []) do
  mode = Keyword.get(opts, :graph_mode, :local)  # :local, :global, :hybrid

  RAG.query(query, Keyword.merge(opts, [
    strategy: :graph_rag,
    mode: mode
  ]))
end
```

### Phase 4: Multi-Provider Routing

**Goal:** Resilient LLM access with fallback

#### 4.1 Router Integration

```elixir
# lib/portfolio_coder/llm.ex
defmodule PortfolioCoder.LLM do
  @moduledoc """
  LLM access with multi-provider routing.
  """

  alias PortfolioManager.Router

  def generate(prompt, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :fallback)
    task_type = Keyword.get(opts, :task_type, :code)

    messages = [%{role: :user, content: prompt}]

    Router.execute(messages, strategy: strategy, task_type: task_type)
  end

  def generate_with_context(question, context, opts \\ []) do
    system_prompt = """
    You are a code analysis assistant. Use the following code context to answer the question.

    Context:
    #{context}
    """

    messages = [
      %{role: :system, content: system_prompt},
      %{role: :user, content: question}
    ]

    Router.execute(messages, opts)
  end
end
```

### Phase 5: Pipeline Workflows

**Goal:** Complex multi-step code analysis

#### 5.1 Code Review Pipeline

```elixir
# lib/portfolio_coder/pipelines/code_review.ex
defmodule PortfolioCoder.Pipelines.CodeReview do
  use PortfolioManager.Pipeline

  def run(file_path, opts \\ []) do
    run(:code_review, %{file_path: file_path, opts: opts}) do
      step :read_file, &read_file/1
      step :parse_structure, &parse_structure/1, depends_on: [:read_file]
      step :find_related, &find_related/1, depends_on: [:parse_structure]
      step :analyze_quality, &analyze_quality/1, depends_on: [:parse_structure, :find_related]
      step :generate_report, &generate_report/1, depends_on: [:analyze_quality]
    end
  end

  defp read_file(ctx), do: File.read(ctx.file_path)
  defp parse_structure(ctx), do: Parsers.parse(ctx.read_file, detect_language(ctx.file_path))
  # ... etc
end
```

#### 5.2 Impact Analysis Pipeline

```elixir
# lib/portfolio_coder/pipelines/impact_analysis.ex
defmodule PortfolioCoder.Pipelines.ImpactAnalysis do
  use PortfolioManager.Pipeline

  def analyze(symbol, graph_id, opts \\ []) do
    run(:impact_analysis, %{symbol: symbol, graph_id: graph_id}) do
      step :find_dependents, &find_all_dependents/1
      step :classify_impact, &classify_impact/1, depends_on: [:find_dependents]
      step :estimate_risk, &estimate_risk/1, depends_on: [:classify_impact], parallel: true
      step :suggest_tests, &suggest_tests/1, depends_on: [:classify_impact], parallel: true
      step :compile_report, &compile_report/1, depends_on: [:estimate_risk, :suggest_tests]
    end
  end
end
```

### Phase 6: Agent Sessions & Tools

**Goal:** Multi-turn code conversations

#### 6.1 Code Assistant Agent

```elixir
# lib/portfolio_coder/agent.ex
defmodule PortfolioCoder.Agent do
  @moduledoc """
  Session-based code assistant using PortfolioManager.Agent.
  """

  alias PortfolioManager.Agent
  alias PortfolioManager.Agent.Session

  def new_session(opts \\ []) do
    context = %{
      index_id: Keyword.get(opts, :index_id, "default"),
      repo_path: opts[:repo_path]
    }

    Session.new(context: context, metadata: opts[:metadata] || %{})
  end

  def chat(session, message) do
    Agent.process(session, message)
  end

  def chat_with_tools(session, message, tools \\ nil) do
    tools = tools || [:search_code, :read_file, :analyze_code, :list_files]
    Agent.process_with_tools(session, message, tools)
  end
end
```

#### 6.2 CLI Interactive Mode

```elixir
# lib/mix/tasks/code.chat.ex
defmodule Mix.Tasks.Code.Chat do
  use Mix.Task

  @shortdoc "Interactive code chat session"

  def run(args) do
    # Parse args for --index, --repo
    session = PortfolioCoder.Agent.new_session(opts)

    IO.puts("Code Assistant ready. Type 'exit' to quit.\n")
    chat_loop(session)
  end

  defp chat_loop(session) do
    input = IO.gets("> ") |> String.trim()

    case input do
      "exit" -> IO.puts("Goodbye!")
      _ ->
        {:ok, response, new_session} = PortfolioCoder.Agent.chat_with_tools(session, input)
        IO.puts("\n#{response}\n")
        chat_loop(new_session)
    end
  end
end
```

### Phase 7: Quality & Evaluation

**Goal:** RAG quality metrics and improvement

#### 7.1 Answer Evaluation

```elixir
# lib/portfolio_coder/evaluation.ex
defmodule PortfolioCoder.Evaluation do
  alias PortfolioManager.Evaluation
  alias PortfolioManager.Generation

  def evaluate_answer(question, answer, context) do
    generation = Generation.new(question)
      |> Generation.with_context(context, [])
      |> Generation.with_response(answer)

    Evaluation.evaluate_rag_triad(generation)
  end

  def detect_hallucination(answer, context) do
    generation = Generation.new("")
      |> Generation.with_context(context, [])
      |> Generation.with_response(answer)

    Evaluation.detect_hallucination(generation)
  end
end
```

#### 7.2 CLI Evaluation Mode

```bash
mix code.ask "How does auth work?" --index my_project --evaluate
# Output includes:
# Answer: ...
# Evaluation:
#   Context Relevance: 4/5
#   Groundedness: 5/5
#   Answer Relevance: 4/5
#   Overall: 4.33/5
```

---

## 5. Documentation Plan

### 5.1 High Priority Documentation

#### Getting Started Guide (`docs/getting_started.md`)
- Prerequisites (Elixir, PostgreSQL, Neo4j)
- Installation steps
- Quick indexing tutorial
- First search and Q&A

#### API Reference (`docs/api_reference.md`)
- All public functions with examples
- Type specifications
- Configuration options

#### CLI Reference (`docs/cli_reference.md`)
- All mix tasks with full options
- Examples for each command
- Common workflows

### 5.2 Medium Priority Documentation

#### Configuration Guide (`docs/configuration.md`)
- Manifest setup
- Adapter selection
- Environment variables

#### RAG Strategies Guide (`docs/rag_strategies.md`)
- When to use hybrid vs self-rag vs graph-rag
- Performance characteristics
- Code examples

### 5.3 Low Priority Documentation

#### Language Parser Guide (`docs/parsers.md`)
#### Troubleshooting Guide (`docs/troubleshooting.md`)

---

## 6. Priority Matrix

| Feature | Impact | Effort | Priority |
|---------|--------|--------|----------|
| Cycle detection | Medium | Low | P1 |
| Text search | Medium | Low | P1 |
| find_references tool | Low | Low | P1 |
| Getting Started docs | High | Medium | P1 |
| Self-RAG exposure | Medium | Low | P2 |
| Reranking option | Medium | Medium | P2 |
| API Reference docs | High | Medium | P2 |
| GraphRAG entities | High | High | P3 |
| GraphRAG communities | High | High | P3 |
| Multi-provider router | Medium | Medium | P3 |
| Pipeline workflows | High | High | P4 |
| Agent sessions | High | Medium | P4 |
| Evaluation metrics | Medium | Medium | P4 |

---

## 7. Version Roadmap

### v0.2.0 - Foundation Complete
- Implement cycle detection
- Implement text search
- Add find_references tool
- Complete Getting Started guide
- Add CLI Reference

### v0.3.0 - Advanced Retrieval
- Self-RAG strategy exposure
- Reranking option
- Strategy selection in search
- RAG Strategies guide

### v0.4.0 - GraphRAG
- Code entity extraction
- Community detection
- GraphRAG search mode
- Configuration guide

### v0.5.0 - Resilience & Workflows
- Multi-provider routing
- Code review pipeline
- Impact analysis pipeline

### v0.6.0 - Agent & Evaluation
- Session-based agent
- Interactive chat CLI
- RAG Triad evaluation
- Hallucination detection

---

## 8. Next Steps

1. **Immediate** (This session):
   - Create skeleton for missing docs
   - Implement cycle detection
   - Fix text_search

2. **Short-term** (Next few days):
   - Complete P1 items
   - Add integration tests

3. **Medium-term** (Next week):
   - Complete P2 items
   - GraphRAG groundwork

4. **Long-term**:
   - Full GraphRAG
   - Agent sessions
   - Pipeline workflows
