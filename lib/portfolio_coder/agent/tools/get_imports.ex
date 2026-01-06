defmodule PortfolioCoder.Agent.Tools.GetImports do
  @moduledoc """
  Tool for finding module imports/dependencies.
  """

  @behaviour PortfolioCoder.Agent.Tool

  alias PortfolioCoder.Graph.InMemoryGraph

  @impl true
  def name, do: :get_imports

  @impl true
  def description do
    "Find all modules imported/used by a given module, or find all modules that import a given module."
  end

  @impl true
  def parameters do
    [
      %{
        name: :module_id,
        type: :string,
        required: true,
        description: "The module name (e.g., 'MyApp.Users')"
      },
      %{
        name: :direction,
        type: :string,
        required: false,
        description:
          "Direction: 'imports' (what this module imports) or 'imported_by' (what imports this module). Default: 'imports'"
      }
    ]
  end

  @impl true
  def execute(params, context) do
    module_id = params[:module_id] || params["module_id"]
    direction = params[:direction] || params["direction"] || "imports"

    case context[:graph] do
      nil ->
        {:error, "No graph available. Build a dependency graph first."}

      graph ->
        case direction do
          "imports" ->
            {:ok, imports} = InMemoryGraph.imports_of(graph, module_id)
            {:ok, %{module: module_id, imports: imports}}

          "imported_by" ->
            {:ok, importers} = InMemoryGraph.imported_by(graph, module_id)
            {:ok, %{module: module_id, imported_by: importers}}

          _ ->
            {:error, "Invalid direction. Use 'imports' or 'imported_by'."}
        end
    end
  end
end
