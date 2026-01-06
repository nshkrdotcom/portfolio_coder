defmodule PortfolioCoder.Telemetry do
  @moduledoc """
  Telemetry and observability for the code intelligence engine.

  Tracks metrics for:
  - Query latency and throughput
  - Embedding generation times
  - LLM API calls and token usage
  - Search quality metrics
  - Cache hit rates
  - Error rates

  ## Usage

      # Start collecting metrics
      Telemetry.start()

      # Execute with timing
      Telemetry.span(:search, %{query: query}, fn ->
        Search.execute(query)
      end)

      # Record custom metric
      Telemetry.record(:embedding_time, 150, %{model: "text-embedding-3-small"})

      # Get summary
      Telemetry.summary()
  """

  use GenServer

  @type metric_type :: :counter | :gauge | :histogram | :summary

  @type metric :: %{
          name: atom(),
          type: metric_type(),
          value: number(),
          tags: map(),
          timestamp: DateTime.t()
        }

  # Client API

  @doc """
  Start the telemetry collector.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Start the telemetry system (shorthand for supervision tree).
  """
  def start(opts \\ []) do
    case Process.whereis(__MODULE__) do
      nil -> start_link(opts)
      pid -> {:ok, pid}
    end
  end

  @doc """
  Execute a function and record its duration.

  ## Example

      Telemetry.span(:search, %{query_type: :semantic}, fn ->
        execute_search()
      end)
  """
  @spec span(atom(), map(), (-> any())) :: any()
  def span(name, metadata \\ %{}, func) do
    start_time = System.monotonic_time(:microsecond)

    try do
      result = func.()
      duration = System.monotonic_time(:microsecond) - start_time
      record(name, duration, Map.put(metadata, :status, :ok))
      result
    rescue
      e ->
        duration = System.monotonic_time(:microsecond) - start_time
        record(name, duration, Map.put(metadata, :status, :error))
        reraise e, __STACKTRACE__
    end
  end

  @doc """
  Record a metric value.
  """
  @spec record(atom(), number(), map()) :: :ok
  def record(name, value, tags \\ %{}) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.cast(__MODULE__, {:record, name, value, tags})
    end
  end

  @doc """
  Increment a counter metric.
  """
  @spec increment(atom(), map()) :: :ok
  def increment(name, tags \\ %{}) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.cast(__MODULE__, {:increment, name, tags})
    end
  end

  @doc """
  Set a gauge metric.
  """
  @spec gauge(atom(), number(), map()) :: :ok
  def gauge(name, value, tags \\ %{}) do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.cast(__MODULE__, {:gauge, name, value, tags})
    end
  end

  @doc """
  Get summary statistics for all metrics.
  """
  @spec summary() :: map()
  def summary do
    case Process.whereis(__MODULE__) do
      nil -> %{}
      _pid -> GenServer.call(__MODULE__, :summary)
    end
  end

  @doc """
  Get detailed metrics for a specific metric name.
  """
  @spec get_metric(atom()) :: map() | nil
  def get_metric(name) do
    case Process.whereis(__MODULE__) do
      nil -> nil
      _pid -> GenServer.call(__MODULE__, {:get_metric, name})
    end
  end

  @doc """
  Get all metrics in raw form.
  """
  @spec get_all_metrics() :: [metric()]
  def get_all_metrics do
    case Process.whereis(__MODULE__) do
      nil -> []
      _pid -> GenServer.call(__MODULE__, :get_all_metrics)
    end
  end

  @doc """
  Reset all metrics.
  """
  @spec reset() :: :ok
  def reset do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      _pid -> GenServer.call(__MODULE__, :reset)
    end
  end

  @doc """
  Export metrics to a map for external systems.
  """
  @spec export() :: map()
  def export do
    summary = summary()

    %{
      timestamp: DateTime.utc_now(),
      metrics: summary,
      system: %{
        memory: :erlang.memory(:total),
        process_count: :erlang.system_info(:process_count),
        scheduler_utilization: scheduler_utilization()
      }
    }
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      metrics: %{},
      counters: %{},
      gauges: %{},
      histograms: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:record, name, value, tags}, state) do
    timestamp = DateTime.utc_now()

    metric = %{
      name: name,
      type: :histogram,
      value: value,
      tags: tags,
      timestamp: timestamp
    }

    histograms =
      Map.update(state.histograms, name, [metric], fn existing ->
        # Keep last 1000 entries per metric
        entries = [metric | existing]
        Enum.take(entries, 1000)
      end)

    {:noreply, %{state | histograms: histograms}}
  end

  @impl true
  def handle_cast({:increment, name, tags}, state) do
    key = {name, tags}

    counters =
      Map.update(state.counters, key, 1, fn count ->
        count + 1
      end)

    {:noreply, %{state | counters: counters}}
  end

  @impl true
  def handle_cast({:gauge, name, value, tags}, state) do
    key = {name, tags}
    gauges = Map.put(state.gauges, key, {value, DateTime.utc_now()})

    {:noreply, %{state | gauges: gauges}}
  end

  @impl true
  def handle_call(:summary, _from, state) do
    summary = %{
      histograms: summarize_histograms(state.histograms),
      counters: summarize_counters(state.counters),
      gauges: summarize_gauges(state.gauges)
    }

    {:reply, summary, state}
  end

  @impl true
  def handle_call({:get_metric, name}, _from, state) do
    result = %{
      histogram: Map.get(state.histograms, name, []),
      counter: get_counter_value(state.counters, name),
      gauge: get_gauge_value(state.gauges, name)
    }

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_all_metrics, _from, state) do
    metrics =
      state.histograms
      |> Map.values()
      |> List.flatten()

    {:reply, metrics, state}
  end

  @impl true
  def handle_call(:reset, _from, _state) do
    new_state = %{
      metrics: %{},
      counters: %{},
      gauges: %{},
      histograms: %{}
    }

    {:reply, :ok, new_state}
  end

  # Private helpers

  defp summarize_histograms(histograms) do
    histograms
    |> Enum.map(fn {name, entries} ->
      values = Enum.map(entries, & &1.value)

      stats = %{
        count: length(values),
        min: safe_min(values),
        max: safe_max(values),
        mean: safe_mean(values),
        p50: percentile(values, 50),
        p95: percentile(values, 95),
        p99: percentile(values, 99)
      }

      {name, stats}
    end)
    |> Map.new()
  end

  defp summarize_counters(counters) do
    counters
    |> Enum.group_by(fn {{name, _tags}, _count} -> name end)
    |> Enum.map(fn {name, entries} ->
      total = Enum.sum(Enum.map(entries, fn {_, count} -> count end))

      by_tags =
        entries
        |> Enum.map(fn {{_, tags}, count} -> %{tags: tags, count: count} end)

      {name, %{total: total, by_tags: by_tags}}
    end)
    |> Map.new()
  end

  defp summarize_gauges(gauges) do
    gauges
    |> Enum.map(fn {{name, tags}, {value, timestamp}} ->
      {name, %{value: value, tags: tags, timestamp: timestamp}}
    end)
    |> Enum.group_by(fn {name, _} -> name end)
    |> Enum.map(fn {name, entries} ->
      values = Enum.map(entries, fn {_, data} -> data end)
      {name, values}
    end)
    |> Map.new()
  end

  defp get_counter_value(counters, name) do
    counters
    |> Enum.filter(fn {{n, _}, _} -> n == name end)
    |> Enum.map(fn {_, count} -> count end)
    |> Enum.sum()
  end

  defp get_gauge_value(gauges, name) do
    gauges
    |> Enum.filter(fn {{n, _}, _} -> n == name end)
    |> Enum.map(fn {_, {value, _}} -> value end)
    |> List.first()
  end

  defp safe_min([]), do: 0
  defp safe_min(values), do: Enum.min(values)

  defp safe_max([]), do: 0
  defp safe_max(values), do: Enum.max(values)

  defp safe_mean([]), do: 0.0
  defp safe_mean(values), do: Enum.sum(values) / length(values)

  defp percentile([], _p), do: 0

  defp percentile(values, p) do
    sorted = Enum.sort(values)
    index = ceil(length(sorted) * p / 100) - 1
    Enum.at(sorted, max(index, 0))
  end

  defp scheduler_utilization do
    # Return a simple float for scheduler utilization estimate
    # based on process count vs. scheduler count
    schedulers = :erlang.system_info(:schedulers_online)
    processes = :erlang.system_info(:process_count)

    # Simple heuristic: ratio of processes to schedulers, capped at 1.0
    min(processes / (schedulers * 100), 1.0)
  end
end
