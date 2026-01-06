# Portfolio Integration Design Document

**Version**: 0.4.0
**Date**: 2026-01-05
**Status**: Implementation

---

## 1. Overview

This document describes the integration of Portfolio Coder with the centralized Portfolio repository system. Portfolio Coder becomes the primary interface for managing project context, documentation, and code intelligence across multiple repository base directories.

### 1.1 Goals

1. **Centralized Context** - Use `~/p/g/n/portfolio` as the single source of truth for all project metadata
2. **Multi-Directory Support** - Scan and manage repos across multiple base directories
3. **RAG Integration** - Index portfolio docs and code for semantic search and Q&A
4. **Workflow Automation** - Port checking, doc generation, health checks
5. **CLI Interface** - Full CLI matching the portfolio design specification

### 1.2 Base Directories

The system supports multiple base directories for repository discovery:

```yaml
scan:
  directories:
    - ~/p/g/n
    - ~/p/g/North-Shore-AI
```

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        portfolio_coder v0.4.0                        │
├─────────────────────────────────────────────────────────────────────┤
│  Portfolio Layer (NEW)                                               │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌─────────────┐ │
│  │    Config    │ │   Registry   │ │   Context    │ │Relationships│ │
│  │  (config.yml)│ │(registry.yml)│ │(context.yml) │ │   (.yml)    │ │
│  └──────────────┘ └──────────────┘ └──────────────┘ └─────────────┘ │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌─────────────┐ │
│  │   Scanner    │ │   Syncer     │ │    Views     │ │  Workflows  │ │
│  │  (multi-dir) │ │  (git/fs)    │ │  (computed)  │ │  (port,doc) │ │
│  └──────────────┘ └──────────────┘ └──────────────┘ └─────────────┘ │
├─────────────────────────────────────────────────────────────────────┤
│  Code Intelligence Layer (EXISTING)                                  │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌─────────────┐ │
│  │   Indexer    │ │    Search    │ │    Graph     │ │    Tools    │ │
│  └──────────────┘ └──────────────┘ └──────────────┘ └─────────────┘ │
├─────────────────────────────────────────────────────────────────────┤
│  portfolio_manager → portfolio_index → portfolio_core               │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Data Model

### 3.1 Portfolio Repository Structure

```
~/p/g/n/portfolio/
├── config.yml                    # Global configuration
├── registry.yml                  # Master repo list
├── relationships.yml             # Inter-repo relationships
├── repos/                        # Per-repo context
│   └── {repo_id}/
│       ├── context.yml           # Structured metadata
│       ├── notes.md              # Free-form notes
│       └── docs/                 # Generated docs
└── docs/                         # Portfolio-level docs
```

### 3.2 Configuration Schema (config.yml)

```yaml
version: "1.0"

portfolio:
  name: "My Projects"
  owner: nshkrdotcom

scan:
  directories:
    - ~/p/g/n
    - ~/p/g/North-Shore-AI
  exclude_patterns:
    - "**/node_modules/**"
    - "**/.git/**"
    - "**/deps/**"
    - "**/_build/**"

sync:
  auto_commit: false
  auto_sync_interval: manual

defaults:
  new_repo:
    status: active
    priority: medium
```

### 3.3 Registry Schema (registry.yml)

```yaml
repos:
  - id: flowstone
    name: FlowStone
    path: /home/user/p/g/n/flowstone
    language: elixir
    type: library
    status: active
    remote_url: git@github.com:user/flowstone.git
    tags: []
    created_at: 2026-01-05T00:00:00Z
    updated_at: 2026-01-05T00:00:00Z
```

### 3.4 Context Schema (repos/{id}/context.yml)

```yaml
id: flowstone
name: FlowStone
path: ~/p/g/n/flowstone
language: elixir
type: library
status: active
priority: high

remotes:
  - url: git@github.com:user/flowstone.git
    name: origin
    is_primary: true

purpose: |
  Asset-first data orchestration for BEAM.

tags:
  - beam
  - data-pipeline

todos:
  - "Add S3 I/O manager"
  - "Write architecture docs"

port:  # Only if type: port
  upstream_url: https://github.com/original/project
  upstream_language: python
  last_synced_commit: abc123
  strategy: selective

computed:
  last_commit:
    sha: def456
    date: 2026-01-05
    message: "Latest commit"
  commit_count_30d: 15
  dependencies:
    runtime: [ecto, oban]
    dev: [credo, dialyxir]

created_at: 2026-01-05T00:00:00Z
updated_at: 2026-01-05T00:00:00Z
```

