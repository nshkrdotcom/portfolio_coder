# Portfolio Coder Examples Guide

A comprehensive guide to the example scripts, tracing through all four portfolio libraries to show how features work end-to-end.

## Architecture Overview

The Portfolio ecosystem consists of four libraries that work together:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         portfolio_coder (v0.4.0)                        │
│  Code Intelligence Platform - Repository analysis, semantic search     │
│  This is the main application layer you interact with                  │
├─────────────────────────────────────────────────────────────────────────┤
│                           portfolio_manager                             │
│  Data Management Layer - CRUD operations, sync, telemetry              │
├─────────────────────────────────────────────────────────────────────────┤
│                            portfolio_index                              │
│  Search & Indexing Layer - Embeddings, vector search, rate limiting   │
├─────────────────────────────────────────────────────────────────────────┤
│                             portfolio_core                              │
│  Foundation Layer - Shared types, protocols, utilities                 │
└─────────────────────────────────────────────────────────────────────────┘
```

### Library Responsibilities

| Library | Purpose | Key Features |
|---------|---------|--------------|
| **portfolio_core** | Foundation | Shared types, Result types, Configuration protocols, Common utilities |
| **portfolio_index** | Indexing | Embeddings pipeline, Vector search, Rate limiting (ETS-based), Telemetry |
| **portfolio_manager** | Management | Repository CRUD, Sync operations, Relationship management |
| **portfolio_coder** | Application | CLI tools, Example scripts, Portfolio integration modules |

### Dependency Flow

```elixir
# mix.exs - portfolio_coder dependencies
{:portfolio_manager, path: "../portfolio_manager", override: true},
{:portfolio_index, path: "../portfolio_index", override: true},
{:portfolio_core, path: "../portfolio_core", override: true}
```

---

## Persistence Layer

All portfolio data is stored in YAML files within the portfolio directory:

### Directory Structure

```
~/p/g/n/portfolio/
├── config.yml          # Portfolio configuration
├── registry.yml        # Master list of tracked repositories
├── relationships.yml   # Inter-repository relationships
└── repos/              # Per-repository context
    ├── flowstone/
    │   ├── context.yml # Structured metadata
    │   └── notes.md    # Free-form notes
    └── portfolio_coder/
        ├── context.yml
        └── notes.md
```

### Data Structures

#### config.yml
```yaml
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
version: 1.0
```

**Access via Config module:**
```elixir
Config.scan_directories()     # => ["/home/user/p/g/n", "/home/user/p/g/North-Shore-AI"]
Config.exclude_patterns()     # => ["**/node_modules/**", ...]
Config.portfolio_path()       # => "/home/user/p/g/n/portfolio"
```

#### registry.yml
```yaml
repos:
  - id: flowstone
    name: FlowStone
    path: /home/user/p/g/n/flowstone
    language: elixir
    type: library
    status: active
    remote_url: git@github.com:user/flowstone.git
    tags: [beam, data]
    created_at: 2026-01-05T00:00:00Z
    updated_at: 2026-01-05T00:00:00Z
```

**Repo struct:**
```elixir
%{
  id: String.t(),           # Unique slug identifier
  name: String.t(),         # Display name
  path: String.t(),         # Absolute filesystem path
  language: atom(),         # :elixir | :python | :javascript | :rust | :go | etc.
  type: atom(),             # :library | :application | :port | :unknown
  status: atom(),           # :active | :stale | :archived | :blocked
  remote_url: String.t(),   # Git remote URL (or nil)
  tags: [String.t()],       # User-defined tags
  created_at: DateTime.t(),
  updated_at: DateTime.t()
}
```

#### relationships.yml
```yaml
relationships:
  - type: depends_on
    from: flowstone_ai
    to: flowstone
    auto_detected: true
    details:
      dependency_type: runtime
