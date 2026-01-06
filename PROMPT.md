# Portfolio Coder: Code Intelligence Engine Implementation Prompt

This prompt is designed for iterative execution. Each session continues where the previous left off.

---

## PHASE 0: REQUIRED READING & STATUS ASSESSMENT

**You MUST complete this phase before any implementation work.**

### 0.1 Read Core Documentation

```
REQUIRED READING (in order):
1. /home/home/p/g/n/portfolio_coder/DESIGN.md          # Full feature design
2. /home/home/p/g/n/portfolio_coder/CLAUDE.md          # Current implementation status
3. /home/home/p/g/n/portfolio_coder/CHANGELOG.md       # Recent changes
4. /home/home/p/g/n/portfolio_coder/mix.exs            # Dependencies & version

5. /home/home/p/g/n/portfolio_core/CLAUDE.md           # Core status (if exists)
6. /home/home/p/g/n/portfolio_core/mix.exs             # Core deps
7. /home/home/p/g/n/portfolio_core/lib/portfolio_core.ex

8. /home/home/p/g/n/portfolio_index/CLAUDE.md          # Index status (if exists)
9. /home/home/p/g/n/portfolio_index/mix.exs            # Index deps
10. /home/home/p/g/n/portfolio_index/lib/portfolio_index.ex

11. /home/home/p/g/n/portfolio_manager/CLAUDE.md       # Manager status (if exists)
12. /home/home/p/g/n/portfolio_manager/mix.exs         # Manager deps
13. /home/home/p/g/n/portfolio_manager/lib/portfolio_manager.ex
```

### 0.2 Assess Current Status

Run these commands to assess the current state of all four repos:

```bash
# Portfolio Coder
cd /home/home/p/g/n/portfolio_coder && mix deps.get && mix compile --warnings-as-errors 2>&1 | head -50
cd /home/home/p/g/n/portfolio_coder && mix test --trace 2>&1 | tail -20
cd /home/home/p/g/n/portfolio_coder && mix dialyzer 2>&1 | tail -20

# Portfolio Core
cd /home/home/p/g/n/portfolio_core && mix deps.get && mix compile --warnings-as-errors 2>&1 | head -50
cd /home/home/p/g/n/portfolio_core && mix test --trace 2>&1 | tail -20

# Portfolio Index
cd /home/home/p/g/n/portfolio_index && mix deps.get && mix compile --warnings-as-errors 2>&1 | head -50
cd /home/home/p/g/n/portfolio_index && mix test --trace 2>&1 | tail -20

# Portfolio Manager
cd /home/home/p/g/n/portfolio_manager && mix deps.get && mix compile --warnings-as-errors 2>&1 | head -50
cd /home/home/p/g/n/portfolio_manager && mix test --trace 2>&1 | tail -20
```

### 0.3 Check Example Status

```bash
# List existing examples
ls -la /home/home/p/g/n/portfolio_coder/examples/

# Try running each example (note which work/fail)
cd /home/home/p/g/n/portfolio_coder
for f in examples/*.exs; do echo "=== $f ==="; mix run "$f" 2>&1 | head -20; done
```

### 0.4 Update CLAUDE.md (Pre-Implementation)

After reading and assessment, update `/home/home/p/g/n/portfolio_coder/CLAUDE.md` with:

```markdown
# Portfolio Coder - Claude Implementation Status

## Last Updated
[DATE] - Session [N]

## Current State

### Build Status
- [ ] portfolio_coder: compiles / tests pass / dialyzer clean
- [ ] portfolio_core: compiles / tests pass / dialyzer clean
- [ ] portfolio_index: compiles / tests pass / dialyzer clean
- [ ] portfolio_manager: compiles / tests pass / dialyzer clean

### Test Counts
- portfolio_coder: X tests, Y failures
- portfolio_core: X tests, Y failures
- portfolio_index: X tests, Y failures
- portfolio_manager: X tests, Y failures

### Warnings/Errors
[List any compilation warnings or errors]

## Implementation Progress

### Phase 1: Foundation (Core Indexing & Search)
- [ ] 1.1 Multi-language AST parser
- [ ] 1.2 Code-aware chunking
- [ ] 1.3 Embedding pipeline
- [ ] 1.4 Hybrid search with reranking
- [ ] 1.5 Basic CLI commands

### Phase 2: Intelligence (Knowledge Graph & RAG)
- [ ] 2.1 Code knowledge graph building
- [ ] 2.2 Dependency graph analysis
- [ ] 2.3 Hybrid RAG for code Q&A
- [ ] 2.4 Graph-aware Q&A
- [ ] 2.5 Call graph analysis

### Phase 3: Automation (Agents & Workflows)
- [ ] 3.1 Code agent with tools
- [ ] 3.2 Specialized agents
- [ ] 3.3 Workflow pipelines
- [ ] 3.4 Multi-provider routing
- [ ] 3.5 PR review automation

### Phase 4: Quality (Evaluation & Optimization)
- [ ] 4.1 RAG triad evaluation
- [ ] 4.2 Retrieval metrics
- [ ] 4.3 Test case generation
- [ ] 4.4 Performance optimization
- [ ] 4.5 Telemetry dashboard

## Working Examples
[List examples/*.exs that run successfully]

## Blocked Issues
[List any blocking issues preventing progress]

## Next Steps
[What to implement next this session]

## Session History
- Session 1: [summary]
- Session 2: [summary]
...
```

