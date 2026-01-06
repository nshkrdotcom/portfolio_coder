defmodule PortfolioCoder.Agent.Tools.GraphStats do
  @moduledoc """
  Tool for getting graph statistics and overview.
  """

  @behaviour PortfolioCoder.Agent.Tool

  alias PortfolioCoder.Graph.InMemoryGraph
  alias PortfolioCoder.Graph.CallGraph

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
    include_hot_paths = params[:include_hot_paths] || params["include_hot_paths"] || false

    include_entry_points =
      params[:include_entry_points] || params["include_entry_points"] || false

    case context[:graph] do
      nil ->
        {:error, "No graph available. Build a dependency graph first."}

      graph ->
        stats = InMemoryGraph.stats(graph)

        result = %{
          node_count: stats.node_count,
          edge_count: stats.edge_count,
          nodes_by_type: stats.nodes_by_type,
          edges_by_type: stats.edges_by_type
        }

        result =
          if include_hot_paths do
            {:ok, hot} = CallGraph.hot_paths(graph, limit: 5)

            hot_formatted =
              Enum.map(hot, fn h -> %{id: h.id, name: h.name, connectivity: h.connectivity} end)

            Map.put(result, :hot_paths, hot_formatted)
          else
            result
          end

        result =
          if include_entry_points do
            {:ok, entries} = CallGraph.entry_points(graph)

            entry_formatted =
              Enum.take(entries, 10) |> Enum.map(fn e -> %{id: e.id, name: e.name} end)

            Map.put(result, :entry_points, entry_formatted)
          else
            result
          end

        {:ok, result}
    end
  end
end
