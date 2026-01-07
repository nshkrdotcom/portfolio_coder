defmodule PortfolioCoder.Indexer.InMemorySearch do
  @moduledoc """
  Simple in-memory code search without external dependencies.

  This module provides text-based search functionality for code that has been
  parsed and chunked. It's useful for demos, testing, and small codebases where
  a full vector database isn't needed.

  ## Features

  - Keyword-based search with TF-IDF-like scoring
  - Filter by language, file type, symbol type
  - No external dependencies required
  - Results ranked by relevance

  ## Usage

      # Create a search index
      {:ok, index} = InMemorySearch.new()

      # Add documents
      :ok = InMemorySearch.add(index, %{
        id: "file.ex:func1",
        content: "def hello(name), do: \"Hello \#{name}\"",
        metadata: %{path: "lib/file.ex", language: :elixir, type: :function}
      })

      # Search
      {:ok, results} = InMemorySearch.search(index, "hello")
  """

  use GenServer

  @type index :: GenServer.server()
  @type document :: %{
          id: String.t(),
          content: String.t(),
          metadata: map()
        }
  @type result :: %{
          id: String.t(),
          content: String.t(),
          score: float(),
          metadata: map()
        }

  # Client API

  @doc """
  Create a new search index.
  """
  @spec new(keyword()) :: {:ok, index()} | {:error, term()}
  def new(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Add a document to the index.
  """
  @spec add(index(), document()) :: :ok
  def add(index, document) do
    GenServer.call(index, {:add, document})
  end

  @doc """
  Add multiple documents to the index.
  """
  @spec add_all(index(), [document()]) :: :ok
  def add_all(index, documents) do
    GenServer.call(index, {:add_all, documents})
  end

  @doc """
  Search the index.

  ## Options

    - `:limit` - Maximum results (default: 10)
    - `:min_score` - Minimum relevance score (default: 0.0)
    - `:language` - Filter by language
    - `:type` - Filter by document type
    - `:path_pattern` - Filter by path pattern
  """
  @spec search(index(), String.t(), keyword()) :: {:ok, [result()]}
  def search(index, query, opts \\ []) do
    GenServer.call(index, {:search, query, opts})
  end

  @doc """
  Get index statistics.
  """
  @spec stats(index()) :: map()
  def stats(index) do
    GenServer.call(index, :stats)
  end

  @doc """
  Clear all documents from the index.
  """
  @spec clear(index()) :: :ok
  def clear(index) do
    GenServer.call(index, :clear)
  end

  # Server implementation

  @impl GenServer
  def init(_opts) do
    state = %{
      documents: %{},
      term_index: %{},
      doc_count: 0
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:add, document}, _from, state) do
    state = do_add(state, document)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:add_all, documents}, _from, state) do
    state = Enum.reduce(documents, state, &do_add(&2, &1))
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:search, query, opts}, _from, state) do
    results = do_search(state, query, opts)
    {:reply, {:ok, results}, state}
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    stats = %{
      document_count: state.doc_count,
      term_count: map_size(state.term_index)
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_call(:clear, _from, _state) do
    state = %{
      documents: %{},
      term_index: %{},
      doc_count: 0
    }

    {:reply, :ok, state}
  end

  # Private functions

  defp do_add(state, document) do
    id = document.id
    content = document.content || ""
    terms = tokenize(content)

    # Store document
    documents = Map.put(state.documents, id, document)

    # Update term index
    term_index =
      Enum.reduce(terms, state.term_index, fn term, idx ->
        postings = Map.get(idx, term, [])
        Map.put(idx, term, [id | postings])
      end)

    %{state | documents: documents, term_index: term_index, doc_count: state.doc_count + 1}
  end

  defp do_search(state, query, opts) do
    limit = Keyword.get(opts, :limit, 10)
    min_score = Keyword.get(opts, :min_score, 0.0)

    query_terms = tokenize(query)

    if Enum.empty?(query_terms) do
      []
    else
      # Calculate scores for each document
      scores =
        state.documents
        |> Enum.map(fn {id, doc} ->
          score = calculate_score(state, doc, query_terms)
          {id, doc, score}
        end)
        |> Enum.filter(fn {_, _, score} -> score > min_score end)
        |> Enum.sort_by(fn {_, _, score} -> -score end)
        |> Enum.take(limit)
        |> Enum.filter(fn {_, doc, _} -> matches_filters?(doc, opts) end)
        |> Enum.map(fn {id, doc, score} ->
          %{
            id: id,
            content: doc.content,
            score: score,
            metadata: doc.metadata
          }
        end)

      scores
    end
  end

  defp calculate_score(state, doc, query_terms) do
    content = doc.content || ""
    doc_terms = tokenize(content)
    doc_term_set = MapSet.new(doc_terms)
    doc_term_freq = Enum.frequencies(doc_terms)
    doc_term_count = max(length(doc_terms), 1)

    # Simple TF-IDF-like scoring
    Enum.reduce(query_terms, 0.0, fn term, acc ->
      if MapSet.member?(doc_term_set, term) do
        acc + tf_idf_score(state, doc_term_freq, doc_term_count, term)
      else
        acc + partial_match_bonus(doc_terms, term)
      end
    end)
  end

  defp matches_filters?(doc, opts) do
    language = Keyword.get(opts, :language)
    type = Keyword.get(opts, :type)
    path_pattern = Keyword.get(opts, :path_pattern)

    metadata = doc.metadata || %{}

    matches_language?(metadata, language) and
      matches_type?(metadata, type) and
      matches_path?(metadata, path_pattern)
  end

  defp tf_idf_score(state, doc_term_freq, doc_term_count, term) do
    tf = Map.get(doc_term_freq, term, 0) / doc_term_count
    df = length(Map.get(state.term_index, term, []))
    idf = :math.log(state.doc_count / max(df, 1)) + 1
    tf * idf
  end

  defp partial_match_bonus(doc_terms, term) do
    Enum.reduce(doc_terms, 0.0, fn doc_term, bonus ->
      if String.contains?(doc_term, term) or String.contains?(term, doc_term) do
        bonus + 0.1
      else
        bonus
      end
    end)
  end

  defp matches_language?(_metadata, nil), do: true
  defp matches_language?(metadata, language), do: metadata[:language] == language

  defp matches_type?(_metadata, nil), do: true
  defp matches_type?(metadata, type), do: metadata[:type] == type

  defp matches_path?(_metadata, nil), do: true

  defp matches_path?(metadata, path_pattern),
    do: String.contains?(metadata[:path] || "", path_pattern)

  defp tokenize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.filter(&(String.length(&1) >= 2))
    |> Enum.uniq()
  end

  defp tokenize(_), do: []
end
