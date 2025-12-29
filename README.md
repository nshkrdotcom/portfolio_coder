<p align="center">
  <img src="assets/portfolio_coder.svg" alt="Portfolio Coder Logo" width="200">
</p>

<h1 align="center">Portfolio Coder</h1>

<p align="center">
  <strong>Code Intelligence Platform built on the Portfolio RAG Ecosystem</strong>
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/portfolio_coder/actions"><img src="https://github.com/nshkrdotcom/portfolio_coder/workflows/CI/badge.svg" alt="CI Status"></a>
  <a href="https://hex.pm/packages/portfolio_coder"><img src="https://img.shields.io/hexpm/v/portfolio_coder.svg" alt="Hex.pm"></a>
  <a href="https://hexdocs.pm/portfolio_coder"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="Documentation"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License"></a>
</p>

---

## Overview

Portfolio Coder is a code intelligence platform that provides:

- **Repository Indexing** - Scan and index code repositories with multi-language support
- **Semantic Code Search** - Find code by meaning, not just keywords
- **Dependency Graphs** - Visualize and query code dependencies
- **AI-Powered Analysis** - Code review, refactoring suggestions, and documentation generation
- **Intelligent Agents** - Tool-using agents for complex code tasks

Built on the [Portfolio RAG Ecosystem](https://github.com/nshkrdotcom/portfolio_core), it leverages:
- **portfolio_core** - Hexagonal architecture foundation
- **portfolio_index** - Vector storage, LLM adapters, RAG strategies
- **portfolio_manager** - Generic intelligence orchestration layer

## Features

### Multi-Language Support

| Language | Parsing | Dependencies | Call Graph |
|----------|---------|--------------|------------|
| Elixir | AST via Sourceror | mix.exs | Function calls |
| Python | Basic | requirements.txt | Imports |
| JavaScript/TypeScript | Basic | package.json | Imports |

### Code Intelligence

- **Semantic Search** - Find code by natural language queries
- **Symbol Navigation** - Jump to definitions, find references
- **Dependency Analysis** - Identify circular dependencies, impact analysis
- **Code Review** - AI-assisted review with context from codebase

## Installation

Add `portfolio_coder` to your dependencies:

```elixir
def deps do
  [
    {:portfolio_coder, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Index a Repository

```bash
mix code.index /path/to/repo --index my_project
```

### 2. Search Code

```bash
mix code.search "authentication middleware" --index my_project
```

### 3. Ask Questions

```bash
mix code.ask "How does authentication work?" --index my_project
```

### 4. Analyze Dependencies

```bash
mix code.deps build /path/to/repo --graph my_deps
```

## Programmatic Usage

```elixir
# Index a repository
{:ok, stats} = PortfolioCoder.index_repo("/path/to/repo",
  index_id: "my_project",
  languages: [:elixir, :python]
)

# Semantic code search
{:ok, results} = PortfolioCoder.search_code("database connection",
  index_id: "my_project",
  limit: 10
)

# Ask questions about the codebase
{:ok, answer} = PortfolioCoder.ask("How does caching work?",
  index_id: "my_project"
)

# Build dependency graph
{:ok, graph} = PortfolioCoder.build_dependency_graph("deps", "/path/to/repo")
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     portfolio_coder                         │
│  CLI | Indexer | Search | Graph | Tools | Parsers           │
├─────────────────────────────────────────────────────────────┤
│                   portfolio_manager                         │
│  Generic: RAG | Router | Agent | Pipeline                   │
├─────────────────────────────────────────────────────────────┤
│                    portfolio_index                          │
│  Adapters: Pgvector | Neo4j | Gemini | Claude               │
├─────────────────────────────────────────────────────────────┤
│                    portfolio_core                           │
│  Foundation: Ports | Registry | Manifest | Telemetry        │
└─────────────────────────────────────────────────────────────┘
```

## Development

```bash
git clone https://github.com/nshkrdotcom/portfolio_coder.git
cd portfolio_coder
mix deps.get
mix test
```

## License

MIT License - see [LICENSE](LICENSE) for details.
