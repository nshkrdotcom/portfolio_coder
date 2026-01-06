# Portfolio Coder Examples

This directory contains working examples that operate on real data from your portfolio.

## Prerequisites

1. Ensure you have a portfolio repository set up at `~/p/g/n/portfolio` (or set `PORTFOLIO_DIR`)
2. The portfolio should have:
   - `config.yml` with scan directories configured
   - `registry.yml` for tracked repos
   - `relationships.yml` for repo relationships

## Running Examples

All examples can be run using `mix run`:

```bash
cd /path/to/portfolio_coder
mix run examples/scan_repos.exs
```

Or with Mix.install for standalone execution:

```bash
elixir examples/scan_repos.exs
```

## Examples

### scan_repos.exs

Scans all configured directories and lists discovered repositories.

```bash
mix run examples/scan_repos.exs
```

### show_portfolio_status.exs

Displays a comprehensive status of your portfolio including repo counts by status, type, and language.

```bash
mix run examples/show_portfolio_status.exs
```

### list_by_language.exs

Lists all repositories grouped by programming language.

```bash
mix run examples/list_by_language.exs
```

### find_stale_repos.exs

Identifies repositories that may need attention based on their status or inactivity.

```bash
mix run examples/find_stale_repos.exs
```

### sync_all_repos.exs

Syncs all registered repositories, updating their computed fields.

```bash
mix run examples/sync_all_repos.exs
```

### analyze_dependencies.exs

Analyzes dependency relationships between your repositories.

```bash
mix run examples/analyze_dependencies.exs
```

## Configuration

Examples use the default portfolio path `~/p/g/n/portfolio`. Override with:

```bash
PORTFOLIO_DIR=~/my/portfolio mix run examples/scan_repos.exs
```

## Notes

- Examples read from your real portfolio data
- Some examples may modify files (sync operations update context.yml)
- Always backup important data before running modification examples
