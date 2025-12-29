defmodule PortfolioCoder.Tools.SearchCode do
  @moduledoc """
  Code search tool for agents.

  Provides semantic and text-based code search capabilities.
  """

  alias PortfolioCoder.Search

  @doc """
  Get the tool definition for agent registration.
  """
  @spec definition() :: map()
  def definition do
    %{
      name: "search_code",
      description: """
      Search for code in the indexed repositories.
      Supports semantic search using natural language queries.
      """,
      parameters: %{
        type: "object",
        properties: %{
          query: %{
            type: "string",
            description: "The search query (natural language or code snippet)"
          },
          language: %{
            type: "string",
            description:
              "Filter by programming language (elixir, python, javascript, typescript)",
            enum: ["elixir", "python", "javascript", "typescript"]
          },
          file_pattern: %{
            type: "string",
            description: "Filter by file path pattern"
          },
          limit: %{
            type: "integer",
            description: "Maximum number of results (default: 10)",
            default: 10
          },
          index_id: %{
            type: "string",
            description: "The index to search (default: 'default')"
          }
        },
        required: ["query"]
      },
      handler: &__MODULE__.execute/1
    }
  end

  @doc """
  Execute the search_code tool.
  """
  @spec execute(map()) :: {:ok, map()} | {:error, term()}
  def execute(args) do
    query = Map.fetch!(args, "query")

    opts =
      []
      |> maybe_add_opt(:language, args["language"], &String.to_existing_atom/1)
      |> maybe_add_opt(:file_pattern, args["file_pattern"])
      |> maybe_add_opt(:limit, args["limit"])
      |> maybe_add_opt(:index_id, args["index_id"])

    case Search.semantic_search(query, opts) do
      {:ok, results} ->
        formatted = format_results(results)
        {:ok, %{results: formatted, count: length(formatted)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_add_opt(opts, _key, nil, _transform), do: opts
  defp maybe_add_opt(opts, key, value, transform), do: Keyword.put(opts, key, transform.(value))

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp format_results(results) do
    Enum.map(results, fn result ->
      %{
        path: result.path,
        content: truncate_content(result.content, 500),
        score: Float.round(result.score, 3),
        language: result.language
      }
    end)
  end

  defp truncate_content(content, max_length) when byte_size(content) > max_length do
    String.slice(content, 0, max_length) <> "..."
  end

  defp truncate_content(content, _max_length), do: content
end
