# Find repositories that may need attention
#
# Usage: mix run examples/find_stale_repos.exs

alias PortfolioCoder.Portfolio.Registry

IO.puts("Stale Repository Finder")
IO.puts(String.duplicate("=", 50))
IO.puts("")

case Registry.list_repos() do
  {:ok, repos} ->
    # Find stale repos
    stale = Enum.filter(repos, &(&1.status == :stale))
    blocked = Enum.filter(repos, &(&1.status == :blocked))

    if Enum.empty?(stale) and Enum.empty?(blocked) do
      IO.puts("All repositories are healthy!")
      IO.puts("")
      IO.puts("Active: #{Enum.count(repos, &(&1.status == :active))}")
      IO.puts("Total:  #{length(repos)}")
    else
      unless Enum.empty?(stale) do
        IO.puts("STALE REPOSITORIES (#{length(stale)})")
        IO.puts(String.duplicate("-", 40))
        IO.puts("")

        for repo <- stale do
          IO.puts("  #{repo.name}")
          IO.puts("    Path: #{repo.path}")
          IO.puts("    Type: #{repo.type}, Language: #{repo.language}")
          IO.puts("")
        end
      end

      unless Enum.empty?(blocked) do
        IO.puts("BLOCKED REPOSITORIES (#{length(blocked)})")
        IO.puts(String.duplicate("-", 40))
        IO.puts("")

        for repo <- blocked do
          IO.puts("  #{repo.name}")
          IO.puts("    Path: #{repo.path}")
          IO.puts("")
        end
      end

      IO.puts("")
      IO.puts("Summary:")
      IO.puts("  Stale:   #{length(stale)}")
      IO.puts("  Blocked: #{length(blocked)}")
      IO.puts("  Active:  #{Enum.count(repos, &(&1.status == :active))}")
      IO.puts("  Total:   #{length(repos)}")
    end

  {:error, reason} ->
    IO.puts(:stderr, "Error: #{inspect(reason)}")
    System.halt(1)
end
