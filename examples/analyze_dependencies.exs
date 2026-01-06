# Analyze dependency relationships between repositories
#
# Usage: mix run examples/analyze_dependencies.exs

alias PortfolioCoder.Portfolio.{Registry, Relationships}

IO.puts("Dependency Analysis")
IO.puts(String.duplicate("=", 50))
IO.puts("")

case {Registry.list_repos(), Relationships.list()} do
  {{:ok, repos}, {:ok, rels}} ->
    deps = Enum.filter(rels, &(&1.type == :depends_on))

    IO.puts("Repositories: #{length(repos)}")
    IO.puts("Dependencies: #{length(deps)}")
    IO.puts("")

    if Enum.empty?(deps) do
      IO.puts("No dependency relationships found.")
      IO.puts("")
      IO.puts("Add dependencies with:")
      IO.puts("  Relationships.add(:depends_on, \"from_repo\", \"to_repo\")")
    else
      # Build dependency graph
      IO.puts("DEPENDENCY GRAPH")
      IO.puts(String.duplicate("-", 40))
      IO.puts("")

      # Group by 'to' (what things depend ON)
      depended_on =
        deps
        |> Enum.group_by(& &1.to)
        |> Enum.sort_by(fn {_, v} -> -length(v) end)

      IO.puts("Most depended-on repositories:")
      IO.puts("")

      for {to_repo, dependents} <- Enum.take(depended_on, 10) do
        IO.puts("  #{to_repo} (#{length(dependents)} dependents)")

        for dep <- dependents do
          IO.puts("    <- #{dep.from}")
        end

        IO.puts("")
      end

      # Find repos with no dependencies
      repos_with_deps = deps |> Enum.map(& &1.from) |> Enum.uniq()
      repos_depended_on = deps |> Enum.map(& &1.to) |> Enum.uniq()
      repo_ids = Enum.map(repos, & &1.id)

      leaf_repos = repo_ids -- repos_with_deps
      root_repos = repos_with_deps -- repos_depended_on

      IO.puts("ANALYSIS")
      IO.puts(String.duplicate("-", 40))
      IO.puts("")
      IO.puts("Leaf repos (nothing depends on them): #{length(leaf_repos)}")
      IO.puts("Root repos (depend on others only):   #{length(root_repos)}")
      IO.puts("")

      unless Enum.empty?(root_repos) do
        IO.puts("Root repositories:")

        for id <- Enum.take(root_repos, 10) do
          IO.puts("  - #{id}")
        end

        if length(root_repos) > 10 do
          IO.puts("  ... and #{length(root_repos) - 10} more")
        end
      end
    end

  {{:error, reason}, _} ->
    IO.puts(:stderr, "Error loading repos: #{inspect(reason)}")
    System.halt(1)

  {_, {:error, reason}} ->
    IO.puts(:stderr, "Error loading relationships: #{inspect(reason)}")
    System.halt(1)
end

IO.puts("")
IO.puts("Done!")
