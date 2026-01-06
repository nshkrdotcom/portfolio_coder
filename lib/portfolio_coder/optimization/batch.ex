defmodule PortfolioCoder.Optimization.Batch do
  @moduledoc """
  Batch processing for efficient bulk operations.

  Provides utilities for:
  - Batch embedding generation
  - Parallel file processing
  - Chunked data processing
  - Rate-limited API calls

  ## Usage

      # Process files in parallel
      results = Batch.parallel_map(files, fn file ->
        process_file(file)
      end, max_concurrency: 4)

      # Batch with accumulation
      Batch.stream(large_dataset, batch_size: 100)
      |> Enum.each(&process_batch/1)

      # Rate-limited operations
      Batch.rate_limited(urls, &fetch_url/1, rate: 10, per: :second)
  """

  @type batch_opts :: [
          batch_size: pos_integer(),
          max_concurrency: pos_integer(),
          timeout: pos_integer(),
          on_error: :skip | :raise | :collect
        ]

  @default_batch_size 100
  @default_concurrency 4
  @default_timeout 30_000

  @doc """
  Process items in parallel with controlled concurrency.

  ## Options

  - `:max_concurrency` - Maximum parallel tasks (default: 4)
  - `:timeout` - Timeout per task in ms (default: 30_000)
  - `:on_error` - How to handle errors: :skip, :raise, or :collect (default: :raise)
  """
  @spec parallel_map(Enumerable.t(), (term() -> term()), batch_opts()) :: [term()]
  def parallel_map(items, func, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_concurrency)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    on_error = Keyword.get(opts, :on_error, :raise)

    items
    |> Task.async_stream(
      fn item ->
        try do
          {:ok, func.(item)}
        rescue
          e -> {:error, e, item}
        end
      end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, {:ok, result}} ->
        result

      {:ok, {:error, error, item}} ->
        handle_error(on_error, error, item)

      {:exit, reason} ->
        handle_error(on_error, {:exit, reason}, nil)
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Process items in batches.

  ## Options

  - `:batch_size` - Number of items per batch (default: 100)
  """
  @spec in_batches(Enumerable.t(), (list() -> term()), batch_opts()) :: [term()]
  def in_batches(items, func, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    items
    |> Stream.chunk_every(batch_size)
    |> Enum.map(func)
  end

  @doc """
  Create a stream of batches from items.
  """
  @spec stream(Enumerable.t(), batch_opts()) :: Enumerable.t()
  def stream(items, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    Stream.chunk_every(items, batch_size)
  end

  @doc """
  Process items with rate limiting.

  ## Options

  - `:rate` - Maximum operations per time period (default: 10)
  - `:per` - Time period: :second, :minute, or :hour (default: :second)
  """
  @spec rate_limited(Enumerable.t(), (term() -> term()), keyword()) :: [term()]
  def rate_limited(items, func, opts \\ []) do
    rate = Keyword.get(opts, :rate, 10)
    per = Keyword.get(opts, :per, :second)

    interval_ms = calculate_interval(rate, per)

    items
    |> Enum.map(fn item ->
      result = func.(item)
      Process.sleep(interval_ms)
      result
    end)
  end

  @doc """
  Process with retry on failure.

  ## Options

  - `:max_retries` - Maximum retry attempts (default: 3)
  - `:backoff` - Backoff strategy: :linear, :exponential (default: :exponential)
  - `:base_delay` - Initial delay in ms (default: 1000)
  """
  @spec with_retry((-> term()), keyword()) :: {:ok, term()} | {:error, term()}
  def with_retry(func, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    backoff = Keyword.get(opts, :backoff, :exponential)
    base_delay = Keyword.get(opts, :base_delay, 1000)

    do_retry(func, max_retries, backoff, base_delay, 0)
  end

  @doc """
  Collect items until a batch is ready, then process.

  Returns a function that can be called repeatedly with items.
  When batch_size is reached, the processor function is called.
  """
  @spec collector((list() -> term()), batch_opts()) :: (term() | :flush -> :ok | {:batch, term()})
  def collector(processor, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    buffer = :atomics.new(1, signed: false)
    items_ref = :ets.new(:batch_collector, [:set, :public])

    fn
      :flush ->
        items = :ets.tab2list(items_ref) |> Enum.map(fn {_, v} -> v end)
        :ets.delete_all_objects(items_ref)
        :atomics.put(buffer, 1, 0)

        if length(items) > 0 do
          {:batch, processor.(items)}
        else
          :ok
        end

      item ->
        idx = :atomics.add_get(buffer, 1, 1)
        :ets.insert(items_ref, {idx, item})

        if idx >= batch_size do
          items = :ets.tab2list(items_ref) |> Enum.map(fn {_, v} -> v end)
          :ets.delete_all_objects(items_ref)
          :atomics.put(buffer, 1, 0)
          {:batch, processor.(items)}
        else
          :ok
        end
    end
  end

  @doc """
  Process items with progress tracking.

  ## Options

  - `:on_progress` - Callback function receiving {current, total}
  """
  @spec with_progress(Enumerable.t(), (term() -> term()), keyword()) :: [term()]
  def with_progress(items, func, opts \\ []) do
    on_progress = Keyword.get(opts, :on_progress, fn _, _ -> :ok end)
    items_list = Enum.to_list(items)
    total = length(items_list)

    items_list
    |> Enum.with_index(1)
    |> Enum.map(fn {item, idx} ->
      result = func.(item)
      on_progress.(idx, total)
      result
    end)
  end

  @doc """
  Split work across multiple processes and aggregate results.
  """
  @spec map_reduce(Enumerable.t(), (term() -> term()), (list() -> term()), batch_opts()) :: term()
  def map_reduce(items, mapper, reducer, opts \\ []) do
    items
    |> parallel_map(mapper, opts)
    |> reducer.()
  end

  # Private helpers

  defp handle_error(:skip, _error, _item), do: nil

  defp handle_error(:raise, error, _item) do
    raise error
  end

  defp handle_error(:collect, error, item) do
    {:error, error, item}
  end

  defp calculate_interval(rate, :second), do: div(1000, rate)
  defp calculate_interval(rate, :minute), do: div(60_000, rate)
  defp calculate_interval(rate, :hour), do: div(3_600_000, rate)

  defp do_retry(func, max_retries, backoff, base_delay, attempt) do
    try do
      {:ok, func.()}
    rescue
      e ->
        if attempt < max_retries do
          delay = calculate_delay(backoff, base_delay, attempt)
          Process.sleep(delay)
          do_retry(func, max_retries, backoff, base_delay, attempt + 1)
        else
          {:error, e}
        end
    end
  end

  defp calculate_delay(:linear, base, attempt), do: base * (attempt + 1)
  defp calculate_delay(:exponential, base, attempt), do: (base * :math.pow(2, attempt)) |> round()
end
