<p align="center">
  <img src="assets/portfolio_coder.svg" alt="Portfolio Coder Logo" width="200">
</p>

<h1 align="center">Portfolio Coder</h1>

<p align="center">
  <strong>Code Intelligence Platform & Project Portfolio Management</strong>
</p>

<p align="center">
  <a href="https://github.com/nshkrdotcom/portfolio_coder/actions"><img src="https://github.com/nshkrdotcom/portfolio_coder/workflows/CI/badge.svg" alt="CI Status"></a>
  <a href="https://hex.pm/packages/portfolio_coder"><img src="https://img.shields.io/hexpm/v/portfolio_coder.svg" alt="Hex.pm"></a>
  <a href="https://hexdocs.pm/portfolio_coder"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="Documentation"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License"></a>
</p>

---

## Overview

Portfolio Coder is a code intelligence platform that combines:

- **Repository Indexing** - Scan and index code repositories with multi-language support
- **Semantic Code Search** - Find code by meaning, not just keywords
- **Portfolio Management** - Track and manage all your projects from a central repository
- **Dependency Analysis** - Visualize and query code dependencies
- **AI-Powered Analysis** - Code review, refactoring suggestions, and documentation generation

Built on the [Portfolio RAG Ecosystem](https://github.com/nshkrdotcom/portfolio_core).

## New in v0.4.0: Portfolio Integration

Manage all your projects from a centralized portfolio repository:

```bash
# Scan multiple directories for repositories
mix portfolio.scan ~/p/g/n ~/p/g/North-Shore-AI

# List all tracked repos
mix portfolio.list --status=active --language=elixir

# Show detailed info about a repo
mix portfolio.show flowstone

# Sync metadata with actual repo state
mix portfolio.sync
```

### Portfolio Features

- **Multi-Directory Scanning** - Discover repos across multiple base directories
- **Centralized Context** - Store metadata, notes, and decisions in one place
- **Relationship Tracking** - Track dependencies between your repositories
- **Status Management** - Track active, stale, blocked, and archived repos
- **Auto-Detection** - Automatically detect language, type, and dependencies

## Installation

Add `portfolio_coder` to your dependencies:

```elixir
def deps do
  [
    {:portfolio_coder, "~> 0.4.0"}
  ]
end
```

## Quick Start

### Portfolio Management

```bash
# Initialize or configure portfolio location
export PORTFOLIO_DIR=~/p/g/n/portfolio

# Scan for repos
mix portfolio.scan

# Add repos to tracking
mix portfolio.scan --add

# View portfolio status
mix portfolio.status

# List repos by language
mix portfolio.list --language=elixir

# Show repo details
mix portfolio.show my_project
```

### Code Intelligence

```bash
# Index a repository
mix code.index /path/to/repo --index my_project

# Search code
mix code.search "authentication middleware" --index my_project

# Ask questions
mix code.ask "How does authentication work?" --index my_project

# Analyze dependencies
mix code.deps build /path/to/repo --graph my_deps
```

## Portfolio Structure

Portfolio Coder uses a centralized repository to store project context:

```
~/p/g/n/portfolio/
├── config.yml              # Configuration (scan dirs, settings)
├── registry.yml            # Master list of tracked repos
├── relationships.yml       # Inter-repo relationships
└── repos/
    └── {repo_id}/
        ├── context.yml     # Repo metadata and context
        ├── notes.md        # Free-form notes
        └── docs/           # Generated documentation
```

### Configuration Example

```yaml
# config.yml
version: "1.0"

scan:
  directories:
    - ~/p/g/n
    - ~/p/g/North-Shore-AI
  exclude_patterns:
    - "**/node_modules/**"
    - "**/deps/**"
```

## CLI Commands

### Portfolio Commands

| Command | Description |
|---------|-------------|
| `mix portfolio.scan` | Discover repos in directories |
| `mix portfolio.list` | List tracked repos with filters |
| `mix portfolio.show <id>` | Show repo details |
| `mix portfolio.add <path>` | Add repo to tracking |
| `mix portfolio.remove <id>` | Remove repo from tracking |
| `mix portfolio.sync` | Sync with actual repo state |
| `mix portfolio.status` | Show portfolio summary |

### Code Intelligence Commands

| Command | Description |
|---------|-------------|
| `mix code.index` | Index repositories |
| `mix code.search` | Search indexed code |
| `mix code.ask` | Ask questions about code |
| `mix code.deps` | Dependency analysis |

## Programmatic Usage

```elixir
# Portfolio Management
alias PortfolioCoder.Portfolio.{Registry, Scanner, Context}

# List all repos
{:ok, repos} = Registry.list_repos()

# Filter by language
{:ok, elixir_repos} = Registry.filter_by(:language, :elixir)

# Scan for new repos
{:ok, discovered} = Scanner.scan()

# Get repo context
{:ok, context} = Context.load("my_repo")

# Code Intelligence
{:ok, stats} = PortfolioCoder.index_repo("/path/to/repo",
  index_id: "my_project",
  languages: [:elixir, :python]
)

{:ok, results} = PortfolioCoder.search_code("database connection",
  index_id: "my_project",
  limit: 10
)

{:ok, answer} = PortfolioCoder.ask("How does caching work?",
  index_id: "my_project"
)
```

## Multi-Language Support

| Language | Parsing | Dependencies | Detection |
|----------|---------|--------------|-----------|
| Elixir | AST via Sourceror | mix.exs | Full |
| Python | Regex-based | requirements.txt, pyproject.toml | Full |
| JavaScript/TypeScript | Regex-based | package.json | Full |
| Rust | Marker detection | Cargo.toml | Basic |
| Go | Marker detection | go.mod | Basic |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     portfolio_coder                          │
│  Portfolio | CLI | Indexer | Search | Graph | Tools         │
├─────────────────────────────────────────────────────────────┤
│                   portfolio_manager                          │
│  Generic: RAG | Router | Agent | Pipeline                    │
├─────────────────────────────────────────────────────────────┤
│                    portfolio_index                           │
│  Adapters: Pgvector | Neo4j | Gemini | Claude               │
├─────────────────────────────────────────────────────────────┤
│                    portfolio_core                            │
│  Foundation: Ports | Registry | Manifest | Telemetry        │
└─────────────────────────────────────────────────────────────┘
```

## Examples

Working examples are provided in the `examples/` directory:

```bash
# Scan and list repos
mix run examples/scan_repos.exs

# Show portfolio status
mix run examples/show_portfolio_status.exs

# Find stale repos
mix run examples/find_stale_repos.exs

# Sync all repos
mix run examples/sync_all_repos.exs
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
