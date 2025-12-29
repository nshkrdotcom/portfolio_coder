defmodule PortfolioCoder.Search do
  @moduledoc """
  Code search functionality using portfolio_manager's RAG capabilities.
  """

  alias PortfolioManager.RAG

  @doc """
  Semantic code search.
  """
  @spec semantic_search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def semantic_search(query, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, default_index())
    limit = Keyword.get(opts, :limit, 10)

    search_opts =
      opts
      |> Keyword.put(:index_id, index_id)
      |> Keyword.put(:k, limit)

    case RAG.search(query, search_opts) do
      {:ok, results} ->
        filtered = filter_results(results, opts)
        {:ok, format_results(filtered)}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Text-based code search.
  """
  @spec text_search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def text_search(query, opts \\ []) do
    # For now, use semantic search
    # In the future, add full-text search support
    semantic_search(query, opts)
  end

  @doc """
  Ask a question about the codebase.
  """
  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(question, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, default_index())

    ask_opts =
      opts
      |> Keyword.put(:index_id, index_id)

    RAG.ask(question, ask_opts)
  end

  @doc """
  Stream an answer.
  """
  @spec stream_ask(String.t(), (String.t() -> any()), keyword()) :: :ok | {:error, term()}
  def stream_ask(question, callback, opts \\ []) when is_function(callback, 1) do
    index_id = Keyword.get(opts, :index_id, default_index())

    stream_opts =
      opts
      |> Keyword.put(:index_id, index_id)

    RAG.stream_query(question, callback, stream_opts)
  end

  @doc """
  Find usages of a symbol.
  """
  @spec find_usages(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def find_usages(symbol, opts \\ []) do
    # Search for the symbol
    query = "usage of #{symbol} OR reference to #{symbol} OR calls to #{symbol}"
    semantic_search(query, opts)
  end

  # Private functions

  defp filter_results(results, opts) do
    results
    |> filter_by_language(opts[:language])
    |> filter_by_file_pattern(opts[:file_pattern])
  end

  defp filter_by_language(results, nil), do: results

  defp filter_by_language(results, language) do
    Enum.filter(results, fn result ->
      metadata = result[:metadata] || %{}
      metadata[:language] == language
    end)
  end

  defp filter_by_file_pattern(results, nil), do: results

  defp filter_by_file_pattern(results, pattern) do
    Enum.filter(results, fn result ->
      metadata = result[:metadata] || %{}
      path = metadata[:path] || ""
      String.contains?(path, pattern)
    end)
  end

  defp format_results(results) do
    Enum.map(results, fn result ->
      %{
        content: result[:content] || "",
        score: result[:score] || 0.0,
        path: get_in(result, [:metadata, :path]) || "",
        language: get_in(result, [:metadata, :language]) || :unknown,
        metadata: result[:metadata] || %{}
      }
    end)
  end

  defp default_index do
    Application.get_env(:portfolio_coder, :default_index, "default")
  end
end