```

**Relationship types:**
- `:depends_on` - From uses To as a dependency
- `:port_of` - From is a port of To (different language)
- `:evolved_from` - From is a rewrite/evolution of To
- `:related_to` - From and To are conceptually related
- `:forked_from` - From is a git fork of To
- `:supersedes` - From replaces To
- `:alternative_to` - From is an alternative to To
- `:contains` - From contains To as a submodule

#### context.yml (per-repo)
```yaml
id: flowstone
name: FlowStone
path: ~/p/g/n/flowstone
language: elixir
type: library
status: active
purpose: Asset-first orchestration
todos:
  - Add S3 I/O
  - Write docs
computed:
  last_commit:
    sha: abc12345
    message: Fix rate limiter
    date: 2026-01-05
  commit_count_30d: 42
  current_branch: main
  dependencies:
    runtime:
      - phoenix
      - ecto
    dev:
      - ex_doc
      - credo
```

---

## Module Reference

### Config Module
**Location:** `lib/portfolio_coder/portfolio/config.ex`

Manages portfolio configuration and path resolution.

| Function | Signature | Description |
|----------|-----------|-------------|
| `portfolio_path/0` | `() -> String.t()` | Returns expanded portfolio path |
| `expand_path/1` | `(String.t()) -> String.t()` | Expands ~ to home directory |
| `exists?/0` | `() -> boolean()` | Checks if portfolio exists |
| `load/0` | `() -> {:ok, map()} \| {:error, term()}` | Loads config.yml |
| `scan_directories/0` | `() -> [String.t()]` | Returns directories to scan |
| `exclude_patterns/0` | `() -> [String.t()]` | Returns exclude patterns |
| `get/2` | `([String.t()], term()) -> {:ok, term()} \| {:error, :not_found}` | Gets nested config value |
| `repos_path/0` | `() -> String.t()` | Path to repos/ directory |
| `registry_path/0` | `() -> String.t()` | Path to registry.yml |
| `relationships_path/0` | `() -> String.t()` | Path to relationships.yml |

**Configuration sources (priority order):**
1. `PORTFOLIO_DIR` environment variable
2. `config :portfolio_coder, portfolio_path: "..."` in config.exs
3. Default: `~/p/g/n/portfolio`

### Registry Module
**Location:** `lib/portfolio_coder/portfolio/registry.ex`

CRUD operations for the repository registry.

| Function | Signature | Description |
|----------|-----------|-------------|
| `list_repos/1` | `(keyword()) -> {:ok, [repo()]} \| {:error, term()}` | Lists all repos (opts: :limit) |
| `get_repo/1` | `(String.t()) -> {:ok, repo()} \| {:error, :not_found}` | Gets repo by ID |
| `add_repo/1` | `(map()) -> {:ok, repo()} \| {:error, term()}` | Adds new repo |
| `update_repo/2` | `(String.t(), map()) -> {:ok, repo()} \| {:error, term()}` | Updates repo |
| `remove_repo/1` | `(String.t()) -> :ok \| {:error, term()}` | Removes repo |
| `filter_by/2` | `(atom(), term()) -> {:ok, [repo()]} \| {:error, term()}` | Filters by field |

**Internal flow:**
```
add_repo(attrs)
  │
  ├─→ validate_id(attrs)        # Ensure id present
  ├─→ validate_unique(id)       # Check not already exists
  ├─→ build_repo(attrs)         # Build repo struct with timestamps
  └─→ add_to_registry(repo)
        │
        ├─→ load_registry()     # Read registry.yml via YamlElixir
        ├─→ Append repo
        └─→ save_registry()     # Write YAML back to file