### 3.5 Relationships Schema (relationships.yml)

```yaml
relationships:
  - type: depends_on
    from: flowstone_ai
    to: flowstone
    auto_detected: true

  - type: port_of
    from: instructor_ex
    to: external:github.com/instructor-ai/instructor-py
    details:
      strategy: selective

  - type: related_to
    from: flowstone
    to: synapse
    details:
      reason: "Both NSAI platform components"
```

---

## 4. Module Design

### 4.1 PortfolioCoder.Portfolio.Config

Manages portfolio configuration and paths.

```elixir
defmodule PortfolioCoder.Portfolio.Config do
  @default_portfolio_path "~/p/g/n/portfolio"

  @spec portfolio_path() :: String.t()
  @spec load() :: {:ok, map()} | {:error, term()}
  @spec scan_directories() :: [String.t()]
  @spec exclude_patterns() :: [String.t()]
  @spec expand_path(String.t()) :: String.t()
end
```

### 4.2 PortfolioCoder.Portfolio.Registry

Manages the master repository list.

```elixir
defmodule PortfolioCoder.Portfolio.Registry do
  @type repo :: %{
    id: String.t(),
    name: String.t(),
    path: String.t(),
    language: atom(),
    type: atom(),
    status: atom(),
    remote_url: String.t() | nil,
    tags: [String.t()],
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  @spec list_repos(keyword()) :: {:ok, [repo()]} | {:error, term()}
  @spec get_repo(String.t()) :: {:ok, repo()} | {:error, :not_found}
  @spec add_repo(map()) :: {:ok, repo()} | {:error, term()}
  @spec update_repo(String.t(), map()) :: {:ok, repo()} | {:error, term()}
  @spec remove_repo(String.t()) :: :ok | {:error, term()}
  @spec filter_by(atom(), term()) :: {:ok, [repo()]} | {:error, term()}
  @spec save() :: :ok | {:error, term()}
end
```

### 4.3 PortfolioCoder.Portfolio.Context

Manages per-repo context files.

```elixir
defmodule PortfolioCoder.Portfolio.Context do
  @spec load(String.t()) :: {:ok, map()} | {:error, term()}
  @spec save(String.t(), map()) :: :ok | {:error, term()}
  @spec get_notes(String.t()) :: {:ok, String.t()} | {:error, term()}
  @spec save_notes(String.t(), String.t()) :: :ok | {:error, term()}
  @spec update_computed(String.t(), map()) :: :ok | {:error, term()}
  @spec ensure_repo_dir(String.t()) :: :ok | {:error, term()}
end
```

### 4.4 PortfolioCoder.Portfolio.Relationships

Manages inter-repo relationships.

```elixir
defmodule PortfolioCoder.Portfolio.Relationships do
  @type relationship :: %{
    type: atom(),
    from: String.t(),
    to: String.t(),
    auto_detected: boolean(),
    details: map()
  }

  @spec list(keyword()) :: {:ok, [relationship()]} | {:error, term()}
  @spec add(atom(), String.t(), String.t(), map()) :: {:ok, relationship()} | {:error, term()}
  @spec remove(String.t(), String.t()) :: :ok | {:error, term()}
  @spec get_for_repo(String.t()) :: {:ok, [relationship()]} | {:error, term()}
  @spec get_dependencies(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  @spec get_dependents(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  @spec save() :: :ok | {:error, term()}
end
```

### 4.5 PortfolioCoder.Portfolio.Scanner

Scans directories to discover repositories.

```elixir
defmodule PortfolioCoder.Portfolio.Scanner do
  @type scan_result :: %{
    path: String.t(),
    name: String.t(),
    language: atom() | nil,
    type: atom() | nil,
    remotes: [map()],
    is_new: boolean()
  }

  @spec scan(keyword()) :: {:ok, [scan_result()]} | {:error, term()}
  @spec scan_directory(String.t(), keyword()) :: {:ok, [scan_result()]} | {:error, term()}
  @spec detect_language(String.t()) :: atom() | nil
  @spec detect_type(String.t()) :: atom() | nil
  @spec extract_remotes(String.t()) :: [map()]
  @spec extract_dependencies(String.t(), atom()) :: map()
  @spec is_git_repo?(String.t()) :: boolean()
end
```

### 4.6 PortfolioCoder.Portfolio.Syncer

Syncs portfolio with actual repository state.

