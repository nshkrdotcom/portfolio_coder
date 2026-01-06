# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-01-06

### Added

- **Portfolio Integration** - Centralized project management system
  - `Portfolio.Config` - Configuration management with multi-directory support
  - `Portfolio.Registry` - Repository tracking and metadata storage
  - `Portfolio.Context` - Per-repo context files (context.yml, notes.md)
  - `Portfolio.Relationships` - Inter-repo relationship tracking
  - `Portfolio.Scanner` - Multi-directory repository discovery
  - `Portfolio.Syncer` - Sync computed fields with actual repos

- **Portfolio CLI Commands**
  - `mix portfolio.list` - List repos with status/type/language filters
  - `mix portfolio.show` - Show detailed repo information
  - `mix portfolio.scan` - Discover repos in configured directories
  - `mix portfolio.add` - Add repo to tracking
  - `mix portfolio.remove` - Remove repo from tracking
  - `mix portfolio.sync` - Sync metadata with actual repo state
  - `mix portfolio.status` - Show portfolio summary

- **Multi-Directory Scanning** - Support for multiple base directories
  - Configure in `config.yml` under `scan.directories`
  - Default: `~/p/g/n` and `~/p/g/North-Shore-AI`
  - Automatic language and type detection
  - Git remote extraction

- **Working Examples** in `examples/` directory
  - `scan_repos.exs` - Scan and list discovered repos
  - `show_portfolio_status.exs` - Display portfolio status
  - `list_by_language.exs` - Group repos by language
  - `find_stale_repos.exs` - Find repos needing attention
  - `sync_all_repos.exs` - Sync all repo metadata
  - `analyze_dependencies.exs` - Dependency analysis

- **Design Documentation** - Detailed design document at `docs/20260105/portfolio_integration/design.md`

### Changed

- Updated architecture to include Portfolio layer
- Extended README with portfolio features and usage

### Dependencies

- Added yaml_elixir ~> 2.9 for YAML parsing

## [0.1.1] - 2025-12-30

### Fixed

- Minor bug fixes and improvements

## [0.1.0] - 2025-12-28

### Added

- Initial release of Portfolio Coder
- **Indexer** - Repository scanning and indexing
  - Multi-language support (Elixir, Python, JavaScript/TypeScript)
  - Configurable file patterns and exclusions
  - Automatic language detection
- **Search** - Semantic and text-based code search
  - Natural language queries
  - Language and file filters
  - Score-based ranking
- **Parsers** - Language-specific code parsing
  - Elixir parser using Sourceror
  - Python parser (basic)
  - JavaScript/TypeScript parser (basic)
- **Graph** - Dependency graph building and querying
  - Elixir mix.exs dependency extraction
  - Python requirements.txt parsing
  - Graph traversal and impact analysis
- **Tools** - Agent tools for code intelligence
  - search_code - Semantic code search
  - read_file - Read file contents
  - list_files - List files by pattern
  - analyze_code - Parse and analyze code structure
  - find_references - Find symbol references
- **CLI Tasks**
  - `mix code.index` - Index repositories
  - `mix code.search` - Search indexed code
  - `mix code.ask` - Ask questions about code
  - `mix code.deps` - Dependency analysis

### Dependencies

- portfolio_manager ~> 0.3.1
- portfolio_index ~> 0.3.1
- portfolio_core ~> 0.3.1
- sourceror ~> 1.0

[Unreleased]: https://github.com/nshkrdotcom/portfolio_coder/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/nshkrdotcom/portfolio_coder/compare/v0.1.1...v0.4.0
[0.1.1]: https://github.com/nshkrdotcom/portfolio_coder/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/nshkrdotcom/portfolio_coder/releases/tag/v0.1.0