```

### Scanner Module
**Location:** `lib/portfolio_coder/portfolio/scanner.ex`

Discovers and analyzes repositories in configured directories.

| Function | Signature | Description |
|----------|-----------|-------------|
| `scan/1` | `(keyword()) -> {:ok, [scan_result()]}` | Scans all directories |
| `scan_directory/2` | `(String.t(), keyword()) -> {:ok, [scan_result()]} \| {:error, term()}` | Scans single directory |
| `detect_language/1` | `(String.t()) -> atom() \| nil` | Detects primary language |
| `detect_type/1` | `(String.t()) -> atom() \| nil` | Detects repo type |
| `extract_remotes/1` | `(String.t()) -> [map()]` | Gets git remotes |
| `git_repo?/1` | `(String.t()) -> boolean()` | Checks if git repo |
| `extract_dependencies/2` | `(String.t(), atom()) -> %{runtime: [...], dev: [...]}` | Extracts deps |

**Language detection markers:**
```elixir
@language_markers %{
  "mix.exs"          => :elixir,
  "rebar.config"     => :erlang,
  "requirements.txt" => :python,
  "setup.py"         => :python,
  "pyproject.toml"   => :python,
  "package.json"     => :javascript,
  "Cargo.toml"       => :rust,
  "go.mod"           => :go,
  "Gemfile"          => :ruby,
  "pom.xml"          => :java,
  "build.gradle"     => :java
}
```

**scan_result struct:**
```elixir
%{
  path: String.t(),           # Absolute path
  name: String.t(),           # Directory name
  language: atom() | nil,     # Detected language
  type: atom() | nil,         # Detected type
  remotes: [%{name: _, url: _}],  # Git remotes
  is_new: boolean()           # Not in registry yet
}
```

### Context Module
**Location:** `lib/portfolio_coder/portfolio/context.ex`

Manages per-repository context files.

| Function | Signature | Description |
|----------|-----------|-------------|
| `load/1` | `(String.t()) -> {:ok, map()} \| {:error, term()}` | Loads context.yml |
| `save/2` | `(String.t(), map()) -> :ok \| {:error, term()}` | Saves context.yml |
| `get_notes/1` | `(String.t()) -> {:ok, String.t()} \| {:error, term()}` | Gets notes.md |
| `save_notes/2` | `(String.t(), String.t()) -> :ok \| {:error, term()}` | Saves notes.md |
| `update_field/3` | `(String.t(), String.t(), term()) -> :ok \| {:error, term()}` | Updates single field |
| `get_field/2` | `(String.t(), String.t()) -> {:ok, term()} \| {:error, term()}` | Gets single field |
| `update_computed/2` | `(String.t(), map()) -> :ok \| {:error, term()}` | Updates computed fields |
| `ensure_repo_dir/1` | `(String.t()) -> :ok \| {:error, term()}` | Creates repo directory |

**File paths:**
```elixir
repo_dir_path(repo_id)     # ~/p/g/n/portfolio/repos/{repo_id}/
context_file_path(repo_id) # ~/p/g/n/portfolio/repos/{repo_id}/context.yml
notes_file_path(repo_id)   # ~/p/g/n/portfolio/repos/{repo_id}/notes.md
```

### Relationships Module
**Location:** `lib/portfolio_coder/portfolio/relationships.ex`

Manages inter-repository relationships.

| Function | Signature | Description |
|----------|-----------|-------------|
| `list/1` | `(keyword()) -> {:ok, [relationship()]} \| {:error, term()}` | Lists all relationships |
| `add/4` | `(atom(), String.t(), String.t(), map()) -> {:ok, relationship()} \| {:error, term()}` | Adds relationship |
| `remove/2` | `(String.t(), String.t()) -> :ok \| {:error, term()}` | Removes relationships between repos |
| `get_for_repo/1` | `(String.t()) -> {:ok, [relationship()]} \| {:error, term()}` | Gets all relationships for repo |
| `get_dependencies/1` | `(String.t()) -> {:ok, [String.t()]} \| {:error, term()}` | Gets repos this depends on |
| `get_dependents/1` | `(String.t()) -> {:ok, [String.t()]} \| {:error, term()}` | Gets repos that depend on this |
| `filter_by_type/1` | `(atom()) -> {:ok, [relationship()]} \| {:error, term()}` | Filters by relationship type |

### Syncer Module
**Location:** `lib/portfolio_coder/portfolio/syncer.ex`

Syncs portfolio with actual repository state.

| Function | Signature | Description |
|----------|-----------|-------------|
| `sync_all/1` | `(keyword()) -> {:ok, map()} \| {:error, term()}` | Syncs all repos |
| `sync_repo/2` | `(String.t(), keyword()) -> {:ok, map()} \| {:error, term()}` | Syncs single repo |
| `update_computed_fields/1` | `(String.t()) -> {:ok, map()} \| {:error, term()}` | Updates computed fields |
| `get_git_info/1` | `(String.t()) -> {:ok, map()} \| {:error, term()}` | Extracts git info |

**sync_all result:**
```elixir
%{
  synced: integer(),          # Count of successfully synced
  failed: integer(),          # Count of failures
  errors: [{:error, id, reason}],  # Error details
  total: integer()            # Total repos processed
}
```

**Computed fields extracted:**
- `last_commit` - `%{sha: _, message: _, date: _}`
- `commit_count_30d` - Integer count of commits in last 30 days
- `current_branch` - String branch name
- `dependencies` - `%{runtime: [...], dev: [...]}`

---

## Example Scripts

### 1. scan_repos.exs

**Purpose:** Discover new repositories in configured directories.

**Usage:**
```bash
mix run examples/scan_repos.exs
```

**Code Flow:**

```
┌────────────────────────────────────────────────────────────────────────┐
│ scan_repos.exs                                                         │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  1. Config.scan_directories()                                          │
│     │                                                                  │
│     ├─→ Config.load()                                                  │
│     │   └─→ File.read(config.yml)                                      │
│     │   └─→ YamlElixir.read_from_string()                              │
│     │                                                                  │
│     └─→ get_in(config, ["scan", "directories"])                        │
│         └─→ Enum.map(&Config.expand_path/1)  # Expand ~ to home dir    │
│                                                                        │
│  2. Scanner.scan()                                                     │
│     │                                                                  │
│     ├─→ Registry.list_repos()  # Get existing repos                    │
│     │   └─→ MapSet.new(paths)  # For is_new comparison                 │
│     │                                                                  │
│     └─→ for each directory:                                            │
│         │                                                              │
│         ├─→ scan_directory(expanded_path, exclude: patterns)           │
│         │   │                                                          │
│         │   ├─→ File.ls!(directory)                                    │
│         │   ├─→ Enum.filter(&File.dir?/1)                              │
│         │   ├─→ Enum.reject(&excluded?/2)                              │
│         │   ├─→ Enum.filter(&git_repo?/1)                              │
│         │   │   └─→ File.dir?(Path.join(path, ".git"))                 │
│         │   │                                                          │
│         │   └─→ Enum.map(&build_scan_result/1)                         │
│         │       │                                                      │
│         │       ├─→ detect_language(path)                              │
│         │       │   └─→ Check for marker files (mix.exs, etc.)         │
│         │       │                                                      │
│         │       ├─→ detect_type(path)                                  │
│         │       │   └─→ Check for Phoenix, mod:, escript:, etc.        │
│         │       │                                                      │
│         │       └─→ extract_remotes(path)                              │
│         │           └─→ System.cmd("git", ["remote", "-v"])            │
│         │                                                              │
│         └─→ Map.put(result, :is_new, path not in existing_paths)       │
│                                                                        │
│  3. Display Results                                                    │
│     ├─→ Enum.filter(results, & &1.is_new)                              │
│     ├─→ Enum.group_by(& &1.language)                                   │
│     └─→ Print statistics and new repos                                 │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

