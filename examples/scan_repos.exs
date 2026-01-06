# Scan all configured directories and list discovered repositories
#
# Usage: mix run examples/scan_repos.exs

alias PortfolioCoder.Portfolio.{Config, Scanner}

IO.puts("Portfolio Repository Scanner")
IO.puts(String.duplicate("=", 50))
IO.puts("")

# Show configured directories
directories = Config.scan_directories()
IO.puts("Scanning #{length(directories)} directories:")

for dir <- directories do
  exists = if File.dir?(dir), do: "exists", else: "NOT FOUND"
  IO.puts("  - #{dir} (#{exists})")
end

IO.puts("")

# Scan for repositories
case Scanner.scan() do
  {:ok, results} ->
    new_repos = Enum.filter(results, & &1.is_new)
    existing = Enum.reject(results, & &1.is_new)

    IO.puts("Found #{length(results)} repositories:")
    IO.puts("  New (not tracked):    #{length(new_repos)}")
    IO.puts("  Already tracked:      #{length(existing)}")
    IO.puts("")

    # Group by language
    by_language =
      results
      |> Enum.group_by(& &1.language)
      |> Enum.sort_by(fn {_, v} -> -length(v) end)

    IO.puts("By Language:")

    for {lang, repos} <- by_language do
      lang_str = lang || "unknown"
      IO.puts("  #{lang_str}: #{length(repos)}")
    end

    IO.puts("")

    # Show new repos if any
    unless Enum.empty?(new_repos) do
      IO.puts("New repositories (not yet tracked):")
      IO.puts("")

      for repo <- Enum.take(new_repos, 20) do
        lang = repo.language || "?"
        type = repo.type || "?"
        IO.puts("  #{repo.name}")
        IO.puts("    Language: #{lang}, Type: #{type}")
        IO.puts("    Path: #{repo.path}")

        unless Enum.empty?(repo.remotes) do
          IO.puts("    Remote: #{hd(repo.remotes).url}")
        end

        IO.puts("")
      end

      if length(new_repos) > 20 do
        IO.puts("  ... and #{length(new_repos) - 20} more")
      end
    end

  {:error, reason} ->
    IO.puts(:stderr, "Error scanning: #{inspect(reason)}")
    System.halt(1)
end

IO.puts("Done!")
