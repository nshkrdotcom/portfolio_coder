defmodule PortfolioCoder.Agent.Tools.SearchCode do
  @moduledoc """
  Tool for searching code in the index.
  """

  @behaviour PortfolioCoder.Agent.Tool

  alias PortfolioCoder.Indexer.InMemorySearch

  @impl true
  def name, do: :search_code

  @impl true
  def description do
    "Search for code snippets matching a query. Returns relevant code chunks with file paths and scores."
  end

  @impl true
  def parameters do
    [
      %{name: :query, type: :string, required: true, description: "The search query"},
      %{
        name: :limit,
        type: :integer,
        required: false,
        description: "Maximum number of results (default: 5)"
      },
      %{
        name: :language,
        type: :string,
        required: false,
        description: "Filter by language (elixir, python, etc.)"
      }
    ]
  end

  @impl true
  def execute(params, context) do
    query = params[:query] || params["query"]
    limit = params[:limit] || params["limit"] || 5
    language = params[:language] || params["language"]

    case context[:index] do
      nil ->
        {:error, "No index available. Run code.index first."}

      index ->
        opts = [limit: limit]
        opts = if language, do: Keyword.put(opts, :language, String.to_atom(language)), else: opts

        {:ok, results} = InMemorySearch.search(index, query, opts)

        formatted =
          results
          |> Enum.map(fn r ->
            %{
              path: r.metadata[:relative_path] || r.metadata[:path],
              name: r.metadata[:name],
              type: r.metadata[:type],
              score: Float.round(r.score, 3),
              preview: String.slice(r.content, 0, 300)
            }
          end)

        {:ok, formatted}
    end
  end
end
