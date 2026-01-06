# Sync all registered repositories
#
# Usage: mix run examples/sync_all_repos.exs

alias PortfolioCoder.Portfolio.Syncer

IO.puts("Repository Sync")
IO.puts(String.duplicate("=", 50))
IO.puts("")

IO.puts("Syncing all registered repositories...")
IO.puts("This will update computed fields (last commit, dependencies, etc.)")
IO.puts("")

case Syncer.sync_all() do
  {:ok, result} ->
    IO.puts("Sync Complete!")
    IO.puts("")
    IO.puts("  Total:  #{result.total}")
    IO.puts("  Synced: #{result.synced}")
    IO.puts("  Failed: #{result.failed}")
    IO.puts("")

    unless Enum.empty?(result.errors) do
      IO.puts("Errors:")

      for {:error, id, reason} <- result.errors do
        IO.puts("  #{id}: #{inspect(reason)}")
      end

      IO.puts("")
    end

    IO.puts("Done!")

  {:error, reason} ->
    IO.puts(:stderr, "Error syncing: #{inspect(reason)}")
    System.halt(1)
end
