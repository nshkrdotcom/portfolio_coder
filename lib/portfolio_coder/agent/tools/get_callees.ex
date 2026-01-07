defmodule PortfolioCoder.Agent.Tools.GetCallees do
  @moduledoc """
  Tool for finding functions called by a given function.
  """

  @behaviour PortfolioCoder.Agent.Tool

  alias PortfolioCoder.Graph.CallGraph
  alias PortfolioCoder.Graph.InMemoryGraph

  @impl true
  def name, do: :get_callees

  @impl true
  def description do
    "Find all functions called by a given function. Can include transitive callees (callees of callees)."
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
        description: "Include transitive callees (default: false)"
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
          {:ok, callees} = CallGraph.transitive_callees(graph, function_id)
          {:ok, %{function: function_id, callees: callees, transitive: true}}
        else
          {:ok, callees} = InMemoryGraph.callees(graph, function_id)
          {:ok, %{function: function_id, callees: callees, transitive: false}}
        end
    end
  end
end
