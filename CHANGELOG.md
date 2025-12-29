# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

- portfolio_manager ~> 0.3.0
- portfolio_index ~> 0.2.0
- portfolio_core ~> 0.2.0
- sourceror ~> 1.0

[Unreleased]: https://github.com/nshkrdotcom/portfolio_coder/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/nshkrdotcom/portfolio_coder/releases/tag/v0.1.0
