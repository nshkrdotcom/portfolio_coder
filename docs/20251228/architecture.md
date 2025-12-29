# Portfolio Coder Architecture

## Overview

Portfolio Coder is a code intelligence platform built on top of the Portfolio RAG ecosystem. It provides domain-specific functionality for understanding, indexing, and querying codebases.

## Architecture Diagram

```
+------------------+
|  Mix CLI Tasks   |  code.index, code.search, code.ask, code.deps
+------------------+
         |
+------------------+
|  PortfolioCoder  |  Main API module
+------------------+
         |
+--------+--------+--------+--------+
|        |        |        |        |
v        v        v        v        v
+------+ +------+ +------+ +------+ +------+
|Indexer| |Search| |Graph | |Tools | |Parsers|
+------+ +------+ +------+ +------+ +------+
         |        |                  |
         v        v                  v
+------------------+          +------------------+
| PortfolioManager |          | Language Parsers |
|   (RAG Layer)    |          | Elixir/Python/JS |
+------------------+          +------------------+
         |
+------------------+
| PortfolioIndex   |
| (Vector Store)   |
+------------------+
```

## Core Modules

### PortfolioCoder (Main API)

The main entry point providing a clean, user-friendly API:

- `index_repo/2` - Index a code repository
- `index_files/2` - Index specific files
- `search_code/2` - Semantic code search
- `search_text/2` - Text-based search
- `ask/2` - RAG-powered Q&A
- `stream_ask/3` - Streaming Q&A
- `build_dependency_graph/3` - Build dependency graphs
- `get_dependencies/3` - Query dependencies
- `get_dependents/3` - Query reverse dependencies
- `find_cycles/1` - Detect circular dependencies

### Indexer

Handles repository scanning and indexing:

1. **File Discovery**: Scans repos using configurable patterns
2. **Language Detection**: Automatically detects file languages
3. **Parsing**: Extracts structural information
4. **Chunking**: Prepares content for embedding
5. **Storage**: Delegates to PortfolioManager.RAG

### Parsers

Language-specific AST/structure extraction:

- **Elixir Parser**: Uses Sourceror for proper AST parsing
  - Modules, functions, macros
  - Imports, aliases, uses
  - Module attributes

- **Python Parser**: Regex-based extraction
  - Classes, functions, decorators
  - Imports (import/from-import)
  - Docstrings

- **JavaScript Parser**: Regex-based extraction
  - Classes, functions, arrow functions
  - ES6 imports/exports
  - TypeScript interfaces and types

### Graph

Dependency graph building and analysis:

- **Dependency.build/4**: Extracts and stores dependencies
- **get_dependencies/3**: Forward dependency traversal
- **get_dependents/3**: Reverse dependency traversal
- **find_cycles/1**: Circular dependency detection

Supports:
- Elixir (mix.exs)
- Python (requirements.txt, pyproject.toml)
- JavaScript (package.json)

### Tools

Agent-compatible tools for code intelligence:

- **SearchCode**: Semantic code search
- **ReadFile**: Safe file reading with line ranges
- **ListFiles**: Directory listing with filters
- **AnalyzeCode**: Structural and complexity analysis

## Data Flow

### Indexing Flow

```
Repository
    |
    v
[Indexer.scan_files/3]
    |
    v
[Parser.parse/1] - Extract structure
    |
    v
[Chunking] - Split content
    |
    v
[PortfolioManager.RAG.index_repo/2]
    |
    v
Vector Store (via PortfolioIndex)
```

### Search Flow

```
Query
    |
    v
[PortfolioCoder.search_code/2]
    |
    v
[PortfolioManager.RAG.retrieve/2]
    |
    v
[Vector similarity search]
    |
    v
Results with code context
```

### Q&A Flow

```
Question
    |
    v
[PortfolioCoder.ask/2]
    |
    v
[PortfolioManager.RAG.query/2]
    |
    +-> Retrieve relevant chunks
    |
    +-> Build prompt with context
    |
    +-> LLM generation
    |
    v
Answer
```

## Configuration

```elixir
config :portfolio_coder,
  default_index: "default",
  supported_languages: [:elixir, :python, :javascript],
  chunk_size: 1000,
  chunk_overlap: 200
```

## Extension Points

1. **New Language Parsers**: Add to `lib/portfolio_coder/parsers/`
2. **New Tools**: Add to `lib/portfolio_coder/tools/`
3. **Custom Indexing**: Override chunking strategies
4. **Graph Analysis**: Extend dependency detection

## Design Decisions

### Why Regex for Python/JS?

- No runtime dependency on external parsers
- Fast execution for common patterns
- Sufficient for structural extraction (not full analysis)
- Easy to maintain and extend

### Why Sourceror for Elixir?

- Native Elixir parsing with proper AST
- Handles all edge cases correctly
- Preserves source positions
- Supports macros and complex syntax

### Layered Architecture

- **PortfolioCoder**: Domain-specific (code intelligence)
- **PortfolioManager**: Generic RAG/Agent layer
- **PortfolioIndex**: Generic vector storage
- **PortfolioCore**: Shared utilities

This separation allows:
- Independent evolution
- Clear responsibilities
- Reusable components
- Testable modules