**Key Parameters:**

| Variable | Source | Type |
|----------|--------|------|
| `directories` | config.yml → scan.directories | `[String.t()]` |
| `exclude_patterns` | config.yml → scan.exclude_patterns | `[String.t()]` |
| `existing_paths` | registry.yml → repos[].path | `MapSet.t()` |

**System Commands Used:**
```elixir
# Extract git remotes
System.cmd("git", ["remote", "-v"], cd: repo_path, stderr_to_stdout: true)
# Output: "origin\tgit@github.com:user/repo.git (fetch)\n..."
```

**Output Example:**
```
Portfolio Repository Scanner
==================================================

Scanning 2 directories:
  - /home/user/p/g/n (exists)
  - /home/user/p/g/North-Shore-AI (exists)

Found 207 repositories:
  New (not tracked):    207
  Already tracked:      0

By Language:
  elixir: 137
  unknown: 59
  python: 7
  javascript: 4

New repositories (not yet tracked):

  flowstone
    Language: elixir, Type: library
    Path: /home/user/p/g/n/flowstone
    Remote: git@github.com:user/flowstone.git
```

---

### 2. show_portfolio_status.exs

**Purpose:** Display comprehensive portfolio status report.

**Usage:**
```bash
mix run examples/show_portfolio_status.exs
```