```elixir
defmodule PortfolioCoder.Portfolio.Syncer do
  @spec sync_all(keyword()) :: {:ok, map()} | {:error, term()}
  @spec sync_repo(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @spec update_computed_fields(String.t()) :: {:ok, map()} | {:error, term()}
  @spec get_git_info(String.t()) :: {:ok, map()} | {:error, term()}
end
```

---

## 5. CLI Commands

### 5.1 Command Overview

| Command | Description |
|---------|-------------|
| `mix portfolio.init` | Initialize portfolio repo |
| `mix portfolio.scan` | Discover repos in directories |
| `mix portfolio.add` | Add repo manually |
| `mix portfolio.remove` | Remove repo from tracking |
| `mix portfolio.list` | List repos with filters |
| `mix portfolio.show` | Show repo details |
| `mix portfolio.sync` | Sync with actual repos |
| `mix portfolio.search` | Search across portfolio |
| `mix portfolio.ask` | Natural language query |
| `mix portfolio.status` | Portfolio status summary |

### 5.2 Command Specifications

#### mix portfolio.list

```
mix portfolio.list [OPTIONS]

Options:
  --status, -s     Filter by status (active, stale, archived)
  --type, -t       Filter by type (library, application, port)
  --language, -l   Filter by language
  --tag            Filter by tag
  --json           Output as JSON
  --limit, -n      Limit results

Examples:
  mix portfolio.list
  mix portfolio.list --status=active --type=library
  mix portfolio.list --language=elixir --json
```

#### mix portfolio.show

```
mix portfolio.show <repo-id> [OPTIONS]

Options:
  --section        Show specific section (context, notes, deps)
  --json           Output as JSON

Examples:
  mix portfolio.show flowstone
  mix portfolio.show flowstone --section=notes
```

#### mix portfolio.scan

```
mix portfolio.scan [directories...] [OPTIONS]

Options:
  --add            Auto-add discovered repos
  --dry-run        Show what would be discovered

Examples:
  mix portfolio.scan
  mix portfolio.scan ~/p/g/n ~/p/g/North-Shore-AI
  mix portfolio.scan --dry-run
```

#### mix portfolio.sync

```
mix portfolio.sync [repo-id] [OPTIONS]

Options:
  --all            Sync all repos (default if no repo-id)
  --computed-only  Only update computed fields

Examples:
  mix portfolio.sync
  mix portfolio.sync flowstone
```

---

## 6. RAG Integration

### 6.1 Auto-Indexing

On startup, portfolio_coder indexes the portfolio repository for semantic search:

```elixir
# Indexes all markdown and yaml files in portfolio repo
PortfolioCoder.index_repo(portfolio_path,
  index_id: "portfolio_docs",
  languages: [:markdown, :yaml],
  exclude: [".git/", ".portfolio/"]
)
```

### 6.2 Portfolio-Aware Search

The `portfolio.ask` command combines:
1. Registry data (structured queries)
2. Portfolio docs (semantic search)
3. Optionally, code from tracked repos

```elixir
def ask_portfolio(question, opts \\ []) do
  context = %{
    registry: Registry.list_repos(),
    relationships: Relationships.list(),
    docs: Search.semantic_search(question, index_id: "portfolio_docs")
  }

  PortfolioManager.RAG.ask(question, context: context)
end
```

---

## 7. Testing Strategy

### 7.1 Test Structure

```
test/
├── portfolio_coder/
│   └── portfolio/
│       ├── config_test.exs
│       ├── registry_test.exs
│       ├── context_test.exs
│       ├── relationships_test.exs
│       ├── scanner_test.exs
│       └── syncer_test.exs
├── mix/tasks/
│   ├── portfolio.list_test.exs
│   ├── portfolio.show_test.exs
│   ├── portfolio.scan_test.exs
│   └── portfolio.sync_test.exs
└── support/
    └── portfolio_fixtures.ex
```

### 7.2 Test Fixtures

Tests use a temporary portfolio directory with fixture data:

```elixir
defmodule PortfolioCoder.PortfolioFixtures do
  def setup_test_portfolio do
    tmp_dir = System.tmp_dir!() |> Path.join("portfolio_test_#{:rand.uniform(10000)}")
    File.mkdir_p!(tmp_dir)

    # Create config.yml
    File.write!(Path.join(tmp_dir, "config.yml"), """
    version: "1.0"
    scan:
      directories:
        - #{tmp_dir}/repos
      exclude_patterns:
        - "**/node_modules/**"
    """)

    # Create registry.yml
    File.write!(Path.join(tmp_dir, "registry.yml"), """
    repos: []
    """)

    tmp_dir
  end

  def cleanup_test_portfolio(path) do
    File.rm_rf!(path)
  end
end
```