---

## PHASE 1: IMPLEMENTATION (TDD / Red-Green-Refactor)

**Only proceed here after Phase 0 is complete.**

### 1.1 Implementation Rules

1. **TDD Workflow**:
   - RED: Write failing test first
   - GREEN: Write minimum code to pass
   - REFACTOR: Clean up while keeping tests green

2. **Quality Gates** (must pass before moving on):
   - All tests pass: `mix test`
   - No warnings: `mix compile --warnings-as-errors`
   - No dialyzer errors: `mix dialyzer`
   - Example runs successfully: `mix run examples/{feature}.exs`

3. **Cross-Repo Changes**:
   - When modifying portfolio_core/index/manager, run their tests too
   - Ensure changes don't break downstream repos
   - Update CLAUDE.md in each modified repo

4. **Example-Driven Development**:
   - Each feature MUST have a working example in `examples/`
   - Example must demonstrate the feature end-to-end
   - Example must print meaningful output

### 1.2 Feature Implementation Order

Follow DESIGN.md phases. For each feature:

```
1. Read relevant sections in DESIGN.md
2. Identify which adapters/modules are needed
3. Check if adapters exist in portfolio_index
4. Write test file: test/portfolio_coder/{feature}_test.exs
5. Write failing tests (RED)
6. Implement in lib/portfolio_coder/{feature}.ex (GREEN)
7. Refactor if needed
8. Create example: examples/{feature}_demo.exs
9. Run example, verify it works
10. Run full test suite across all repos
11. Update CLAUDE.md progress
```

### 1.3 Example File Template

Each example should follow this structure:

```elixir
# examples/{feature}_demo.exs
#
# Demonstrates: {Feature Name}
# Adapters Used: {list from portfolio_index}
# Prerequisites: {any setup needed}
#
# Usage: mix run examples/{feature}_demo.exs

# Optional: Configure for demo
Application.put_env(:portfolio_coder, :some_config, :value)

alias PortfolioCoder.{Relevant, Modules}

IO.puts("=" |> String.duplicate(60))
IO.puts("{Feature Name} Demo")
IO.puts("=" |> String.duplicate(60))
IO.puts("")

# Demo code here with meaningful output
case Module.function(args) do
  {:ok, result} ->
    IO.puts("Success!")
    IO.inspect(result, label: "Result")

  {:error, reason} ->
    IO.puts(:stderr, "Error: #{inspect(reason)}")
    System.halt(1)
end

IO.puts("")
IO.puts("Demo complete!")
```

---

## PHASE 2: EXAMPLE SPECIFICATIONS

Create these examples in order, ensuring each works before moving to next:

### Foundation Examples (Phase 1)

#### examples/01_indexing_demo.exs
```
Demonstrates: Code indexing pipeline
Adapters: Chunker.Recursive, Embedder.*, VectorStore.Pgvector, DocumentStore
Tests: File scanning, chunking, embedding, storage
Output: Stats on indexed files, chunks, vectors
```

#### examples/02_search_demo.exs
```
Demonstrates: Hybrid code search
Adapters: VectorStore.Pgvector (semantic + fulltext), Embedder, Reranker.LLM
Tests: Semantic search, keyword search, hybrid merge, reranking
Output: Search results with scores, sources, snippets
```

#### examples/03_query_enhancement_demo.exs
```
Demonstrates: Query processing pipeline
Adapters: QueryRewriter.LLM, QueryExpander.LLM, QueryDecomposer.LLM
Tests: Query cleaning, expansion, decomposition
Output: Original vs enhanced queries
```

### Intelligence Examples (Phase 2)

#### examples/04_graph_build_demo.exs
```
Demonstrates: Knowledge graph construction
Adapters: GraphStore.Neo4j, EntityExtractor, Parser
Tests: Node creation, edge creation, traversal
Output: Graph stats, sample queries
```