**Code Flow:**

```
┌────────────────────────────────────────────────────────────────────────┐
│ show_portfolio_status.exs                                              │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  1. Portfolio Info                                                     │
│     │                                                                  │
│     ├─→ Config.portfolio_path()                                        │
│     │   └─→ System.get_env("PORTFOLIO_DIR") ||                         │
│     │       Application.get_env(:portfolio_coder, :portfolio_path) ||  │
│     │       "~/p/g/n/portfolio"                                        │
│     │                                                                  │
│     └─→ Config.exists?()                                               │
│         └─→ File.dir?(path) and File.exists?(config.yml)               │
│                                                                        │
│  2. Config.load()                                                      │
│     │                                                                  │
│     └─→ YamlElixir.read_from_string(config.yml content)                │
│         ├─→ get_in(config, ["portfolio", "name"])                      │
│         └─→ get_in(config, ["portfolio", "owner"])                     │
│                                                                        │
│  3. Registry.list_repos()                                              │
│     │                                                                  │
│     ├─→ load_registry()                                                │
│     │   └─→ File.read(registry.yml) |> YamlElixir.read_from_string()   │
│     │                                                                  │
│     └─→ Enum.map(&parse_repo/1)                                        │
│         └─→ Convert string keys to atoms, parse dates                  │
│                                                                        │
│  4. Group and Display                                                  │
│     │                                                                  │
│     ├─→ Enum.group_by(& &1.status)  # :active, :stale, :archived       │
│     ├─→ Enum.group_by(& &1.type)    # :library, :application           │
│     └─→ Enum.group_by(& &1.language)# :elixir, :python, etc.           │
│                                                                        │
│  5. Relationships.list()                                               │
│     │                                                                  │
│     ├─→ load_relationships()                                           │
│     │   └─→ File.read(relationships.yml)                               │
│     │                                                                  │
│     └─→ Enum.map(&parse_relationship/1)                                │
│         └─→ Convert type string to atom                                │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

**Data Transformations:**

```elixir
# Raw YAML to Elixir map
%{"id" => "flowstone", "language" => "elixir", ...}

# After parse_repo/1
%{id: "flowstone", language: :elixir, ...}

# Grouping
repos |> Enum.group_by(& &1.status)
# => %{active: [repo1, repo2], stale: [repo3], archived: []}
```

**Output Example:**
```
Portfolio Status Report
==================================================

Portfolio Path: /home/user/p/g/n/portfolio
Config exists:  Yes

Portfolio Name: My Projects
Owner:          username

--------------------------------------------------

REPOSITORIES: 45 total

By Status:
  active: 32
  stale: 10
  archived: 3

By Type:
  library: 28
  application: 15
  unknown: 2

By Language:
  elixir: 25
  python: 12
  javascript: 8

--------------------------------------------------

RELATIONSHIPS: 23 total

  depends_on: 18
  related_to: 3
  port_of: 2
```

---

### 3. list_by_language.exs

**Purpose:** List all repositories grouped by programming language.

**Usage:**
```bash
mix run examples/list_by_language.exs
```

**Code Flow:**

```
┌────────────────────────────────────────────────────────────────────────┐
│ list_by_language.exs                                                   │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  1. Registry.list_repos()                                              │
│     │                                                                  │
│     └─→ Returns all repos from registry.yml                            │
│                                                                        │
│  2. Group by Language                                                  │
│     │                                                                  │
│     ├─→ Enum.group_by(& &1.language)                                   │
│     │   # %{elixir: [...], python: [...], nil: [...]}                  │
│     │                                                                  │
│     └─→ Enum.sort_by(fn {lang, _} -> to_string(lang) end)              │
│         # Alphabetical order                                           │
│                                                                        │
│  3. For each language group:                                           │
│     │                                                                  │
│     ├─→ Sort repos by name                                             │
│     │   └─→ Enum.sort_by(language_repos, & &1.name)                    │
│     │                                                                  │
│     └─→ Display with status icon                                       │
│         └─→ case repo.status do                                        │
│               :active -> "+"                                           │
│               :stale -> "~"                                            │
│               :archived -> "-"                                         │
│             end                                                        │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

