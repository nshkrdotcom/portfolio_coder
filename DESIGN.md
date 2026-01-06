# Portfolio Coder: Code Intelligence Engine Design

A comprehensive design leveraging all capabilities from portfolio_core, portfolio_index, and portfolio_manager to build a powerful code intelligence platform for your ecosystem.

---

## Executive Summary

This design transforms portfolio_coder from a simple portfolio manager into a full **Code Intelligence Engine** that:

1. **Indexes** your entire codebase with semantic understanding
2. **Builds** knowledge graphs of code relationships
3. **Answers** questions about your code using RAG
4. **Navigates** dependencies across repositories
5. **Generates** code with full context awareness
6. **Reviews** code quality and suggests improvements
7. **Documents** codebases automatically

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PORTFOLIO CODER v1.0                                 │
│                     Code Intelligence Engine                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Indexer   │  │   Search    │  │    Agent    │  │   Review    │        │
│  │   Service   │  │   Service   │  │   Service   │  │   Service   │        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
│         │                │                │                │                │
│  ┌──────┴────────────────┴────────────────┴────────────────┴──────┐        │
│  │                    Code Intelligence Core                       │        │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌────────────┐   │        │
│  │  │ AST Parser │ │ Dependency │ │ Semantic   │ │ Doc        │   │        │
│  │  │ (multi-    │ │ Analyzer   │ │ Chunker    │ │ Generator  │   │        │
│  │  │ language)  │ │            │ │            │ │            │   │        │
│  │  └────────────┘ └────────────┘ └────────────┘ └────────────┘   │        │
│  └────────────────────────────────────────────────────────────────┘        │
│                                    │                                        │
├────────────────────────────────────┼────────────────────────────────────────┤
│                        PORTFOLIO MANAGER                                    │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐          │
│  │   RAG   │  │  Router │  │  Agent  │  │Pipeline │  │  Graph  │          │
│  │ (query, │  │(multi-  │  │(tools,  │  │  (DAG   │  │(deps,   │          │
│  │  ask)   │  │provider)│  │sessions)│  │  exec)  │  │traversal│          │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘          │
├─────────────────────────────────────────────────────────────────────────────┤
│                         PORTFOLIO INDEX                                     │
│  ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐      │
│  │    ADAPTERS       │  │   RAG STRATEGIES  │  │    PIPELINES      │      │
│  │ • Embedder:       │  │ • Hybrid          │  │ • Ingestion       │      │
│  │   OpenAI/Gemini/  │  │ • SelfRAG         │  │ • Embedding       │      │
│  │   Bumblebee       │  │ • GraphRAG        │  │                   │      │
│  │ • LLM: Claude/    │  │ • Agentic         │  │                   │      │
│  │   GPT/Gemini      │  │                   │  │                   │      │
│  │ • VectorStore:    │  │                   │  │                   │      │
│  │   Pgvector/Memory │  │                   │  │                   │      │
│  │ • GraphStore:Neo4j│  │                   │  │                   │      │
│  │ • Chunker:        │  │                   │  │                   │      │
│  │   Recursive/      │  │                   │  │                   │      │
│  │   Semantic        │  │                   │  │                   │      │
│  │ • Reranker: LLM   │  │                   │  │                   │      │
│  └───────────────────┘  └───────────────────┘  └───────────────────┘      │
├─────────────────────────────────────────────────────────────────────────────┤
│                          PORTFOLIO CORE                                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│  │   21 Port   │  │  Registry   │  │  Manifest   │  │  Telemetry  │       │
│  │  Behaviors  │  │   (ETS)     │  │   Engine    │  │   Events    │       │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Feature Categories

### 1. CODE INDEXING SERVICE

**Purpose**: Transform raw code into searchable, semantically-rich representations.

#### 1.1 Multi-Language AST Parsing

```elixir
defmodule PortfolioCoder.Indexer.Parser do
  @moduledoc """
  Multi-language AST parsing using Sourceror (Elixir) and Tree-sitter (others).
  Extracts: modules, functions, classes, methods, imports, exports.
  """

  # Adapters Used:
  # - PortfolioIndex.Adapters.Chunker.Recursive (format-aware splitting)
  # - PortfolioCore.Ports.Chunker (behavior)

  @spec parse(path :: String.t(), language :: atom()) :: {:ok, ast_result()} | {:error, term()}
  def parse(path, language)

  @spec extract_symbols(ast :: term()) :: [symbol()]
  def extract_symbols(ast)

  @spec extract_references(ast :: term()) :: [reference()]
  def extract_references(ast)
end
```

**Symbols Extracted**:
- **Elixir**: modules, functions, macros, typespecs, protocols, behaviours
- **Python**: classes, functions, methods, imports, decorators
- **JavaScript/TypeScript**: classes, functions, exports, imports, types
- **Rust**: structs, traits, impls, functions, mods
- **Go**: packages, structs, interfaces, functions

#### 1.2 Semantic Chunking for Code

```elixir
defmodule PortfolioCoder.Indexer.CodeChunker do
  @moduledoc """
  Code-aware chunking that preserves semantic boundaries.
  """

  # Adapters Used:
  # - PortfolioIndex.Adapters.Chunker.Semantic (embedding-based boundaries)
  # - PortfolioIndex.Adapters.Chunker.Recursive (format-aware fallback)
  # - PortfolioIndex.Adapters.Embedder.* (for semantic similarity)

  @type chunk_strategy :: :function | :class | :module | :semantic | :hybrid

  @spec chunk_file(path :: String.t(), opts :: keyword()) :: {:ok, [code_chunk()]}
  def chunk_file(path, opts \\ [])

  @spec chunk_by_symbol(content :: String.t(), symbols :: [symbol()]) :: [code_chunk()]
  def chunk_by_symbol(content, symbols)
end
```

**Chunking Strategies**:
| Strategy | Best For | Adapter |
|----------|----------|---------|
| `:function` | Small functions, method-level search | Recursive with custom separators |
| `:class` | OOP codebases, class-level context | Recursive with class markers |
| `:module` | Elixir/Erlang, module-level understanding | Recursive with defmodule |
| `:semantic` | Finding conceptually related code | Semantic chunker + embedder |
| `:hybrid` | Best of both - structure + semantics | Recursive → Semantic merge |

#### 1.3 Code Embedding Pipeline

```elixir
defmodule PortfolioCoder.Indexer.Pipeline do
  @moduledoc """
  Broadway-based pipeline for indexing repositories at scale.
  """

  # Adapters Used:
  # - PortfolioIndex.Pipelines.Ingestion (Broadway file discovery)
  # - PortfolioIndex.Pipelines.Embedding (rate-limited embedding)
  # - PortfolioIndex.Adapters.Embedder.* (vector generation)
  # - PortfolioIndex.Adapters.VectorStore.Pgvector (storage)
  # - PortfolioIndex.Adapters.DocumentStore.Postgres (chunk storage)

  @spec index_repo(repo_id :: String.t(), opts :: keyword()) :: {:ok, stats()} | {:error, term()}
  def index_repo(repo_id, opts \\ [])

  @spec index_file(repo_id :: String.t(), path :: String.t()) :: :ok | {:error, term()}
  def index_file(repo_id, path)

  @spec reindex_changed(repo_id :: String.t()) :: {:ok, stats()}
  def reindex_changed(repo_id)
end
```

**Pipeline Configuration**:
```elixir
config :portfolio_coder, PortfolioCoder.Indexer.Pipeline,
  # File discovery
  patterns: ["**/*.ex", "**/*.exs", "**/*.py", "**/*.js", "**/*.ts"],
  exclude: ["**/node_modules/**", "**/deps/**", "**/_build/**"],

  # Chunking
  chunk_strategy: :hybrid,
  chunk_size: 1500,        # ~375 tokens
  chunk_overlap: 200,

  # Embedding
  embedder: :openai,        # or :gemini, :bumblebee
  embedding_model: "text-embedding-3-small",
  batch_size: 100,
  rate_limit: {1000, :minute},

  # Storage
  vector_store: :pgvector,
  document_store: :postgres,

  # Concurrency
  concurrency: 10,
  max_demand: 50
```

#### 1.4 Incremental Indexing

```elixir
defmodule PortfolioCoder.Indexer.Incremental do
  @moduledoc """
  Track file changes and reindex only modified content.
  Uses content hashing to detect changes.
  """

  # Adapters Used:
  # - PortfolioIndex.Adapters.DocumentStore.Postgres (content hash storage)
  # - PortfolioIndex.Adapters.VectorStore.Pgvector.SoftDelete (vector updates)

  @spec detect_changes(repo_id :: String.t()) :: {:ok, changeset()}
  def detect_changes(repo_id)

  @spec apply_changes(repo_id :: String.t(), changeset()) :: {:ok, stats()}
  def apply_changes(repo_id, changeset)
end
```

---

### 2. CODE SEARCH SERVICE

**Purpose**: Find relevant code using semantic understanding, not just keywords.

#### 2.1 Hybrid Code Search

```elixir
defmodule PortfolioCoder.Search do
  @moduledoc """
  Semantic + keyword search across indexed codebases.
  """

  # Adapters Used:
  # - PortfolioIndex.RAG.Strategies.Hybrid (combined search)
  # - PortfolioIndex.Adapters.VectorStore.Pgvector (semantic)
  # - PortfolioIndex.Adapters.VectorStore.Pgvector.Fulltext (keyword)
  # - PortfolioIndex.Adapters.Embedder.* (query embedding)
  # - PortfolioIndex.Adapters.Reranker.LLM (result quality)

  @type search_mode :: :semantic | :keyword | :hybrid

  @spec search(query :: String.t(), opts :: keyword()) :: {:ok, [result()]}
  def search(query, opts \\ [])

  @spec search_in_repo(query :: String.t(), repo_id :: String.t(), opts :: keyword()) :: {:ok, [result()]}
  def search_in_repo(query, repo_id, opts \\ [])

  @spec search_by_symbol(symbol_name :: String.t(), opts :: keyword()) :: {:ok, [result()]}
  def search_by_symbol(symbol_name, opts \\ [])

  @spec find_similar(code_snippet :: String.t(), opts :: keyword()) :: {:ok, [result()]}
  def find_similar(code_snippet, opts \\ [])
end
```

**Search Options**:
```elixir
search("handle authentication",
  mode: :hybrid,           # :semantic | :keyword | :hybrid
  repos: ["app1", "app2"], # scope to repos
  languages: [:elixir],    # filter by language
  file_patterns: ["**/controllers/**"],
  k: 20,                   # results before reranking
  rerank: true,            # LLM reranking
  top_n: 5,                # final results
  min_score: 0.7           # score threshold
)
```

#### 2.2 Query Enhancement

```elixir
defmodule PortfolioCoder.Search.QueryEnhancer do
  @moduledoc """
  Improve search queries for better code retrieval.
  """

  # Adapters Used:
  # - PortfolioIndex.Adapters.QueryRewriter.LLM (clean up query)
  # - PortfolioIndex.Adapters.QueryExpander.LLM (add synonyms)
  # - PortfolioIndex.Adapters.QueryDecomposer.LLM (break down complex queries)

  @spec enhance(query :: String.t(), opts :: keyword()) :: enhanced_query()
  def enhance(query, opts \\ [])

  @spec rewrite_for_code(query :: String.t()) :: String.t()
  def rewrite_for_code(query)

  @spec expand_with_synonyms(query :: String.t()) :: String.t()
  def expand_with_synonyms(query)

  @spec decompose_complex(query :: String.t()) :: [String.t()]
  def decompose_complex(query)
end
```

**Query Enhancement Pipeline**:
```
User Query: "how do we handle user login?"
     │
     ├─→ Rewrite: "user login authentication handler"
     │
     ├─→ Expand: "user login authentication handler sign-in session auth"
     │
     └─→ Decompose (if complex):
           1. "user authentication implementation"
           2. "login session management"
           3. "password validation"
```

#### 2.3 Collection-Aware Search

```elixir
defmodule PortfolioCoder.Search.CollectionRouter do
  @moduledoc """
  Route queries to relevant code collections.
  """

  # Adapters Used:
  # - PortfolioIndex.Adapters.CollectionSelector.LLM (intelligent routing)
  # - PortfolioIndex.Adapters.CollectionSelector.RuleBased (fast routing)

  @spec route(query :: String.t(), available :: [collection()]) :: [collection()]
  def route(query, available)
end
```

**Collections**:
- Per-repository indexes
- Per-language indexes
- Domain-specific indexes (auth, payments, etc.)
- Documentation vs code indexes

---

### 3. KNOWLEDGE GRAPH SERVICE

**Purpose**: Build and query a graph of code relationships.

#### 3.1 Code Knowledge Graph

```elixir
defmodule PortfolioCoder.Graph.CodeGraph do
  @moduledoc """
  Knowledge graph of code entities and relationships.
  """

  # Adapters Used:
  # - PortfolioIndex.Adapters.GraphStore.Neo4j (graph storage)
  # - PortfolioIndex.GraphRAG.EntityExtractor (entity extraction)
  # - PortfolioIndex.GraphRAG.CommunityDetector (clustering)
  # - PortfolioIndex.GraphRAG.CommunitySummarizer (summaries)
  # - PortfolioManager.Graph (interface)

  @type node_type :: :module | :function | :class | :method | :file | :repo | :concept
  @type edge_type :: :calls | :imports | :defines | :inherits | :implements | :depends_on

  @spec build_from_repo(repo_id :: String.t(), opts :: keyword()) :: {:ok, stats()}
  def build_from_repo(repo_id, opts \\ [])

  @spec add_entity(graph_id :: String.t(), entity :: entity()) :: :ok
  def add_entity(graph_id, entity)

  @spec add_relationship(graph_id :: String.t(), rel :: relationship()) :: :ok
  def add_relationship(graph_id, rel)

  @spec query(graph_id :: String.t(), cypher :: String.t()) :: {:ok, [result()]}
  def query(graph_id, cypher)
end
```

**Node Types**:
```
(:Repo)-[:CONTAINS]->(:File)-[:DEFINES]->(:Module)-[:DEFINES]->(:Function)
                                              │
                                              └─[:IMPLEMENTS]->(:Behaviour)
                                              └─[:USES]->(:Protocol)

(:Function)-[:CALLS]->(:Function)
(:Module)-[:IMPORTS]->(:Module)
(:Class)-[:INHERITS]->(:Class)
(:Package)-[:DEPENDS_ON]->(:Package)
```

#### 3.2 Dependency Graph

```elixir
defmodule PortfolioCoder.Graph.Dependencies do
  @moduledoc """
  Cross-repository dependency analysis.
  """

  # Adapters Used:
  # - PortfolioManager.Graph (graph interface)
  # - PortfolioIndex.Adapters.GraphStore.Neo4j (storage)
  # - PortfolioIndex.Adapters.GraphStore.Neo4j.Traversal (path finding)

  @spec build_dependency_graph(repos :: [String.t()]) :: {:ok, graph_id()}
  def build_dependency_graph(repos)

  @spec get_dependents(package :: String.t()) :: {:ok, [package()]}
  def get_dependents(package)

  @spec get_dependencies(package :: String.t()) :: {:ok, [package()]}
  def get_dependencies(package)

  @spec impact_analysis(package :: String.t()) :: {:ok, impact_report()}
  def impact_analysis(package)

  @spec find_path(from :: String.t(), to :: String.t()) :: {:ok, [path()]}
  def find_path(from, to)

  @spec detect_cycles() :: {:ok, [cycle()]}
  def detect_cycles()
end
```

**Dependency Analysis Features**:
- **Impact Analysis**: "If I change portfolio_core, what breaks?"
- **Cycle Detection**: Find circular dependencies
- **Unused Dependencies**: Find deps that aren't actually used
- **Version Conflicts**: Detect version mismatches across repos
- **Upgrade Planning**: Safe upgrade order based on dependency tree

#### 3.3 Call Graph

```elixir
defmodule PortfolioCoder.Graph.CallGraph do
  @moduledoc """
  Function-level call relationships.
  """

  # Adapters Used:
  # - PortfolioIndex.Adapters.GraphStore.Neo4j (storage)
  # - PortfolioIndex.Adapters.GraphStore.Neo4j.EntitySearch (search)
  # - PortfolioIndex.Adapters.GraphStore.Neo4j.Traversal (traversal)

  @spec build_call_graph(repo_id :: String.t()) :: {:ok, graph_id()}
  def build_call_graph(repo_id)

  @spec callers(function :: mfa()) :: {:ok, [mfa()]}
  def callers(function)

  @spec callees(function :: mfa()) :: {:ok, [mfa()]}
  def callees(function)

  @spec call_chain(from :: mfa(), to :: mfa()) :: {:ok, [path()]}
  def call_chain(from, to)

  @spec hot_paths() :: {:ok, [path()]}
  def hot_paths()
end
```

---

### 4. CODE Q&A SERVICE (RAG)

**Purpose**: Answer questions about your codebase using retrieval-augmented generation.

#### 4.1 Code Question Answering

```elixir
defmodule PortfolioCoder.QA do
  @moduledoc """
  Ask questions about your codebase.
  """

  # Adapters Used:
  # - PortfolioManager.RAG (query, ask, search)
  # - PortfolioIndex.RAG.Strategies.* (all strategies)
  # - PortfolioManager.Router (LLM routing)
  # - PortfolioManager.Evaluation (answer quality)

  @type strategy :: :hybrid | :self_rag | :graph_rag | :agentic

  @spec ask(question :: String.t(), opts :: keyword()) :: {:ok, answer()}
  def ask(question, opts \\ [])

  @spec ask_with_sources(question :: String.t(), opts :: keyword()) :: {:ok, sourced_answer()}
  def ask_with_sources(question, opts \\ [])

  @spec stream_answer(question :: String.t(), callback :: fun()) :: :ok
  def stream_answer(question, callback)
end
```

**Strategy Selection**:
| Question Type | Best Strategy | Why |
|---------------|---------------|-----|
| "What does X do?" | `:hybrid` | Direct code lookup |
| "How does X work?" | `:graph_rag` | Needs relationship context |
| "Why was X implemented this way?" | `:self_rag` | Needs careful reasoning |
| "Help me debug X" | `:agentic` | Needs tool use |

#### 4.2 Self-Correcting Code QA

```elixir
defmodule PortfolioCoder.QA.SelfCorrecting do
  @moduledoc """
  Self-critiquing answers with automatic refinement.
  """

  # Adapters Used:
  # - PortfolioIndex.RAG.Strategies.SelfRAG
  # - PortfolioIndex.RAG.SelfCorrectingSearch
  # - PortfolioIndex.RAG.SelfCorrectingAnswer
  # - PortfolioManager.Evaluation (RAG triad)

  @spec ask_with_verification(question :: String.t()) :: {:ok, verified_answer()}
  def ask_with_verification(question)
end
```

**Self-Correction Flow**:
```
Question → Assess retrieval need → Retrieve (if needed)
    │
    └─→ Generate with critique → Evaluate scores
                                       │
                                       ├─→ Score >= threshold: Return
                                       │
                                       └─→ Score < threshold: Refine → Re-evaluate
```

#### 4.3 Graph-Aware Q&A

```elixir
defmodule PortfolioCoder.QA.GraphAware do
  @moduledoc """
  Q&A that leverages code knowledge graph.
  """

  # Adapters Used:
  # - PortfolioIndex.RAG.Strategies.GraphRAG
  # - PortfolioIndex.GraphRAG.EntityExtractor
  # - PortfolioIndex.Adapters.GraphStore.Neo4j
  # - PortfolioIndex.Adapters.GraphStore.Neo4j.Community

  @spec ask_about_relationships(question :: String.t()) :: {:ok, answer()}
  def ask_about_relationships(question)

  @spec explain_architecture() :: {:ok, explanation()}
  def explain_architecture()

  @spec trace_data_flow(from :: String.t(), to :: String.t()) :: {:ok, explanation()}
  def trace_data_flow(from, to)
end
```

**Graph Q&A Modes**:
- **Local Search**: Entity-specific questions ("What calls `authenticate/2`?")
- **Global Search**: Architectural questions ("How is auth organized?")
- **Hybrid**: Combined for comprehensive answers

---

### 5. CODE AGENT SERVICE

**Purpose**: Autonomous agent for complex code tasks.

#### 5.1 Code Intelligence Agent

```elixir
defmodule PortfolioCoder.Agent do
  @moduledoc """
  Tool-using agent for complex code analysis.
  """

  # Adapters Used:
  # - PortfolioManager.Agent (agent framework)
  # - PortfolioManager.Agent.Session (conversation state)
  # - PortfolioManager.Agent.Tool (tool definitions)
  # - PortfolioManager.Router (LLM selection)
  # - PortfolioCore.Ports.Agent (behavior)
  # - PortfolioCore.Ports.Tool (behavior)

  @spec run(task :: String.t(), opts :: keyword()) :: {:ok, result()}
  def run(task, opts \\ [])

  @spec chat(session :: session(), message :: String.t()) :: {:ok, response(), session()}
  def chat(session, message)

  @spec with_context(session :: session(), context_type :: atom(), data :: term()) :: session()
  def with_context(session, context_type, data)
end
```

#### 5.2 Code Tools

```elixir
defmodule PortfolioCoder.Agent.Tools do
  @moduledoc """
  Tools available to the code agent.
  """

  # Adapters Used:
  # - PortfolioManager.Agent.Tool (tool framework)
  # - PortfolioCore.Ports.Tool (behavior)
end
```

**Available Tools**:

| Tool | Description | Adapters Used |
|------|-------------|---------------|
| `search_code` | Semantic code search | VectorStore, Embedder, Reranker |
| `read_file` | Read file contents | DocumentStore |
| `list_files` | List directory contents | FileSystem |
| `get_symbol` | Get symbol definition | AST Parser, VectorStore |
| `get_callers` | Find function callers | GraphStore.Traversal |
| `get_callees` | Find function calls | GraphStore.Traversal |
| `get_dependencies` | Get package deps | GraphStore |
| `get_dependents` | Get reverse deps | GraphStore |
| `search_graph` | Query knowledge graph | GraphStore, EntitySearch |
| `run_tests` | Execute tests | Bash |
| `analyze_coverage` | Check test coverage | Bash |
| `check_types` | Run type checker | Bash (dialyzer/mypy) |
| `lint_code` | Run linter | Bash (credo/pylint) |
| `explain_code` | Explain code snippet | LLM |
| `suggest_refactor` | Suggest improvements | LLM |

#### 5.3 Specialized Agents

```elixir
defmodule PortfolioCoder.Agent.Specialists do
  @moduledoc """
  Pre-configured agents for specific tasks.
  """

  # Uses: PortfolioManager.Router with :specialist strategy

  @spec debug_agent() :: agent_config()
  def debug_agent()

  @spec refactor_agent() :: agent_config()
  def refactor_agent()

  @spec documentation_agent() :: agent_config()
  def documentation_agent()

  @spec review_agent() :: agent_config()
  def review_agent()

  @spec test_agent() :: agent_config()
  def test_agent()
end
```

**Agent Capabilities by Provider**:
```elixir
# Router configuration for specialist routing
providers: [
  %{
    name: :claude,
    capabilities: [:reasoning, :code, :generation],
    priority: 1,
    cost_per_token: 0.003
  },
  %{
    name: :gpt4,
    capabilities: [:code, :function_calling, :streaming],
    priority: 2,
    cost_per_token: 0.01
  },
  %{
    name: :gemini,
    capabilities: [:generation, :code],
    priority: 3,
    cost_per_token: 0.001
  }
]
```

---

### 6. CODE REVIEW SERVICE

**Purpose**: Automated code review and quality analysis.

#### 6.1 Automated Code Review

```elixir
defmodule PortfolioCoder.Review do
  @moduledoc """
  AI-powered code review.
  """

  # Adapters Used:
  # - PortfolioManager.Agent (review agent)
  # - PortfolioManager.RAG (context retrieval)
  # - PortfolioManager.Router (LLM selection)
  # - PortfolioManager.Evaluation (quality scoring)

  @spec review_file(path :: String.t(), opts :: keyword()) :: {:ok, review()}
  def review_file(path, opts \\ [])

  @spec review_diff(diff :: String.t(), opts :: keyword()) :: {:ok, review()}
  def review_diff(diff, opts \\ [])

  @spec review_pr(pr_url :: String.t(), opts :: keyword()) :: {:ok, review()}
  def review_pr(pr_url, opts \\ [])
end
```

**Review Categories**:
- **Security**: Injection, auth issues, secrets
- **Performance**: N+1 queries, memory leaks, inefficient algorithms
- **Maintainability**: Code smells, complexity, naming
- **Testing**: Missing tests, edge cases, coverage
- **Documentation**: Missing docs, outdated comments
- **Style**: Formatting, conventions, idioms

#### 6.2 Quality Metrics

```elixir
defmodule PortfolioCoder.Review.Metrics do
  @moduledoc """
  Code quality scoring.
  """

  # Adapters Used:
  # - PortfolioIndex.Adapters.RetrievalMetrics.Standard (scoring)
  # - PortfolioManager.Evaluation (RAG triad for explanations)

  @spec analyze_repo(repo_id :: String.t()) :: {:ok, quality_report()}
  def analyze_repo(repo_id)

  @spec complexity_score(path :: String.t()) :: {:ok, score()}
  def complexity_score(path)

  @spec test_coverage_analysis(repo_id :: String.t()) :: {:ok, coverage_report()}
  def test_coverage_analysis(repo_id)
end
```

---

### 7. DOCUMENTATION SERVICE

**Purpose**: Generate and search documentation.

#### 7.1 Documentation Generation

```elixir
defmodule PortfolioCoder.Docs.Generator do
  @moduledoc """
  AI-powered documentation generation.
  """

  # Adapters Used:
  # - PortfolioManager.Agent (doc generation agent)
  # - PortfolioManager.RAG (context for related code)
  # - PortfolioCoder.Graph.CodeGraph (relationship context)
  # - PortfolioManager.Router (LLM selection)

  @spec generate_module_docs(module :: String.t()) :: {:ok, docs()}
  def generate_module_docs(module)

  @spec generate_function_docs(mfa :: mfa()) :: {:ok, docs()}
  def generate_function_docs(mfa)

  @spec generate_readme(repo_id :: String.t()) :: {:ok, readme()}
  def generate_readme(repo_id)

  @spec generate_api_docs(repo_id :: String.t()) :: {:ok, api_docs()}
  def generate_api_docs(repo_id)

  @spec generate_architecture_doc(repos :: [String.t()]) :: {:ok, arch_doc()}
  def generate_architecture_doc(repos)
end
```

#### 7.2 Documentation Search

```elixir
defmodule PortfolioCoder.Docs.Search do
  @moduledoc """
  Search across documentation and code.
  """

  # Adapters Used:
  # - PortfolioIndex.RAG.Strategies.Hybrid
  # - PortfolioIndex.Adapters.CollectionSelector.* (route to docs vs code)

  @spec search_docs(query :: String.t(), opts :: keyword()) :: {:ok, [result()]}
  def search_docs(query, opts \\ [])

  @spec search_all(query :: String.t(), opts :: keyword()) :: {:ok, combined_results()}
  def search_all(query, opts \\ [])
end
```

**Collection Separation**:
```elixir
collections: [
  %{id: "code", description: "Source code files"},
  %{id: "docs", description: "Documentation and README files"},
  %{id: "tests", description: "Test files and examples"},
  %{id: "config", description: "Configuration files"}
]
```

---

### 8. WORKFLOW ORCHESTRATION

**Purpose**: Compose complex multi-step operations.

#### 8.1 Code Intelligence Pipelines

```elixir
defmodule PortfolioCoder.Workflows do
  @moduledoc """
  Pre-built workflows for common tasks.
  """

  # Adapters Used:
  # - PortfolioManager.Pipeline (DAG execution)
  # - PortfolioCore.Ports.Pipeline (behavior)
  # - All other services as pipeline steps
end
```

**Example Workflows**:

```elixir
# Full Repository Analysis Pipeline
defmodule PortfolioCoder.Workflows.AnalyzeRepo do
  use PortfolioManager.Pipeline

  pipeline :analyze_repo do
    step :scan_files, &scan_files/1
    step :parse_ast, &parse_ast/1, depends_on: [:scan_files]
    step :extract_symbols, &extract_symbols/1, depends_on: [:parse_ast]
    step :build_graph, &build_graph/1, depends_on: [:extract_symbols]
    step :chunk_code, &chunk_code/1, depends_on: [:parse_ast], parallel: true
    step :embed_chunks, &embed_chunks/1, depends_on: [:chunk_code]
    step :store_vectors, &store_vectors/1, depends_on: [:embed_chunks]
    step :detect_communities, &detect_communities/1, depends_on: [:build_graph]
    step :generate_summaries, &generate_summaries/1, depends_on: [:detect_communities]
  end
end

# Code Review Pipeline
defmodule PortfolioCoder.Workflows.ReviewCode do
  use PortfolioManager.Pipeline

  pipeline :review_code do
    step :get_diff, &get_diff/1
    step :analyze_changes, &analyze_changes/1, depends_on: [:get_diff]
    step :get_context, &get_related_code/1, depends_on: [:analyze_changes], parallel: true
    step :get_tests, &get_related_tests/1, depends_on: [:analyze_changes], parallel: true
    step :security_scan, &security_scan/1, depends_on: [:get_diff], parallel: true
    step :generate_review, &generate_review/1, depends_on: [:get_context, :get_tests, :security_scan]
    step :evaluate_quality, &evaluate_review/1, depends_on: [:generate_review]
  end
end
```

---

### 9. MULTI-PROVIDER LLM ROUTING

**Purpose**: Intelligent routing across LLM providers.

#### 9.1 Smart Router Configuration

```elixir
defmodule PortfolioCoder.LLM do
  @moduledoc """
  Multi-provider LLM access with intelligent routing.
  """

  # Adapters Used:
  # - PortfolioManager.Router (routing logic)
  # - PortfolioIndex.Adapters.LLM.Anthropic (Claude)
  # - PortfolioIndex.Adapters.LLM.OpenAI (GPT)
  # - PortfolioIndex.Adapters.LLM.Gemini (Gemini)
  # - PortfolioCore.Ports.Router (behavior)
  # - PortfolioCore.Ports.LLM (behavior)

  @spec complete(messages :: [message()], opts :: keyword()) :: {:ok, response()}
  def complete(messages, opts \\ [])

  @spec stream(messages :: [message()], callback :: fun()) :: :ok
  def stream(messages, callback)
end
```

**Routing Strategies**:
```elixir
# Fallback Strategy - Try providers in order
config :portfolio_coder, :router,
  strategy: :fallback,
  providers: [
    %{name: :claude, priority: 1, module: PortfolioIndex.Adapters.LLM.Anthropic},
    %{name: :gpt4, priority: 2, module: PortfolioIndex.Adapters.LLM.OpenAI},
    %{name: :gemini, priority: 3, module: PortfolioIndex.Adapters.LLM.Gemini}
  ]

# Specialist Strategy - Route by task type
config :portfolio_coder, :router,
  strategy: :specialist,
  routing_rules: %{
    code: :claude,        # Claude excels at code
    reasoning: :claude,   # Complex reasoning
    generation: :gpt4,    # General generation
    quick: :gemini        # Fast, cheap tasks
  }

# Cost-Optimized Strategy - Minimize cost
config :portfolio_coder, :router,
  strategy: :cost_optimized,
  budget_per_hour: 10.0,  # dollars
  min_quality: 0.8        # don't sacrifice too much quality
```

---

### 10. OBSERVABILITY & EVALUATION

**Purpose**: Monitor, evaluate, and improve system quality.

#### 10.1 Telemetry Dashboard

```elixir
defmodule PortfolioCoder.Telemetry do
  @moduledoc """
  Comprehensive telemetry for all operations.
  """

  # Adapters Used:
  # - PortfolioCore.Telemetry (event definitions)
  # - PortfolioIndex.Telemetry.* (component telemetry)
  # - PortfolioManager telemetry events

  @spec attach_handlers() :: :ok
  def attach_handlers()
end
```

**Events Captured**:
```elixir
# Indexing
[:portfolio_coder, :indexer, :file, :start/:stop/:exception]
[:portfolio_coder, :indexer, :chunk, :start/:stop/:exception]
[:portfolio_coder, :indexer, :embed, :start/:stop/:exception]

# Search
[:portfolio_coder, :search, :query, :start/:stop/:exception]
[:portfolio_coder, :search, :rerank, :start/:stop/:exception]

# RAG
[:portfolio, :rag, :*, :start/:stop/:exception]  # From portfolio_index

# LLM
[:portfolio, :llm, :complete, :start/:stop/:exception]
[:portfolio_core, :router, :route, :start/:stop/:exception]

# Agent
[:portfolio_core, :agent, :run/:tool, :start/:stop/:exception]

# Graph
[:portfolio_core, :graph_store, :*, :start/:stop/:exception]
```

#### 10.2 Quality Evaluation

```elixir
defmodule PortfolioCoder.Evaluation do
  @moduledoc """
  Evaluate and benchmark system quality.
  """

  # Adapters Used:
  # - PortfolioManager.Evaluation (RAG triad)
  # - PortfolioIndex.Evaluation (test harness)
  # - PortfolioIndex.Evaluation.Generator (synthetic data)
  # - PortfolioIndex.Adapters.RetrievalMetrics.Standard
  # - PortfolioCore.Ports.Evaluation (behavior)
  # - PortfolioCore.Ports.RetrievalMetrics (behavior)

  @spec evaluate_search(test_cases :: [test_case()]) :: {:ok, metrics()}
  def evaluate_search(test_cases)

  @spec evaluate_qa(test_cases :: [test_case()]) :: {:ok, metrics()}
  def evaluate_qa(test_cases)

  @spec generate_test_cases(repo_id :: String.t(), count :: integer()) :: {:ok, [test_case()]}
  def generate_test_cases(repo_id, count)
end
```

**Metrics Tracked**:
- **Retrieval**: Recall@K, Precision@K, MRR, Hit Rate
- **Generation**: Context Relevance, Groundedness, Answer Relevance (RAG Triad)
- **Hallucination**: Rate of unsupported claims
- **Latency**: P50, P95, P99 response times
- **Cost**: Tokens used, API costs

---

## CLI Commands

```bash
# Indexing
mix code.index [repo_id]              # Index a repository
mix code.index --all                  # Index all repos in portfolio
mix code.reindex [repo_id]            # Reindex changed files
mix code.index.status                 # Show indexing status

# Search
mix code.search "query"               # Semantic code search
mix code.search "query" --repo=app    # Search in specific repo
mix code.search "query" --mode=hybrid # Use hybrid search
mix code.find "symbol_name"           # Find symbol definition

# Q&A
mix code.ask "question"               # Ask about code
mix code.ask "question" --strategy=graph_rag  # Use graph strategy
mix code.explain [file:line]          # Explain code at location

# Agent
mix code.agent "task"                 # Run agent on task
mix code.agent.debug "error"          # Debug an error
mix code.agent.refactor [file]        # Suggest refactoring

# Graph
mix code.graph.build [repo_id]        # Build knowledge graph
mix code.graph.deps [package]         # Show dependencies
mix code.graph.impact [package]       # Show impact analysis
mix code.graph.query "cypher"         # Run graph query

# Review
mix code.review [file]                # Review file
mix code.review.pr [pr_url]           # Review pull request
mix code.review.repo [repo_id]        # Full repo review

# Docs
mix code.docs.generate [module]       # Generate docs
mix code.docs.readme [repo_id]        # Generate README
mix code.docs.search "query"          # Search docs

# Evaluation
mix code.eval.run                     # Run evaluation suite
mix code.eval.generate [repo_id]      # Generate test cases
mix code.eval.report                  # Show evaluation report

# Portfolio (existing)
mix portfolio.scan                    # Scan for repos
mix portfolio.list                    # List repos
mix portfolio.show [repo_id]          # Show repo details
mix portfolio.sync                    # Sync all repos
```

---

## Configuration

### config/config.exs

```elixir
import Config

# Portfolio Core - Adapter Registry
config :portfolio_core,
  manifest_path: "config/manifests/#{config_env()}.yml"

# Portfolio Index - Adapters
config :portfolio_index,
  # Embedder
  embedder: PortfolioIndex.Adapters.Embedder.OpenAI,
  embedder_config: [
    model: "text-embedding-3-small",
    api_key: {:system, "OPENAI_API_KEY"}
  ],

  # LLM (primary)
  llm: PortfolioIndex.Adapters.LLM.Anthropic,
  llm_config: [
    model: "claude-sonnet-4-20250514",
    api_key: {:system, "ANTHROPIC_API_KEY"}
  ],

  # Vector Store
  vector_store: PortfolioIndex.Adapters.VectorStore.Pgvector,
  vector_store_config: [
    repo: PortfolioIndex.Repo,
    index_type: :hnsw,
    distance_metric: :cosine
  ],

  # Graph Store
  graph_store: PortfolioIndex.Adapters.GraphStore.Neo4j,
  graph_store_config: [
    url: {:system, "NEO4J_URL"},
    auth: {:basic, {:system, "NEO4J_USER"}, {:system, "NEO4J_PASSWORD"}}
  ],

  # Chunker
  chunker: PortfolioIndex.Adapters.Chunker.Recursive,
  chunker_config: [
    chunk_size: 1500,
    chunk_overlap: 200
  ],

  # Reranker
  reranker: PortfolioIndex.Adapters.Reranker.LLM,
  reranker_config: [
    top_n: 5
  ]

# Portfolio Manager - Router
config :portfolio_manager,
  router_strategy: :fallback,
  router_providers: [
    %{
      name: :claude,
      module: PortfolioIndex.Adapters.LLM.Anthropic,
      priority: 1,
      capabilities: [:reasoning, :code, :generation]
    },
    %{
      name: :gpt4,
      module: PortfolioIndex.Adapters.LLM.OpenAI,
      config: [model: "gpt-4o"],
      priority: 2,
      capabilities: [:code, :function_calling]
    },
    %{
      name: :gemini,
      module: PortfolioIndex.Adapters.LLM.Gemini,
      priority: 3,
      capabilities: [:generation, :code]
    }
  ],
  health_check_interval: 30_000,
  failure_threshold: 3

# Portfolio Coder - Code Intelligence
config :portfolio_coder,
  portfolio_path: "~/p/g/n/portfolio",

  # Indexing
  index_patterns: ["**/*.ex", "**/*.exs", "**/*.py", "**/*.js", "**/*.ts"],
  index_exclude: ["**/node_modules/**", "**/deps/**", "**/_build/**"],
  chunk_strategy: :hybrid,

  # Search
  default_search_mode: :hybrid,
  rerank_enabled: true,

  # RAG
  default_rag_strategy: :hybrid,

  # Agent
  agent_max_iterations: 10,
  agent_tools: [:search_code, :read_file, :list_files, :get_graph_context]
```

---

## Adapter Usage Matrix

| Feature | Embedder | LLM | VectorStore | GraphStore | Chunker | Reranker | Query* | Other |
|---------|----------|-----|-------------|------------|---------|----------|--------|-------|
| Indexing | ✓ | | ✓ | | ✓ | | | DocStore |
| Search | ✓ | | ✓ | | | ✓ | ✓ | |
| Hybrid Search | ✓ | | ✓ (full) | | | ✓ | | |
| Graph Build | | ✓ | | ✓ | | | | EntityExtract |
| Graph Q&A | ✓ | ✓ | ✓ | ✓ | | | | Community |
| Self-RAG | ✓ | ✓ | ✓ | | | | | Evaluation |
| Agentic | ✓ | ✓ | ✓ | ✓ | | | ✓ | Tools, Router |
| Code Review | | ✓ | | | | | | Agent |
| Doc Gen | | ✓ | | ✓ | | | | Agent |
| Evaluation | | ✓ | | | | | | Metrics |

*Query = QueryRewriter, QueryExpander, QueryDecomposer, CollectionSelector

---

## Implementation Priority

### Phase 1: Foundation (Core Indexing & Search)
1. Multi-language AST parser
2. Code-aware chunking
3. Embedding pipeline with rate limiting
4. Hybrid search with reranking
5. Basic CLI commands

### Phase 2: Intelligence (Knowledge Graph & RAG)
1. Code knowledge graph building
2. Dependency graph analysis
3. Hybrid RAG for code Q&A
4. Graph-aware Q&A
5. Call graph analysis

### Phase 3: Automation (Agents & Workflows)
1. Code agent with tools
2. Specialized agents (debug, review, docs)
3. Workflow pipelines
4. Multi-provider routing
5. PR review automation

### Phase 4: Quality (Evaluation & Optimization)
1. RAG triad evaluation
2. Retrieval metrics
3. Test case generation
4. Performance optimization
5. Telemetry dashboard

---

## Summary

This design fully leverages:

**From portfolio_core:**
- All 21 port behaviors
- Registry for adapter management
- Manifest engine for configuration
- Telemetry for observability

**From portfolio_index:**
- All embedder adapters (OpenAI, Gemini, Bumblebee)
- All LLM adapters (Anthropic, OpenAI, Gemini)
- Vector stores (Pgvector, Memory)
- Graph store (Neo4j)
- All chunkers (Recursive, Semantic, etc.)
- All RAG strategies (Hybrid, SelfRAG, GraphRAG, Agentic)
- All query processors
- Rerankers
- GraphRAG components
- Evaluation framework

**From portfolio_manager:**
- RAG interface
- Multi-provider router
- Agent framework with tools
- Pipeline orchestration
- Graph interface
- Evaluation (RAG triad)
- CLI task framework

The result is a comprehensive code intelligence engine that can index, search, understand, navigate, generate, review, and document code across your entire ecosystem.