#### examples/05_dependency_analysis_demo.exs
```
Demonstrates: Cross-repo dependency analysis
Adapters: GraphStore.Neo4j, Traversal
Tests: Dependency extraction, impact analysis, cycle detection
Output: Dependency tree, impact report
```

#### examples/06_rag_hybrid_demo.exs
```
Demonstrates: Hybrid RAG for code Q&A
Adapters: RAG.Strategies.Hybrid, Embedder, VectorStore, LLM
Tests: Question answering with sources
Output: Answer with cited code snippets
```

#### examples/07_rag_graph_demo.exs
```
Demonstrates: Graph-aware RAG
Adapters: RAG.Strategies.GraphRAG, GraphStore, EntityExtractor, Community
Tests: Entity linking, local search, global search
Output: Graph-contextualized answers
```

#### examples/08_rag_self_demo.exs
```
Demonstrates: Self-correcting RAG
Adapters: RAG.Strategies.SelfRAG, SelfCorrectingSearch, SelfCorrectingAnswer
Tests: Critique scoring, refinement
Output: Answer with critique scores, refinement history
```

### Automation Examples (Phase 3)

#### examples/09_agent_basic_demo.exs
```
Demonstrates: Code agent with tools
Adapters: Agent, Tool, Router, VectorStore, GraphStore
Tests: Tool execution, multi-turn conversation
Output: Agent reasoning trace, tool results
```

#### examples/10_agent_debug_demo.exs
```
Demonstrates: Debug specialist agent
Adapters: Agent.Specialists.Debug, all search tools
Tests: Error analysis, fix suggestions
Output: Debug analysis report
```

#### examples/11_router_demo.exs
```
Demonstrates: Multi-provider LLM routing
Adapters: Router (all strategies), LLM.Anthropic, LLM.OpenAI, LLM.Gemini
Tests: Fallback, round-robin, specialist routing
Output: Provider selection trace, health status
```

#### examples/12_pipeline_demo.exs
```
Demonstrates: DAG workflow execution
Adapters: Pipeline, all services as steps
Tests: Dependency resolution, parallel execution, error handling
Output: Pipeline execution trace, timing
```

### Quality Examples (Phase 4)

#### examples/13_evaluation_demo.exs
```
Demonstrates: RAG quality evaluation
Adapters: Evaluation, RetrievalMetrics.Standard, RAG Triad
Tests: Retrieval metrics, generation quality
Output: Evaluation report with scores
```

#### examples/14_telemetry_demo.exs
```
Demonstrates: Telemetry and observability
Adapters: Telemetry (all events)
Tests: Event capture, metrics aggregation
Output: Telemetry event stream, metrics summary
```

#### examples/15_full_demo.exs
```
Demonstrates: Complete code intelligence workflow
Adapters: ALL
Tests: Index -> Search -> Q&A -> Agent -> Review
Output: Full workflow trace
```

---

## PHASE 3: VALIDATION & COMPLETION

### 3.1 Final Validation Checklist

Before marking a session complete, verify:

```bash
# All repos compile without warnings
cd /home/home/p/g/n/portfolio_core && mix compile --warnings-as-errors
cd /home/home/p/g/n/portfolio_index && mix compile --warnings-as-errors
cd /home/home/p/g/n/portfolio_manager && mix compile --warnings-as-errors
cd /home/home/p/g/n/portfolio_coder && mix compile --warnings-as-errors

# All tests pass
cd /home/home/p/g/n/portfolio_core && mix test
cd /home/home/p/g/n/portfolio_index && mix test
cd /home/home/p/g/n/portfolio_manager && mix test
cd /home/home/p/g/n/portfolio_coder && mix test

# Dialyzer passes (at minimum on portfolio_coder)
cd /home/home/p/g/n/portfolio_coder && mix dialyzer

# All implemented examples run
cd /home/home/p/g/n/portfolio_coder
for f in examples/*_demo.exs; do
  echo "Running $f..."
  mix run "$f" || echo "FAILED: $f"
done
```

### 3.2 Update CLAUDE.md (Post-Implementation)

After implementation work, update CLAUDE.md with:

1. Updated progress checkboxes
2. New test counts
3. New working examples
4. Any new blocked issues
5. Next steps for next session
6. Session summary added to history

### 3.3 Commit Guidelines

When changes are ready:

```bash
# Stage all changes across repos
cd /home/home/p/g/n/portfolio_coder && git add -A
cd /home/home/p/g/n/portfolio_core && git add -A
cd /home/home/p/g/n/portfolio_index && git add -A
cd /home/home/p/g/n/portfolio_manager && git add -A

# Commit with descriptive message
# Format: "feat(component): description"
# Include: what was implemented, what examples work
```

---

## ADAPTER REFERENCE (Quick Lookup)

When implementing features, reference these adapters:

### Embedders (portfolio_index/lib/portfolio_index/adapters/embedder/)
- `OpenAI` - OpenAI text-embedding-3-*
- `Gemini` - Google embedding models
- `Bumblebee` - Local HuggingFace models
- `Function` - Custom embedding function

### LLMs (portfolio_index/lib/portfolio_index/adapters/llm/)
- `Anthropic` - Claude models
- `OpenAI` - GPT models
- `Gemini` - Google models
- `Codex` - Code-specific (legacy)

### Vector Stores (portfolio_index/lib/portfolio_index/adapters/vector_store/)
- `Pgvector` - PostgreSQL with pgvector
- `Pgvector.Hybrid` - Semantic + fulltext
- `Pgvector.Fulltext` - Keyword search
- `Memory` - In-memory HNSWLib

### Graph Store (portfolio_index/lib/portfolio_index/adapters/graph_store/)
- `Neo4j` - Neo4j graph database
- `Neo4j.EntitySearch` - Node search
- `Neo4j.Traversal` - Path traversal
- `Neo4j.Community` - Clustering
- `Neo4j.Schema` - Schema management

### Chunkers (portfolio_index/lib/portfolio_index/adapters/chunker/)
- `Recursive` - Format-aware hierarchical
- `Semantic` - Embedding-based boundaries
- `Sentence` - Sentence boundaries
- `Character` - Fixed size
- `Paragraph` - Paragraph boundaries

### Rerankers (portfolio_index/lib/portfolio_index/adapters/reranker/)
- `LLM` - LLM-based scoring
- `Passthrough` - No-op

### Query Processing (portfolio_index/lib/portfolio_index/adapters/)
- `QueryRewriter.LLM` - Clean queries
- `QueryExpander.LLM` - Add synonyms
- `QueryDecomposer.LLM` - Break down complex
- `CollectionSelector.LLM` - Route to collections
- `CollectionSelector.RuleBased` - Pattern matching

### RAG Strategies (portfolio_index/lib/portfolio_index/rag/strategies/)
- `Hybrid` - Semantic + keyword
- `SelfRAG` - Self-critiquing
- `GraphRAG` - Graph-aware
- `Agentic` - Tool-using

### Manager Services (portfolio_manager/lib/portfolio_manager/)
- `RAG` - RAG interface
- `Router` - LLM routing
- `Agent` - Tool-using agent
- `Agent.Session` - Conversation state
- `Agent.Tool` - Tool definitions
- `Pipeline` - DAG workflows
- `Graph` - Graph interface
- `Evaluation` - RAG triad

---

## EXECUTION CHECKLIST

Each session, follow this checklist:

```
□ PHASE 0: REQUIRED READING
  □ Read DESIGN.md
  □ Read CLAUDE.md (all repos)
  □ Read CHANGELOG.md
  □ Run status assessment commands
  □ Check example status
  □ Update CLAUDE.md (pre-implementation)

□ PHASE 1: IMPLEMENTATION
  □ Identify next feature from CLAUDE.md
  □ Write failing tests (RED)
  □ Implement feature (GREEN)
  □ Refactor if needed
  □ Create/update example
  □ Run example successfully
  □ Run full test suite
  □ Fix any warnings/errors

□ PHASE 2: VALIDATION
  □ All repos compile without warnings
  □ All tests pass
  □ Dialyzer passes
  □ All examples run

□ PHASE 3: COMPLETION
  □ Update CLAUDE.md (post-implementation)
  □ Document session in history
  □ Note next steps
```

---

## SUCCESS CRITERIA

The implementation is complete when:

1. **All 15 examples run successfully**
2. **All tests pass across all 4 repos**
3. **Zero compilation warnings**
4. **Zero dialyzer errors**
5. **CLAUDE.md shows all phases complete**
6. **Each feature from DESIGN.md is implemented and demonstrated**

---

## NOTES FOR CLAUDE

- Work incrementally. Don't try to implement everything at once.
- Prioritize working examples over complete features.
- If blocked, document in CLAUDE.md and move to next feature.
- Cross-repo changes require running tests in all affected repos.
- When in doubt, write a test first.
- Examples are the proof that features work - they are mandatory.
- Update CLAUDE.md frequently to track progress.
- Each session should leave the codebase in a better state than found.