---

## 8. Examples

### 8.1 Live Examples

The `examples/` directory contains working scripts that operate on real data:

```
examples/
├── README.md
├── scan_repos.exs           # Scan and list all repos
├── show_portfolio_status.exs # Display portfolio status
├── search_portfolio.exs     # Search across docs and code
├── sync_all_repos.exs       # Sync all repo metadata
└── find_stale_repos.exs     # Find repos needing attention
```

### 8.2 Example: scan_repos.exs

```elixir
#!/usr/bin/env elixir

# Scan all base directories and display discovered repos

Mix.install([{:portfolio_coder, path: "."}])

alias PortfolioCoder.Portfolio.{Config, Scanner, Registry}

IO.puts("Scanning repositories...\n")

directories = Config.scan_directories()
IO.puts("Base directories: #{inspect(directories)}\n")

{:ok, results} = Scanner.scan()

new_repos = Enum.filter(results, & &1.is_new)
existing = Enum.reject(results, & &1.is_new)

IO.puts("Found #{length(results)} repositories:")
IO.puts("  New: #{length(new_repos)}")
IO.puts("  Already tracked: #{length(existing)}\n")

if length(new_repos) > 0 do
  IO.puts("New repositories:")
  for repo <- new_repos do
    IO.puts("  #{repo.name} (#{repo.language || "unknown"}) - #{repo.path}")
  end
end
```

---

## 9. Implementation Phases

### Phase 1: Core Data Layer
- [x] Design document
- [ ] Portfolio.Config
- [ ] Portfolio.Registry
- [ ] Portfolio.Context
- [ ] Portfolio.Relationships

### Phase 2: Discovery & Sync
- [ ] Portfolio.Scanner
- [ ] Portfolio.Syncer

### Phase 3: CLI Commands
- [ ] mix portfolio.list
- [ ] mix portfolio.show
- [ ] mix portfolio.scan
- [ ] mix portfolio.add
- [ ] mix portfolio.remove
- [ ] mix portfolio.sync
- [ ] mix portfolio.status

### Phase 4: RAG Integration
- [ ] Auto-index portfolio docs
- [ ] mix portfolio.search
- [ ] mix portfolio.ask

### Phase 5: Examples & Documentation
- [ ] examples/README.md
- [ ] Working examples
- [ ] README.md updates
- [ ] CHANGELOG.md

---

## 10. Configuration Reference

### 10.1 Application Config

```elixir
# config/config.exs

config :portfolio_coder,
  # Portfolio repository location
  portfolio_path: System.get_env("PORTFOLIO_DIR", "~/p/g/n/portfolio"),

  # Auto-index portfolio on startup
  auto_index_portfolio: true,
  portfolio_index_id: "portfolio_docs",

  # Existing code intelligence config
  default_index: "default",
  default_graph: "dependencies",
  supported_languages: [:elixir, :python, :javascript, :typescript],
  chunk_size: 1000,
  chunk_overlap: 200
```

### 10.2 Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORTFOLIO_DIR` | Portfolio repo location | `~/p/g/n/portfolio` |
| `PORTFOLIO_AUTO_INDEX` | Auto-index on startup | `true` |

---

## 11. Error Handling

### 11.1 Error Types

```elixir
defmodule PortfolioCoder.Portfolio.Error do
  defexception [:message, :type]

  @type t :: %__MODULE__{
    message: String.t(),
    type: :not_found | :invalid_config | :parse_error | :write_error
  }
end
```

### 11.2 Common Errors

| Error | Cause | Resolution |
|-------|-------|------------|
| `:portfolio_not_found` | Portfolio dir doesn't exist | Run `mix portfolio.init` |
| `:invalid_yaml` | YAML parse error | Check file syntax |
| `:repo_not_found` | Repo ID not in registry | Verify repo ID |
| `:path_not_found` | Repo path doesn't exist | Update or remove repo |

---

## 12. Future Enhancements

### 12.1 Planned Features

1. **Agentic Detection** - LLM-powered purpose/relationship inference
2. **Port Workflows** - Automated port checking and sync
3. **Doc Generation** - AI-generated documentation
4. **Interactive Mode** - REPL interface
5. **Views** - Auto-generated computed views

### 12.2 Integration Points

- **Claude Code** - Context injection for AI coding
- **VSCode Extension** - Editor integration
- **GitHub Actions** - CI/CD workflows
