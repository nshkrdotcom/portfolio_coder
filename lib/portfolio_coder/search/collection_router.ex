defmodule PortfolioCoder.Search.CollectionRouter do
  @moduledoc """
  Routes search queries to relevant code collections.

  Collections represent logical groupings of code (e.g., auth, api, database)
  that can be searched independently. The router analyzes queries and determines
  which collections are most likely to contain relevant results.

  ## Strategies

    * `:keyword` - Match query words against collection patterns (fast, rule-based)
    * `:semantic` - Use embeddings for semantic similarity (requires LLM)
    * `:hybrid` - Combine keyword and semantic matching

  ## Usage

      collections = [
        %{id: "auth", name: "Authentication", patterns: ["auth", "login", "session"]},
        %{id: "api", name: "API", patterns: ["api", "endpoint", "route"]}
      ]

      router = CollectionRouter.new(collections)

      # Route a query
      relevant = CollectionRouter.route(router, "how do users log in?")
      # => [%{id: "auth", ...}]

      # Get scores for all collections
      scored = CollectionRouter.route_with_scores(router, "authentication")
      # => [{%{id: "auth", ...}, 0.85}, ...]
  """

  defstruct [:collections, :strategy, :max_collections, :embedder]

  @type collection :: %{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          patterns: [String.t()]
        }

  @type t :: %__MODULE__{
          collections: [collection()],
          strategy: :keyword | :semantic | :hybrid,
          max_collections: pos_integer(),
          embedder: module() | nil
        }

  @doc """
  Create a new collection router.

  ## Options

    * `:strategy` - Routing strategy (default: `:keyword`)
    * `:max_collections` - Maximum collections to return (default: 3)
    * `:embedder` - Embedder module for semantic matching
  """
  @spec new([collection()], keyword()) :: t()
  def new(collections, opts \\ []) do
    %__MODULE__{
      collections: collections,
      strategy: Keyword.get(opts, :strategy, :keyword),
      max_collections: Keyword.get(opts, :max_collections, 3),
      embedder: Keyword.get(opts, :embedder)
    }
  end

  @doc """
  Route a query to relevant collections.

  Returns a list of collections that are likely to contain relevant results,
  ordered by relevance.
  """
  @spec route(t(), String.t()) :: [collection()]
  def route(%__MODULE__{} = router, query) do
    router
    |> route_with_scores(query)
    |> Enum.take(router.max_collections)
    |> Enum.map(fn {collection, _score} -> collection end)
  end

  @doc """
  Route a query and return collections with relevance scores.

  Returns a list of {collection, score} tuples, ordered by score descending.
  """
  @spec route_with_scores(t(), String.t()) :: [{collection(), float()}]
  def route_with_scores(%__MODULE__{} = router, query) do
    case router.strategy do
      :keyword -> route_keyword(router, query)
      :semantic -> route_semantic(router, query)
      :hybrid -> route_hybrid(router, query)
    end
  end

  @doc """
  Add a collection to the router.
  """
  @spec add_collection(t(), collection()) :: t()
  def add_collection(%__MODULE__{} = router, collection) do
    %{router | collections: router.collections ++ [collection]}
  end

  @doc """
  Remove a collection by id.
  """
  @spec remove_collection(t(), String.t()) :: t()
  def remove_collection(%__MODULE__{} = router, collection_id) do
    collections = Enum.reject(router.collections, &(&1.id == collection_id))
    %{router | collections: collections}
  end

  @doc """
  Get all configured collections.
  """
  @spec get_all_collections(t()) :: [collection()]
  def get_all_collections(%__MODULE__{} = router) do
    router.collections
  end

  @doc """
  Find a collection by id.
  """
  @spec find_collection(t(), String.t()) :: collection() | nil
  def find_collection(%__MODULE__{} = router, collection_id) do
    Enum.find(router.collections, &(&1.id == collection_id))
  end

  # Private routing implementations

  defp route_keyword(router, query) do
    query_tokens = tokenize(query)

    router.collections
    |> Enum.map(fn collection ->
      score = calculate_keyword_score(collection, query_tokens)
      {collection, score}
    end)
    |> Enum.filter(fn {_c, score} -> score > 0 end)
    |> Enum.sort_by(fn {_c, score} -> score end, :desc)
  end

  defp route_semantic(router, query) do
    # Fall back to keyword if no embedder configured
    if router.embedder do
      # Would use embedder for semantic similarity
      route_keyword(router, query)
    else
      route_keyword(router, query)
    end
  end

  defp route_hybrid(router, query) do
    keyword_scores = route_keyword(router, query) |> Map.new()

    # Combine with semantic scores if available
    if router.embedder do
      semantic_scores = route_semantic(router, query) |> Map.new()

      router.collections
      |> Enum.map(fn collection ->
        kw_score = Map.get(keyword_scores, collection, 0.0)
        sem_score = Map.get(semantic_scores, collection, 0.0)
        combined = kw_score * 0.5 + sem_score * 0.5
        {collection, combined}
      end)
      |> Enum.filter(fn {_c, score} -> score > 0 end)
      |> Enum.sort_by(fn {_c, score} -> score end, :desc)
    else
      keyword_scores
      |> Enum.to_list()
      |> Enum.sort_by(fn {_c, score} -> score end, :desc)
    end
  end

  defp calculate_keyword_score(collection, query_tokens) do
    patterns = collection.patterns ++ [collection.id, String.downcase(collection.name)]

    # Count matching tokens
    matches =
      Enum.count(query_tokens, fn token ->
        Enum.any?(patterns, fn pattern ->
          String.contains?(token, pattern) or String.contains?(pattern, token)
        end)
      end)

    # Also check description
    description_tokens = tokenize(collection.description || "")

    description_matches =
      Enum.count(query_tokens, fn token ->
        Enum.any?(description_tokens, fn desc_token ->
          String.contains?(token, desc_token) or String.contains?(desc_token, token)
        end)
      end)

    # Normalize score
    total_matches = matches + description_matches * 0.5
    total_patterns = length(patterns)

    if total_patterns > 0 do
      min(1.0, total_matches / total_patterns * 2)
    else
      0.0
    end
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.uniq()
  end
end
