defmodule PortfolioCoder.Optimization.Cache do
  @moduledoc """
  Caching layer for expensive operations.

  Provides caching for:
  - Embeddings (to avoid re-computing for same content)
  - Search results (to speed up repeated queries)
  - Parsed ASTs (to avoid re-parsing unchanged files)

  ## Usage

      # Set up cache
      Cache.start_link()

      # Cache embeddings
      Cache.put_embedding("content_hash", [0.1, 0.2, ...])
      embedding = Cache.get_embedding("content_hash")

      # Cache search results
      Cache.put_search("query_hash", results, ttl: 300_000)
      results = Cache.get_search("query_hash")

      # Generic caching
      result = Cache.fetch(:embeddings, key, fn -> compute_expensive() end)
  """

  use GenServer

  @type cache_name :: :embeddings | :search | :ast | :results | atom()

  @default_ttl 300_000
  @max_entries 10_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start the cache if not already running.
  """
  def start(opts \\ []) do
    case Process.whereis(__MODULE__) do
      nil -> start_link(opts)
      pid -> {:ok, pid}
    end
  end

  @doc """
  Get a value from cache, computing it if not present.

  The provided function is only called if the key is not in cache.
  """
  @spec fetch(cache_name(), term(), (-> term()), keyword()) :: term()
  def fetch(cache, key, compute_fn, opts \\ []) do
    case get(cache, key) do
      nil ->
        value = compute_fn.()
        put(cache, key, value, opts)
        value

      value ->
        value
    end
  end

  @doc """
  Get a value from cache.
  """
  @spec get(cache_name(), term()) :: term() | nil
  def get(cache, key) do
    case Process.whereis(__MODULE__) do
      nil -> nil
      _pid -> GenServer.call(__MODULE__, {:get, cache, key})
    end
  end

  @doc """
  Put a value in cache.
  """
  @spec put(cache_name(), term(), term(), keyword()) :: :ok
  def put(cache, key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)

    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.cast(__MODULE__, {:put, cache, key, value, ttl})
    end
  end

  @doc """
  Delete a value from cache.
  """
  @spec delete(cache_name(), term()) :: :ok
  def delete(cache, key) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.cast(__MODULE__, {:delete, cache, key})
    end
  end

  @doc """
  Clear an entire cache namespace.
  """
  @spec clear(cache_name()) :: :ok
  def clear(cache) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.cast(__MODULE__, {:clear, cache})
    end
  end

  @doc """
  Clear all caches.
  """
  @spec clear_all() :: :ok
  def clear_all do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.cast(__MODULE__, :clear_all)
    end
  end

  @doc """
  Get cache statistics.
  """
  @spec stats() :: map()
  def stats do
    case Process.whereis(__MODULE__) do
      nil -> %{}
      _pid -> GenServer.call(__MODULE__, :stats)
    end
  end

  # Convenience functions for specific cache types

  @doc """
  Cache an embedding.
  """
  def put_embedding(content_hash, embedding) do
    put(:embeddings, content_hash, embedding)
  end

  @doc """
  Get a cached embedding.
  """
  def get_embedding(content_hash) do
    get(:embeddings, content_hash)
  end

  @doc """
  Cache search results.
  """
  def put_search(query_hash, results, opts \\ []) do
    put(:search, query_hash, results, opts)
  end

  @doc """
  Get cached search results.
  """
  def get_search(query_hash) do
    get(:search, query_hash)
  end

  @doc """
  Cache a parsed AST.
  """
  def put_ast(file_hash, ast) do
    put(:ast, file_hash, ast)
  end

  @doc """
  Get a cached AST.
  """
  def get_ast(file_hash) do
    get(:ast, file_hash)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Schedule periodic cleanup
    :timer.send_interval(60_000, :cleanup)

    state = %{
      caches: %{},
      hits: 0,
      misses: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:get, cache, key}, _from, state) do
    case get_from_cache(state.caches, cache, key) do
      {:ok, value} ->
        {:reply, value, %{state | hits: state.hits + 1}}

      :miss ->
        {:reply, nil, %{state | misses: state.misses + 1}}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    cache_stats =
      state.caches
      |> Enum.map(fn {name, entries} ->
        {name, %{entries: map_size(entries)}}
      end)
      |> Map.new()

    stats = %{
      caches: cache_stats,
      total_entries: count_all_entries(state.caches),
      hits: state.hits,
      misses: state.misses,
      hit_rate: calculate_hit_rate(state.hits, state.misses)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:put, cache, key, value, ttl}, state) do
    expires_at = System.monotonic_time(:millisecond) + ttl

    entry = %{value: value, expires_at: expires_at}

    caches =
      state.caches
      |> Map.update(cache, %{key => entry}, fn entries ->
        entries = Map.put(entries, key, entry)
        # Enforce max entries with LRU-like eviction
        enforce_max_entries(entries)
      end)

    {:noreply, %{state | caches: caches}}
  end

  @impl true
  def handle_cast({:delete, cache, key}, state) do
    caches =
      Map.update(state.caches, cache, %{}, fn entries ->
        Map.delete(entries, key)
      end)

    {:noreply, %{state | caches: caches}}
  end

  @impl true
  def handle_cast({:clear, cache}, state) do
    caches = Map.delete(state.caches, cache)
    {:noreply, %{state | caches: caches}}
  end

  @impl true
  def handle_cast(:clear_all, state) do
    {:noreply, %{state | caches: %{}, hits: 0, misses: 0}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)

    caches =
      state.caches
      |> Enum.map(fn {name, entries} ->
        cleaned =
          entries
          |> Enum.reject(fn {_key, entry} -> entry.expires_at < now end)
          |> Map.new()

        {name, cleaned}
      end)
      |> Map.new()

    {:noreply, %{state | caches: caches}}
  end

  # Private helpers

  defp get_from_cache(caches, cache, key) do
    now = System.monotonic_time(:millisecond)

    with {:ok, entries} <- Map.fetch(caches, cache),
         {:ok, entry} <- Map.fetch(entries, key),
         true <- entry.expires_at > now do
      {:ok, entry.value}
    else
      _ -> :miss
    end
  end

  defp count_all_entries(caches) do
    caches
    |> Map.values()
    |> Enum.map(&map_size/1)
    |> Enum.sum()
  end

  defp calculate_hit_rate(hits, misses) do
    total = hits + misses

    if total > 0 do
      hits / total * 100
    else
      0.0
    end
  end

  defp enforce_max_entries(entries) when map_size(entries) <= @max_entries do
    entries
  end

  defp enforce_max_entries(entries) do
    # Remove oldest entries (by expiration time)
    entries
    |> Enum.sort_by(fn {_key, entry} -> entry.expires_at end)
    |> Enum.take(@max_entries)
    |> Map.new()
  end
end