**Output Example:**
```
Repositories by Language
==================================================

ELIXIR (25)
----------------------------------------
  [+] blueprint (library)
  [+] flowstone (library)
  [~] old_project (application)
  [-] deprecated_lib (library)

PYTHON (12)
----------------------------------------
  [+] data_pipeline (application)
  [+] ml_utils (library)

Legend: [+] active, [~] stale, [-] archived
```

---

### 4. find_stale_repos.exs

**Purpose:** Find repositories that may need attention (stale or blocked status).

**Usage:**
```bash
mix run examples/find_stale_repos.exs
```

**Code Flow:**

```
┌────────────────────────────────────────────────────────────────────────┐
│ find_stale_repos.exs                                                   │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  1. Registry.list_repos()                                              │
│     │                                                                  │
│     └─→ Returns all repos from registry.yml                            │
│                                                                        │
│  2. Filter by Status                                                   │
│     │                                                                  │
│     ├─→ stale = Enum.filter(repos, &(&1.status == :stale))             │
│     └─→ blocked = Enum.filter(repos, &(&1.status == :blocked))         │
│                                                                        │
│  3. Decision Branch                                                    │
│     │                                                                  │
│     ├─→ If empty(stale) and empty(blocked):                            │
│     │   └─→ "All repositories are healthy!"                            │
│     │                                                                  │
│     └─→ Otherwise:                                                     │
│         ├─→ Display stale repos with details                           │
│         ├─→ Display blocked repos with details                         │
│         └─→ Show summary counts                                        │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

**Status meanings:**
- `:active` - Repository is actively maintained
- `:stale` - Repository hasn't been updated recently
- `:blocked` - Repository has issues blocking progress
- `:archived` - Repository is no longer maintained

**Output Example:**
```
Stale Repository Finder
==================================================

STALE REPOSITORIES (3)
----------------------------------------

  old_experiments
    Path: /home/user/p/g/n/old_experiments
    Type: application, Language: python

  legacy_lib
    Path: /home/user/p/g/n/legacy_lib
    Type: library, Language: elixir

BLOCKED REPOSITORIES (1)
----------------------------------------

  stuck_project
    Path: /home/user/p/g/n/stuck_project

Summary:
  Stale:   3
  Blocked: 1
  Active:  41
  Total:   45
```

---

### 5. sync_all_repos.exs

**Purpose:** Sync all registered repositories, updating computed fields.

**Usage:**
```bash
mix run examples/sync_all_repos.exs
```

**Code Flow:**

```
┌────────────────────────────────────────────────────────────────────────┐
│ sync_all_repos.exs                                                     │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  1. Syncer.sync_all()                                                  │
│     │                                                                  │
│     ├─→ Registry.list_repos()                                          │
│     │   └─→ Get all registered repos                                   │
│     │                                                                  │
│     └─→ For each repo:                                                 │
│         │                                                              │
│         └─→ sync_repo(repo.id, opts)                                   │
│             │                                                          │
│             ├─→ Registry.get_repo(repo_id)                             │
│             │   └─→ Get repo path                                      │
│             │                                                          │
│             └─→ update_computed_fields(repo_id, repo.path, opts)       │
│                 │                                                      │
│                 ├─→ get_git_info(repo_path)                            │
│                 │   │                                                  │
│                 │   ├─→ get_last_commit(repo_path)                     │
│                 │   │   └─→ git log -1 --format=%H|%s|%ai              │
│                 │   │                                                  │
│                 │   ├─→ get_commit_count_30d(repo_path)                │
│                 │   │   └─→ git rev-list --count --since=DATE HEAD     │
│                 │   │                                                  │
│                 │   └─→ get_current_branch(repo_path)                  │
│                 │       └─→ git rev-parse --abbrev-ref HEAD            │
│                 │                                                      │
│                 ├─→ Scanner.detect_language(repo_path)                 │
│                 │                                                      │
│                 ├─→ Scanner.extract_dependencies(repo_path, language)  │
│                 │   │                                                  │
│                 │   ├─→ :elixir → Parse mix.exs                        │
│                 │   ├─→ :python → Parse requirements.txt               │
│                 │   └─→ :javascript → Parse package.json               │
│                 │                                                      │
│                 └─→ Context.update_computed(repo_id, computed)         │
│                     │                                                  │
│                     ├─→ Context.load(repo_id)                          │
│                     │   └─→ Read context.yml                           │
│                     │                                                  │
│                     ├─→ Merge computed fields                          │
│                     │                                                  │
│                     └─→ Context.save(repo_id, updated)                 │
│                         └─→ Write context.yml                          │
│                                                                        │
│  2. Aggregate Results                                                  │
│     │                                                                  │
│     ├─→ synced = count {:ok, _}                                        │
│     ├─→ failed = count {:error, _, _}                                  │
│     └─→ errors = filter {:error, _, _}                                 │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

