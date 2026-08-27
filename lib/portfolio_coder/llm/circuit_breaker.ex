defmodule PortfolioCoder.LLM.CircuitBreaker do
  @moduledoc """
  Lightweight circuit breaker for LLM providers.

  Tracks failures in a short window and applies temporary cooldowns
  for providers that are repeatedly failing. Fatal failures trigger
  longer cooldowns.
  """

  @table __MODULE__
  @default_failure_window_ms 60_000
  @default_failure_threshold 2
  @default_transient_cooldown_ms 60_000
  @default_fatal_cooldown_ms 15 * 60_000

  @type provider :: atom()

  @doc """
  Returns true if the provider is currently in a cooldown window.
  """
  @spec blocked?(provider(), keyword()) :: boolean()
  def blocked?(provider, _opts \\ []) do
    ensure_table()
    now = now_ms()

    case :ets.lookup(@table, provider) do
      [{^provider, %{cooldown_until: cooldown_until}}] when is_integer(cooldown_until) ->
        cooldown_until > now

      _ ->
        false
    end
  end

  @doc """
  Record a successful call and clear failure counters.
  """
  @spec record_success(provider()) :: :ok
  def record_success(provider) do
    ensure_table()

    :ets.insert(@table, {provider, %{count: 0, last_failure_at: nil, cooldown_until: nil}})
    :ok
  end

  @doc """
  Record a failure for a provider.

  Options:
    - `:class` - :transient or :fatal
    - `:failure_window_ms` - time window for counting failures
    - `:failure_threshold` - number of failures before cooldown
    - `:transient_cooldown_ms` - cooldown after transient failures
    - `:fatal_cooldown_ms` - cooldown after fatal failures
  """
  @spec record_failure(provider(), :transient | :fatal, keyword()) :: :ok
  def record_failure(provider, class, opts \\ []) do
    ensure_table()

    window = Keyword.get(opts, :failure_window_ms, @default_failure_window_ms)
    threshold = Keyword.get(opts, :failure_threshold, @default_failure_threshold)
    transient_cooldown = Keyword.get(opts, :transient_cooldown_ms, @default_transient_cooldown_ms)
    fatal_cooldown = Keyword.get(opts, :fatal_cooldown_ms, @default_fatal_cooldown_ms)

    now = now_ms()

    state =
      case :ets.lookup(@table, provider) do
        [{^provider, stored}] -> stored
        _ -> %{count: 0, last_failure_at: nil, cooldown_until: nil}
      end

    {count, last_failure_at} =
      if is_integer(state.last_failure_at) and now - state.last_failure_at <= window do
        {state.count + 1, now}
      else
        {1, now}
      end

    cooldown_until =
      case class do
        :fatal -> now + fatal_cooldown
        :transient when count >= threshold -> now + transient_cooldown
        _ -> state.cooldown_until
      end

    :ets.insert(@table, {provider, %{count: count, last_failure_at: last_failure_at, cooldown_until: cooldown_until}})
    :ok
  end

  @doc """
  Clears all circuit breaker state (useful for tests).
  """
  @spec reset() :: :ok
  def reset do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
