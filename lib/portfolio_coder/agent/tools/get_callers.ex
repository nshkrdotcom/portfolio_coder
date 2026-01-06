defmodule PortfolioCoder.Agent.Tools.GetCallers do
  @moduledoc """
  Tool for finding functions that call a given function.
  """

  @behaviour PortfolioCoder.Agent.Tool

  alias PortfolioCoder.Graph.InMemoryGraph
  alias PortfolioCoder.Graph.CallGraph

  @impl true
  def name, do: :get_callers

  @impl true
  def description do
    "Find all functions that call a given function. Can include transitive callers (callers of callers)."
  end

  @impl true
  def parameters do
    [
      %{
        name: :function_id,
        type: :string,
        required: true,
        description: "The function ID (e.g., 'MyModule.my_func/2')"
      },
      %{
        name: :transitive,
        type: :boolean,
        required: false,
        description: "Include transitive callers (default: false)"
      }
    ]
  end

  @impl true
  def execute(params, context) do
    function_id = params[:function_id] || params["function_id"]
    transitive = params[:transitive] || params["transitive"] || false

    case context[:graph] do
      nil ->
        {:error, "No graph available. Build a dependency graph first."}

      graph ->
        if transitive do
          {:ok, callers} = CallGraph.transitive_callers(graph, function_id)
          {:ok, %{function: function_id, callers: callers, transitive: true}}
        else
          {:ok, callers} = InMemoryGraph.callers(graph, function_id)
          {:ok, %{function: function_id, callers: callers, transitive: false}}
        end
    end
  end
end