**Git Commands Used:**

| Command | Purpose | Example Output |
|---------|---------|----------------|
| `git log -1 --format=%H\|%s\|%ai` | Last commit info | `abc123\|Fix bug\|2026-01-05 10:30:00 -0500` |
| `git rev-list --count --since=DATE HEAD` | Commits in 30 days | `42` |
| `git rev-parse --abbrev-ref HEAD` | Current branch | `main` |

**Dependency Extraction:**

```elixir
# Elixir (mix.exs)
extract_elixir_deps(content)
# Regex: ~r/\{:(\w+),\s*"[^"]*"\}/  → runtime deps
# Regex: ~r/\{:(\w+),[^}]*only:\s*(?::dev|:test|\[:dev|\[:test)/ → dev deps

# Python (requirements.txt)
"package==1.0.0" → "package"
"package>=2.0,<3.0" → "package"
"package[extra]" → "package"

# JavaScript (package.json)
pkg["dependencies"] → runtime
pkg["devDependencies"] → dev
```

**Output Example:**
```
Repository Sync
==================================================

Syncing all registered repositories...
This will update computed fields (last commit, dependencies, etc.)

Sync Complete!

  Total:  45
  Synced: 43
  Failed: 2

Errors:
  missing_repo: {:file_error, :enoent}
  corrupted_repo: {:parse_error, ...}

Done!
```

---

### 6. analyze_dependencies.exs

**Purpose:** Analyze dependency relationships between repositories.

**Usage:**
```bash
mix run examples/analyze_dependencies.exs
```

**Code Flow:**

```
┌────────────────────────────────────────────────────────────────────────┐
│ analyze_dependencies.exs                                               │
├────────────────────────────────────────────────────────────────────────┤
│                                                                        │
│  1. Load Data (parallel pattern match)                                 │
│     │                                                                  │
│     ├─→ Registry.list_repos()                                          │
│     │   └─→ All repos from registry.yml                                │
│     │                                                                  │
│     └─→ Relationships.list()                                           │
│         └─→ All relationships from relationships.yml                   │
│                                                                        │
│  2. Filter Dependencies                                                │
│     │                                                                  │
│     └─→ deps = Enum.filter(rels, &(&1.type == :depends_on))            │
│                                                                        │
│  3. Build Dependency Graph                                             │
│     │                                                                  │
│     ├─→ Group by 'to' (what things depend ON)                          │
│     │   └─→ deps |> Enum.group_by(& &1.to)                             │
│     │       # %{"portfolio_core" => [rel1, rel2, ...]}                 │
│     │                                                                  │
│     └─→ Sort by dependent count (most depended-on first)               │
│         └─→ Enum.sort_by(fn {_, v} -> -length(v) end)                  │
│                                                                        │
│  4. Analysis                                                           │
│     │                                                                  │
│     ├─→ repos_with_deps = deps |> map(& &1.from) |> uniq               │
│     │   # Repos that depend on something                               │
│     │                                                                  │
│     ├─→ repos_depended_on = deps |> map(& &1.to) |> uniq               │
│     │   # Repos that something depends on                              │
│     │                                                                  │
│     ├─→ leaf_repos = repo_ids -- repos_with_deps                       │
│     │   # Nothing depends on these                                     │
│     │                                                                  │
│     └─→ root_repos = repos_with_deps -- repos_depended_on              │
│         # These only depend on others, nothing depends on them         │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
```

