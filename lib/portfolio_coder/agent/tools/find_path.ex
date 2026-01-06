defmodule PortfolioCoder.Agent.Tools.FindPath do
  @moduledoc """
  Tool for finding paths between code entities in the graph.
  """

  @behaviour PortfolioCoder.Agent.Tool

  alias PortfolioCoder.Graph.CallGraph

  @impl true
  def name, do: :find_path

  @impl true
  def description do
    "Find the call chain path between two functions in the graph."
  end

  @impl true
  def parameters do
    [
      %{
        name: :from,
        type: :string,
        required: true,
        description: "Starting function ID (e.g., 'ModuleA.func/1')"
      },
      %{
        name: :to,
        type: :string,
        required: true,
        description: "Target function ID (e.g., 'ModuleB.func/2')"
      },
      %{
        name: :max_depth,
        type: :integer,
        required: false,
        description: "Maximum path length to search (default: 10)"
      }
    ]
  end

  @impl true
  def execute(params, context) do
    from = params[:from] || params["from"]
    to = params[:to] || params["to"]
    max_depth = params[:max_depth] || params["max_depth"] || 10

    case context[:graph] do
      nil ->
        {:error, "No graph available. Build a dependency graph first."}

      graph ->
        case CallGraph.call_chain(graph, from, to, max_depth: max_depth) do
          {:ok, path} ->
            {:ok, %{from: from, to: to, path: path, path_length: length(path)}}

          {:error, :no_path} ->
            {:ok,
             %{from: from, to: to, path: nil, message: "No path found between these functions"}}
        end
    end
  end
end
