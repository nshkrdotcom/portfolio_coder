defmodule PortfolioCoder.Search do
  @moduledoc """
  Code search functionality using portfolio_manager's RAG capabilities.
  """

  alias PortfolioCoder.LLM
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

  Options:
    - `:index_id` - Index to query (default: "default")
    - `:strategy` - RAG strategy (default: :hybrid)
    - `:k` - Number of chunks to retrieve (default: 5)
    - `:llm_strategy` - LLM routing strategy for answer generation
  """
  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(question, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, default_index())

    ask_opts =
      opts
      |> Keyword.put(:index_id, index_id)

    case RAG.query(question, ask_opts) do
      {:ok, %{answer: answer}} when is_binary(answer) ->
        {:ok, answer}

      {:ok, %{items: items}} ->
        prompt = build_prompt(question, items)
        messages = [%{role: :user, content: prompt}]

        case LLM.complete(messages, llm_opts(opts)) do
          {:ok, response} ->
            {:ok, extract_answer(response)}

          {:error, reason} ->
            {:error, {:llm_failed, reason, %{context_items: items}}}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Stream an answer.

  Options are the same as `ask/2` plus the stream callback.
  """
  @spec stream_ask(String.t(), (String.t() -> any()), keyword()) :: :ok | {:error, term()}
  def stream_ask(question, callback, opts \\ []) when is_function(callback, 1) do
    index_id = Keyword.get(opts, :index_id, default_index())

    stream_opts =
      opts
      |> Keyword.put(:index_id, index_id)

    case RAG.query(question, stream_opts) do
      {:ok, %{items: items}} ->
        prompt = build_prompt(question, items)
        messages = [%{role: :user, content: prompt}]
        LLM.stream(messages, callback, llm_opts(opts))

      {:ok, %{answer: answer}} when is_binary(answer) ->
        callback.(answer)
        :ok

      {:error, _} = err ->
        err
    end
  end

  defp extract_answer(%{content: content}) when is_binary(content), do: content
  defp extract_answer(%{output: output}) when is_binary(output), do: output
  defp extract_answer(%{text: text}) when is_binary(text), do: text
  defp extract_answer(other), do: inspect(other)

  defp build_prompt(question, context_items) do
    context =
      Enum.map_join(context_items, "\n\n---\n\n", fn item ->
        item[:content] || item.content || ""
      end)

    """
    Answer the question based on the provided context. Be concise and accurate.

    Context:
    #{context}

    Question: #{question}
    """
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

  defp llm_opts(opts) do
    opts
    |> Keyword.drop([:index_id, :k, :limit, :strategy, :filters, :query, :context, :items])
    |> maybe_put(:strategy, Keyword.get(opts, :llm_strategy))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
