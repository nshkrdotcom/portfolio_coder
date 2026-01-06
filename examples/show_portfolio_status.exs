# Show comprehensive portfolio status
#
# Usage: mix run examples/show_portfolio_status.exs

alias PortfolioCoder.Portfolio.{Config, Registry, Relationships}

IO.puts("Portfolio Status Report")
IO.puts(String.duplicate("=", 50))
IO.puts("")

# Portfolio info
path = Config.portfolio_path()
IO.puts("Portfolio Path: #{path}")
IO.puts("Config exists:  #{if Config.exists?(), do: "Yes", else: "No"}")
IO.puts("")

# Load config
case Config.load() do
  {:ok, config} ->
    IO.puts("Portfolio Name: #{get_in(config, ["portfolio", "name"]) || "Not set"}")
    IO.puts("Owner:          #{get_in(config, ["portfolio", "owner"]) || "Not set"}")

  {:error, reason} ->
    IO.puts("Config error: #{inspect(reason)}")
end

IO.puts("")
IO.puts(String.duplicate("-", 50))
IO.puts("")

# Repository statistics
case Registry.list_repos() do
  {:ok, repos} ->
    IO.puts("REPOSITORIES: #{length(repos)} total")
    IO.puts("")

    # By status
    by_status =
      repos
      |> Enum.group_by(& &1.status)
      |> Enum.sort_by(fn {_, v} -> -length(v) end)

    IO.puts("By Status:")

    for {status, list} <- by_status do
      IO.puts("  #{status}: #{length(list)}")
    end

    IO.puts("")

    # By type
    by_type =
      repos
      |> Enum.group_by(& &1.type)
      |> Enum.sort_by(fn {_, v} -> -length(v) end)

    IO.puts("By Type:")

    for {type, list} <- by_type do
      IO.puts("  #{type}: #{length(list)}")
    end

    IO.puts("")

    # By language
    by_language =
      repos
      |> Enum.group_by(& &1.language)
      |> Enum.sort_by(fn {_, v} -> -length(v) end)

    IO.puts("By Language:")

    for {lang, list} <- by_language do
      lang_str = lang || "unknown"
      IO.puts("  #{lang_str}: #{length(list)}")
    end

  {:error, reason} ->
    IO.puts("Error loading repos: #{inspect(reason)}")
end

IO.puts("")
IO.puts(String.duplicate("-", 50))
IO.puts("")

# Relationships
case Relationships.list() do
  {:ok, rels} ->
    IO.puts("RELATIONSHIPS: #{length(rels)} total")
    IO.puts("")

    by_type =
      rels
      |> Enum.group_by(& &1.type)
      |> Enum.sort_by(fn {_, v} -> -length(v) end)

    for {type, list} <- by_type do
      IO.puts("  #{type}: #{length(list)}")
    end

  {:error, _} ->
    IO.puts("No relationships loaded")
end

IO.puts("")
IO.puts("Done!")