**Dependency Graph Concepts:**

```
Leaf Repos: End consumers, nothing depends on them
  ├─→ my_web_app (depends on libraries, but nothing depends on it)
  └─→ cli_tool

Root Repos: Foundation libraries, only provide dependencies
  ├─→ portfolio_core (nothing depends on, others use it)
  └─→ utility_lib

Middle Repos: Both depend on and are depended upon
  ├─→ portfolio_index (depends on core, manager depends on it)
  └─→ portfolio_manager
```

**Output Example:**
```
Dependency Analysis
==================================================

Repositories: 45
Dependencies: 23

DEPENDENCY GRAPH
----------------------------------------

Most depended-on repositories:

  portfolio_core (5 dependents)
    <- portfolio_index
    <- portfolio_manager
    <- portfolio_coder
    <- flowstone
    <- blueprint

  utility_lib (3 dependents)
    <- web_app
    <- cli_tool
    <- data_pipeline

ANALYSIS
----------------------------------------

Leaf repos (nothing depends on them): 12
Root repos (depend on others only):   8

Root repositories:
  - web_app
  - cli_tool
  - data_pipeline
  - admin_dashboard
  ...
```

---

## Configuration Reference

### Application Config (config/dev.exs)

```elixir
import Config

config :portfolio_coder,
  log_level: :debug

# Disable database connections for local Portfolio features
# (not needed for scanning/managing repos via YAML files)
config :portfolio_index,
  start_repo: false,      # Don't start PostgreSQL
  start_boltx: false,     # Don't start Neo4j
  start_telemetry: false  # Skip telemetry setup

config :portfolio_manager,
  start_repo: false,      # Don't start PostgreSQL
  start_router: false     # Skip HTTP router

config :logger, level: :debug
```

### Environment Variables

| Variable | Purpose | Default |
|----------|---------|---------|
| `PORTFOLIO_DIR` | Portfolio directory path | `~/p/g/n/portfolio` |

### Rate Limiting (portfolio_index)

The rate limiter uses an ETS-based sliding window counter:

```elixir
# Location: portfolio_index/lib/portfolio_index/rate_limiter.ex
PortfolioIndex.RateLimiter.check_rate(key, interval_ms, limit)
# Returns: {:allow, count} | {:deny, limit}
```

---

## Running Examples

All examples can be run with Mix:

```bash
# From the portfolio_coder directory
cd ~/p/g/n/portfolio_coder

# Scan for new repositories
mix run examples/scan_repos.exs

# Show portfolio status
mix run examples/show_portfolio_status.exs

# List by language
mix run examples/list_by_language.exs

# Find stale repos
mix run examples/find_stale_repos.exs

# Sync all repos
mix run examples/sync_all_repos.exs

# Analyze dependencies
mix run examples/analyze_dependencies.exs
```

## Troubleshooting

### "0 directories" in scan

Ensure `~/p/g/n/portfolio/config.yml` has directories configured:
```yaml
scan:
  directories:
    - ~/p/g/n
    - ~/your/other/path
```

### Database connection errors

Add to `config/dev.exs`:
```elixir
config :portfolio_index,
  start_repo: false,
  start_boltx: false

config :portfolio_manager,
  start_repo: false
```

### "not found" errors for registry

Ensure `~/p/g/n/portfolio/registry.yml` exists:
```yaml
repos: []
```

### "not found" errors for relationships

Ensure `~/p/g/n/portfolio/relationships.yml` exists:
```yaml
relationships: []
```
