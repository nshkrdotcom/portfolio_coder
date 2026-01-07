defmodule PortfolioCoder.Graph.CrossRepoDeps do
  @moduledoc """
  Cross-repository dependency analysis.

  Analyzes dependencies between multiple repositories in a portfolio,
  identifying shared dependencies, version conflicts, and upgrade paths.

  ## Usage

      repos = [
        %{name: "app_core", dependencies: ["phoenix", "ecto"], dev_dependencies: []},
        %{name: "app_web", dependencies: ["app_core", "phoenix_live_view"], dev_dependencies: []}
      ]

      {:ok, graph} = CrossRepoDeps.build_cross_repo_graph(repos)

      # Find repos affected by changes to app_core
      impact = CrossRepoDeps.impact_analysis(graph, "app_core")

      # Find shared dependencies
      shared = CrossRepoDeps.find_shared_dependencies(graph)

      # Detect version conflicts
      conflicts = CrossRepoDeps.find_version_conflicts(graph)

      # Get safe upgrade order
      order = CrossRepoDeps.suggest_upgrade_order(graph)
  """

  @type repo :: %{
          name: String.t(),
          dependencies: [String.t() | %{name: String.t(), version: String.t()}],
          dev_dependencies: [String.t() | %{name: String.t(), version: String.t()}]
        }

  @type graph_node :: %{
          id: String.t(),
          type: :repo | :external,
          metadata: map()
        }

  @type graph_edge :: %{
          from: String.t(),
          to: String.t(),
          type: :depends_on | :dev_depends_on
        }

  @type graph :: %{
          nodes: [graph_node()],
          edges: [graph_edge()],
          repos: [repo()]
        }

  @type impact_result :: %{
          repo: String.t(),
          directly_affected: [%{name: String.t()}],
          transitively_affected: [%{name: String.t()}],
          risk_level: :low | :medium | :high | :critical
        }

  @type shared_dep :: %{
          dependency: String.t(),
          used_by: [String.t()],
          count: non_neg_integer()
        }

  @type version_info :: %{
          dependency: String.t(),
          versions: [%{repo: String.t(), version: String.t()}]
        }

  @type version_conflict :: %{
          dependency: String.t(),
          repos: [%{repo: String.t(), version: String.t()}],
          severity: :minor | :major
        }

  @doc """
  Build a cross-repo dependency graph from a list of repositories.

  Returns a graph structure with nodes (repos and external deps) and edges (dependencies).
  """
  @spec build_cross_repo_graph([repo()]) :: {:ok, graph()} | {:error, term()}
  def build_cross_repo_graph(repos) when is_list(repos) do
    # Build nodes for each repo
    repo_nodes =
      Enum.map(repos, fn repo ->
        %{id: repo.name, type: :repo, metadata: %{repo: repo}}
      end)

    # Collect all external dependencies
    all_deps = collect_all_dependencies(repos)
    repo_names = MapSet.new(Enum.map(repos, & &1.name))

    external_deps =
      all_deps
      |> Enum.reject(fn dep_name -> MapSet.member?(repo_names, dep_name) end)
      |> Enum.uniq()
      |> Enum.map(fn dep_name ->
        %{id: dep_name, type: :external, metadata: %{}}
      end)

    # Build edges
    edges = build_edges(repos)

    graph = %{
      nodes: repo_nodes ++ external_deps,
      edges: edges,
      repos: repos
    }

    {:ok, graph}
  end

  @doc """
  Analyze the impact of changes to a specific repo.

  Returns directly and transitively affected repos along with a risk level.
  """
  @spec impact_analysis(graph(), String.t()) :: impact_result()
  def impact_analysis(graph, repo_name) do
    # Find repos that directly depend on this repo
    directly_affected =
      graph.edges
      |> Enum.filter(fn edge -> edge.to == repo_name end)
      |> Enum.map(fn edge -> %{name: edge.from} end)
      |> Enum.uniq_by(& &1.name)

    # Find transitively affected (repos that depend on directly affected)
    direct_names = MapSet.new(Enum.map(directly_affected, & &1.name))

    transitively_affected =
      find_transitive_dependents(graph, direct_names, MapSet.new([repo_name]))
      |> Enum.map(fn name -> %{name: name} end)
      |> Enum.reject(fn %{name: name} -> MapSet.member?(direct_names, name) end)

    # Calculate risk level based on impact
    total_affected = length(directly_affected) + length(transitively_affected)
    total_repos = length(Enum.filter(graph.nodes, &(&1.type == :repo)))

    risk_level = calculate_risk_level(total_affected, total_repos)

    %{
      repo: repo_name,
      directly_affected: directly_affected,
      transitively_affected: transitively_affected,
      risk_level: risk_level
    }
  end

  @doc """
  Find dependencies that are shared across multiple repos.

  Returns a list of shared dependencies with usage counts.
  """
  @spec find_shared_dependencies(graph()) :: [shared_dep()]
  def find_shared_dependencies(graph) do
    # Build a map of dependency -> repos that use it
    dep_usage =
      graph.repos
      |> Enum.flat_map(fn repo ->
        deps = normalize_dependencies(repo.dependencies)
        Enum.map(deps, fn dep_name -> {dep_name, repo.name} end)
      end)
      |> Enum.group_by(fn {dep, _repo} -> dep end, fn {_dep, repo} -> repo end)

    # Filter to only shared deps (used by 2+ repos)
    dep_usage
    |> Enum.filter(fn {_dep, repos} -> length(repos) >= 2 end)
    |> Enum.map(fn {dep, repos} ->
      %{
        dependency: dep,
        used_by: Enum.uniq(repos),
        count: length(Enum.uniq(repos))
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  @doc """
  Extract version information for all dependencies.

  Returns version info for dependencies that have version constraints specified.
  """
  @spec find_dependency_versions(graph()) :: [version_info()]
  def find_dependency_versions(graph) do
    graph.repos
    |> Enum.flat_map(fn repo ->
      repo.dependencies
      |> Enum.filter(&is_map/1)
      |> Enum.map(fn dep ->
        {dep.name, %{repo: repo.name, version: dep.version}}
      end)
    end)
    |> Enum.group_by(fn {name, _} -> name end, fn {_, info} -> info end)
    |> Enum.map(fn {name, versions} ->
      %{
        dependency: name,
        versions: versions
      }
    end)
  end

  @doc """
  Find version conflicts between repos.

  Returns a list of conflicts where repos use incompatible versions.
  """
  @spec find_version_conflicts(graph()) :: [version_conflict()]
  def find_version_conflicts(graph) do
    versions = find_dependency_versions(graph)

    versions
    |> Enum.filter(fn %{versions: vers} -> length(vers) >= 2 end)
    |> Enum.map(fn %{dependency: dep, versions: vers} ->
      # Check for major version conflicts
      major_versions =
        vers
        |> Enum.map(fn %{version: v} -> extract_major_version(v) end)
        |> Enum.uniq()

      if length(major_versions) > 1 do
        %{
          dependency: dep,
          repos: vers,
          severity: :major
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Suggest an upgrade order based on dependencies.

  Returns repos in topological order - dependencies before dependents.
  """
  @spec suggest_upgrade_order(graph()) :: [String.t()]
  def suggest_upgrade_order(graph) do
    repo_names =
      graph.nodes
      |> Enum.filter(&(&1.type == :repo))
      |> Enum.map(& &1.id)

    # Build adjacency list (reverse - from dependency to dependent)
    deps_map =
      graph.edges
      |> Enum.filter(fn edge ->
        edge.from in repo_names and edge.to in repo_names
      end)
      |> Enum.group_by(& &1.to, & &1.from)

    # Topological sort using Kahn's algorithm
    topological_sort(repo_names, deps_map)
  end

  @doc """
  Find circular dependencies between repos.

  Returns a list of cycles found in the dependency graph.
  """
  @spec find_cycles(graph()) :: [[String.t()]]
  def find_cycles(graph) do
    repo_names =
      graph.nodes
      |> Enum.filter(&(&1.type == :repo))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # Build adjacency list
    adj =
      graph.edges
      |> Enum.filter(fn edge ->
        MapSet.member?(repo_names, edge.from) and MapSet.member?(repo_names, edge.to)
      end)
      |> Enum.group_by(& &1.from, & &1.to)

    # Find cycles using DFS
    find_all_cycles(MapSet.to_list(repo_names), adj)
  end

  @doc """
  Calculate the dependency depth for a repo.

  Returns the maximum distance to any leaf dependency.
  """
  @spec dependency_depth(graph(), String.t()) :: non_neg_integer()
  def dependency_depth(graph, repo_name) do
    repo_names =
      graph.nodes
      |> Enum.filter(&(&1.type == :repo))
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # Build adjacency list
    adj =
      graph.edges
      |> Enum.filter(fn edge ->
        MapSet.member?(repo_names, edge.from) and MapSet.member?(repo_names, edge.to)
      end)
      |> Enum.group_by(& &1.from, & &1.to)

    calculate_depth(repo_name, adj, MapSet.new())
  end

  @doc """
  Get all repos that depend on a given repo (transitively).
  """
  @spec get_all_dependents(graph(), String.t()) :: [%{name: String.t()}]
  def get_all_dependents(graph, repo_name) do
    find_transitive_dependents(graph, MapSet.new([repo_name]), MapSet.new())
    |> Enum.reject(&(&1 == repo_name))
    |> Enum.map(fn name -> %{name: name} end)
  end

  # Private functions

  defp collect_all_dependencies(repos) do
    repos
    |> Enum.flat_map(fn repo ->
      normalize_dependencies(repo.dependencies) ++
        normalize_dependencies(repo.dev_dependencies)
    end)
    |> Enum.uniq()
  end

  defp normalize_dependencies(deps) do
    Enum.map(deps, fn
      %{name: name} -> name
      name when is_binary(name) -> name
    end)
  end

  defp build_edges(repos) do
    Enum.flat_map(repos, fn repo ->
      deps =
        Enum.map(normalize_dependencies(repo.dependencies), fn dep ->
          %{from: repo.name, to: dep, type: :depends_on}
        end)

      dev_deps =
        Enum.map(normalize_dependencies(repo.dev_dependencies), fn dep ->
          %{from: repo.name, to: dep, type: :dev_depends_on}
        end)

      deps ++ dev_deps
    end)
  end

  @spec find_transitive_dependents(graph(), MapSet.t(String.t()), MapSet.t(String.t())) ::
          [String.t()]
  defp find_transitive_dependents(graph, to_process, visited) do
    if MapSet.size(to_process) == 0 do
      Enum.to_list(visited)
    else
      # Find all repos that depend on any repo in to_process
      new_dependents =
        graph.edges
        |> Enum.filter(fn edge -> Enum.member?(to_process, edge.to) end)
        |> Enum.map(& &1.from)
        |> Enum.uniq()
        |> Enum.reject(&Enum.member?(visited, &1))
        |> MapSet.new()

      new_visited = Enum.into(to_process, visited)
      find_transitive_dependents(graph, new_dependents, new_visited)
    end
  end

  defp calculate_risk_level(affected, total) when total > 0 do
    ratio = affected / total

    cond do
      ratio >= 0.5 -> :critical
      ratio >= 0.3 -> :high
      ratio >= 0.1 -> :medium
      true -> :low
    end
  end

  defp calculate_risk_level(_, _), do: :low

  defp extract_major_version(version_string) do
    # Extract major version from strings like "~> 3.10", "~> 2.2", ">= 1.0.0"
    case Regex.run(~r/(\d+)/, version_string) do
      [_, major] -> String.to_integer(major)
      _ -> 0
    end
  end

  defp topological_sort(nodes, deps_map) do
    # deps_map maps dependency -> [dependents]
    # For upgrade order: process dependencies before dependents
    # Initialize in-degree (count of dependencies each node has)
    in_degree = Map.new(nodes, fn n -> {n, 0} end)

    # For each dependent in the values, increment its in-degree
    in_degree =
      Enum.reduce(deps_map, in_degree, fn {_dep, dependents}, acc ->
        Enum.reduce(dependents, acc, fn dependent, inner_acc ->
          Map.update(inner_acc, dependent, 1, &(&1 + 1))
        end)
      end)

    # Start with nodes that have no dependencies (in-degree 0)
    queue =
      in_degree
      |> Enum.filter(fn {_node, degree} -> degree == 0 end)
      |> Enum.map(fn {node, _} -> node end)
      |> Enum.sort()

    do_topological_sort(queue, in_degree, deps_map, [])
  end

  defp do_topological_sort([], _in_degree, _deps_map, result) do
    Enum.reverse(result)
  end

  defp do_topological_sort([node | rest], in_degree, deps_map, result) do
    # Find nodes that depend on this node (this node is a dependency of them)
    dependents = Map.get(deps_map, node, [])

    # Decrement in-degree for each dependent
    new_in_degree =
      Enum.reduce(dependents, in_degree, fn dep, acc ->
        Map.update(acc, dep, 0, &(&1 - 1))
      end)

    # Add newly ready nodes to queue (those with in-degree now 0)
    new_ready =
      dependents
      |> Enum.filter(fn dep -> Map.get(new_in_degree, dep) == 0 end)
      |> Enum.sort()

    do_topological_sort(rest ++ new_ready, new_in_degree, deps_map, [node | result])
  end

  defp find_all_cycles(nodes, adj) do
    {cycles, _} =
      Enum.reduce(nodes, {[], MapSet.new()}, fn node, {cycles_acc, visited} ->
        if MapSet.member?(visited, node) do
          {cycles_acc, visited}
        else
          {new_cycles, new_visited} = dfs_cycles(node, adj, [], MapSet.new(), visited)
          {cycles_acc ++ new_cycles, new_visited}
        end
      end)

    cycles
  end

  @spec dfs_cycles(
          String.t(),
          map(),
          [String.t()],
          MapSet.t(String.t()),
          MapSet.t(String.t())
        ) :: {[[String.t()]], MapSet.t(String.t())}
  defp dfs_cycles(node, adj, path, rec_stack, visited) do
    cond do
      Enum.member?(rec_stack, node) ->
        cycle_from_path(node, path, visited)

      Enum.member?(visited, node) ->
        {[], visited}

      true ->
        explore_cycle_neighbors(node, adj, path, rec_stack, visited)
    end
  end

  @spec calculate_depth(String.t(), map(), MapSet.t(String.t())) :: non_neg_integer()
  defp calculate_depth(node, adj, visited) do
    neighbors = Map.get(adj, node, [])

    cond do
      Enum.member?(visited, node) -> 0
      neighbors == [] -> 0
      true -> 1 + max_child_depth(neighbors, adj, Enum.into([node], visited))
    end
  end

  defp cycle_from_path(node, path, visited) do
    case Enum.find_index(path, &(&1 == node)) do
      nil -> {[], visited}
      cycle_start -> {[Enum.slice(path, cycle_start..-1//1) ++ [node]], visited}
    end
  end

  defp explore_cycle_neighbors(node, adj, path, rec_stack, visited) do
    new_path = path ++ [node]
    new_rec_stack = Enum.into([node], rec_stack)
    neighbors = Map.get(adj, node, [])

    Enum.reduce(neighbors, {[], Enum.into([node], visited)}, fn neighbor, {c_acc, v_acc} ->
      {new_cycles, new_v} = dfs_cycles(neighbor, adj, new_path, new_rec_stack, v_acc)
      {c_acc ++ new_cycles, new_v}
    end)
  end

  defp max_child_depth(neighbors, adj, visited) do
    neighbors
    |> Enum.map(fn neighbor -> calculate_depth(neighbor, adj, visited) end)
    |> Enum.max(fn -> 0 end)
  end
end
