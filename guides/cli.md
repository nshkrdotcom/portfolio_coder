# CLI Reference

This guide summarizes key CLI commands. Use `mix help <task>` for full details.

## Code Intelligence

- `mix code.index PATH [--index NAME]`
- `mix code.search QUERY [--index NAME]`
- `mix code.ask প্রশ্ন [--index NAME]`
- `mix code.deps build PATH [--graph NAME]`
- `mix code.agent` (interactive tool‑using agent)
- `mix code.agent_session` (Claude/Codex autonomous sessions)

## Portfolio Management

- `mix portfolio.scan [paths...]`
- `mix portfolio.list [filters]`
- `mix portfolio.show <id>`
- `mix portfolio.add <path>`
- `mix portfolio.remove <id>`
- `mix portfolio.sync`
- `mix portfolio.status`

## Tips

- `mix code.ask` supports graceful degradation: if LLM providers fail, it prints
  the retrieved context with an actionable error message.
- `mix code.agent_session` requires a working directory for Codex.
