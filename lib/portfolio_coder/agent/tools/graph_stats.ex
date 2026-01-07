defmodule PortfolioCoder.Agent.Tools.GraphStats do
  @moduledoc """
  Tool for getting graph statistics and overview.
  """

  @behaviour PortfolioCoder.Agent.Tool

  alias PortfolioCoder.Graph.CallGraph
  alias PortfolioCoder.Graph.InMemoryGraph

  @impl true
  def name, do: :graph_stats

  @impl true
  def description do
    "Get statistics about the code graph including node counts, edge counts, entry points, and hot paths."
  end

  @impl true
  def parameters do
    [
      %{
        name: :include_hot_paths,
        type: :boolean,
        required: false,
        description: "Include hot paths (most connected functions). Default: false"
      },
      %{
        name: :include_entry_points,
        type: :boolean,
        required: false,
        description: "Include entry points (functions with no callers). Default: false"
      }
    ]
  end

  @impl true
  def execute(params, context) do
    include_hot_paths = bool_param(params, :include_hot_paths)
    include_entry_points = bool_param(params, :include_entry_points)

    case context[:graph] do
      nil ->
        {:error, "No graph available. Build a dependency graph first."}

      graph ->
        result =
          graph
          |> base_stats()
          |> maybe_add_hot_paths(graph, include_hot_paths)
          |> maybe_add_entry_points(graph, include_entry_points)

        {:ok, result}
    end
  end

  defp bool_param(params, key) when is_map(params) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key)) || false
  end

  defp bool_param(params, key) when is_list(params) do
    Keyword.get(params, key, false)
  end

  defp base_stats(graph) do
    stats = InMemoryGraph.stats(graph)

    %{
      node_count: stats.node_count,
      edge_count: stats.edge_count,
      nodes_by_type: stats.nodes_by_type,
      edges_by_type: stats.edges_by_type
    }
  end

  defp maybe_add_hot_paths(result, graph, true) do
    {:ok, hot} = CallGraph.hot_paths(graph, limit: 5)

    hot_formatted =
      Enum.map(hot, fn h -> %{id: h.id, name: h.name, connectivity: h.connectivity} end)

    Map.put(result, :hot_paths, hot_formatted)
  end

  defp maybe_add_hot_paths(result, _graph, false), do: result

  defp maybe_add_entry_points(result, graph, true) do
    {:ok, entries} = CallGraph.entry_points(graph)

    entry_formatted =
      Enum.take(entries, 10) |> Enum.map(fn e -> %{id: e.id, name: e.name} end)

    Map.put(result, :entry_points, entry_formatted)
  end

  defp maybe_add_entry_points(result, _graph, false), do: result
end
