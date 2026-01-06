defmodule PortfolioCoder.LLM.Router do
  @moduledoc """
  Multi-provider LLM routing with intelligent strategies.

  The Router manages multiple LLM providers and intelligently routes
  requests based on various strategies:

  - **:fallback** - Try providers in priority order, skip unhealthy ones
  - **:specialist** - Route based on task type (code, reasoning, quick)
  - **:round_robin** - Cycle through providers for load balancing
  - **:cost_optimized** - Minimize cost while maintaining quality

  ## Features

  - Provider health tracking
  - Automatic failover
  - Latency and success rate metrics
  - Task type inference
  - Cost/quality optimization

  ## Usage

      # Create a router with fallback strategy
      router = Router.new(
        strategy: :fallback,
        providers: [:claude, :gpt4, :gemini]
      )

      # Select provider for a request
      {:ok, provider} = Router.select_provider(router, "fix this bug", [])

      # Record result to update health
      router = Router.record_result(router, provider, {:ok, response})
  """

  defstruct [
    :strategy,
    :providers,
    :routing_rules,
    :costs,
    :quality,
    :budget_per_hour,
    :min_quality,
    :round_robin_index,
    :health,
    :stats
  ]

  @type strategy :: :fallback | :specialist | :round_robin | :cost_optimized

  @type t :: %__MODULE__{
          strategy: strategy(),
          providers: [atom()],
          routing_rules: map(),
          costs: map(),
          quality: map(),
          budget_per_hour: float() | nil,
          min_quality: float() | nil,
          round_robin_index: non_neg_integer(),
          health: map(),
          stats: map()
        }

  @type provider_stats :: %{
          success_count: non_neg_integer(),
          failure_count: non_neg_integer(),
          total_latency: non_neg_integer(),
          avg_latency: float()
        }

  # Keywords for task type inference
  @code_keywords ~w(code bug fix debug refactor implement function module class method test)
  @quick_keywords ~w(yes no true false correct simple short)
  @reasoning_keywords ~w(explain why analyze compare reason think understand)

  @doc """
  Create a new router with the specified strategy and options.

  ## Options

  - `:strategy` - Routing strategy (:fallback, :specialist, :round_robin, :cost_optimized)
  - `:providers` - List of provider atoms in priority order
  - `:routing_rules` - Map of task_type => provider for specialist routing
  - `:costs` - Map of provider => cost_per_1k_tokens
  - `:quality` - Map of provider => quality_score (0.0-1.0)
  - `:budget_per_hour` - Budget limit for cost_optimized strategy
  - `:min_quality` - Minimum quality threshold for cost_optimized strategy

  ## Examples

      Router.new(strategy: :fallback, providers: [:claude, :gpt4])

      Router.new(
        strategy: :specialist,
        routing_rules: %{code: :claude, quick: :gemini, default: :gpt4}
      )
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :fallback)
    providers = Keyword.get(opts, :providers, [])

    %__MODULE__{
      strategy: strategy,
      providers: providers,
      routing_rules: Keyword.get(opts, :routing_rules, %{}),
      costs: Keyword.get(opts, :costs, %{}),
      quality: Keyword.get(opts, :quality, %{}),
      budget_per_hour: Keyword.get(opts, :budget_per_hour),
      min_quality: Keyword.get(opts, :min_quality, 0.0),
      round_robin_index: 0,
      health: Map.new(providers, &{&1, :healthy}),
      stats: Map.new(providers, &{&1, default_stats()})
    }
  end

  @doc """
  Select a provider for the given message using the router's strategy.

  ## Options

  - `:task_type` - Override inferred task type (for specialist strategy)
  - `:health` - Override health map

  ## Returns

  - `{:ok, provider}` - Selected provider atom
  - `{:error, reason}` - No provider available
  """
  @spec select_provider(t(), String.t(), keyword()) :: {:ok, atom()} | {:error, String.t()}
  def select_provider(router, message, opts \\ []) do
    case select_provider_with_state(router, message, opts) do
      {:ok, provider, _router} -> {:ok, provider}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Select a provider and return updated router state.

  Used for stateful strategies like round_robin.
  """
  @spec select_provider_with_state(t(), String.t(), keyword()) ::
          {:ok, atom(), t()} | {:error, String.t()}
  def select_provider_with_state(router, message, opts \\ []) do
    health = Keyword.get(opts, :health, router.health)
    router = %{router | health: Map.merge(router.health, health)}

    case router.strategy do
      :fallback ->
        select_fallback(router, opts)

      :specialist ->
        select_specialist(router, message, opts)

      :round_robin ->
        select_round_robin(router, opts)

      :cost_optimized ->
        select_cost_optimized(router, opts)
    end
  end

  @doc """
  Record the result of a provider call to update health and stats.

  ## Options

  - `:latency_ms` - Request latency in milliseconds
  """
  @spec record_result(t(), atom(), {:ok, term()} | {:error, term()}, keyword()) :: t()
  def record_result(router, provider, result, opts \\ []) do
    latency = Keyword.get(opts, :latency_ms, 0)

    # Update stats
    stats = Map.get(router.stats, provider, default_stats())

    updated_stats =
      case result do
        {:ok, _} ->
          %{
            stats
            | success_count: stats.success_count + 1,
              total_latency: stats.total_latency + latency
          }
          |> update_avg_latency()

        {:error, _} ->
          %{stats | failure_count: stats.failure_count + 1}
      end

    # Update health based on recent results
    health = update_health(router.health, provider, result, updated_stats)

    %{router | stats: Map.put(router.stats, provider, updated_stats), health: health}
  end

  @doc """
  Check if a provider is healthy.
  """
  @spec provider_healthy?(t(), atom()) :: boolean()
  def provider_healthy?(router, provider) do
    Map.get(router.health, provider, :healthy) == :healthy
  end

  @doc """
  Get statistics for a provider.
  """
  @spec get_stats(t(), atom()) :: provider_stats()
  def get_stats(router, provider) do
    Map.get(router.stats, provider, default_stats())
  end

  @doc """
  Infer the task type from message content.

  Returns one of:
  - `:code` - Code-related tasks
  - `:quick` - Simple yes/no questions
  - `:reasoning` - Tasks requiring explanation
  - `:general` - Default for unmatched tasks
  """
  @spec infer_task_type(String.t()) :: atom()
  def infer_task_type(message) do
    message_lower = String.downcase(message)
    words = String.split(message_lower, ~r/\W+/)

    cond do
      has_keywords?(words, @code_keywords) -> :code
      has_keywords?(words, @quick_keywords) and String.length(message) < 50 -> :quick
      has_keywords?(words, @reasoning_keywords) -> :reasoning
      true -> :general
    end
  end

  # Private helpers

  defp default_stats do
    %{
      success_count: 0,
      failure_count: 0,
      total_latency: 0,
      avg_latency: 0.0
    }
  end

  defp update_avg_latency(stats) do
    total_calls = stats.success_count + stats.failure_count

    avg =
      if total_calls > 0 do
        stats.total_latency / stats.success_count
      else
        0.0
      end

    %{stats | avg_latency: avg}
  end

  defp update_health(health, provider, result, stats) do
    case result do
      {:ok, _} ->
        # Success - mark healthy
        Map.put(health, provider, :healthy)

      {:error, _} ->
        # Check failure rate
        total = stats.success_count + stats.failure_count

        failure_rate =
          if total > 0 do
            stats.failure_count / total
          else
            0
          end

        # Mark unhealthy if >50% failure rate with at least 3 calls
        if failure_rate > 0.5 and total >= 3 do
          Map.put(health, provider, :unhealthy)
        else
          health
        end
    end
  end

  defp select_fallback(router, _opts) do
    case Enum.find(router.providers, &provider_healthy?(router, &1)) do
      nil -> {:error, "No available provider"}
      provider -> {:ok, provider, router}
    end
  end

  defp select_specialist(router, message, opts) do
    task_type = Keyword.get(opts, :task_type) || infer_task_type(message)

    provider =
      Map.get(router.routing_rules, task_type) ||
        Map.get(router.routing_rules, :default) ||
        List.first(router.providers)

    if provider do
      {:ok, provider, router}
    else
      {:error, "No provider configured for task type: #{task_type}"}
    end
  end

  defp select_round_robin(router, _opts) do
    healthy_providers = Enum.filter(router.providers, &provider_healthy?(router, &1))

    if healthy_providers == [] do
      {:error, "No available provider"}
    else
      index = rem(router.round_robin_index, length(healthy_providers))
      provider = Enum.at(healthy_providers, index)
      updated_router = %{router | round_robin_index: router.round_robin_index + 1}
      {:ok, provider, updated_router}
    end
  end

  defp select_cost_optimized(router, _opts) do
    min_quality = router.min_quality || 0.0

    # Filter by health and quality
    eligible =
      router.providers
      |> Enum.filter(&provider_healthy?(router, &1))
      |> Enum.filter(fn provider ->
        quality = Map.get(router.quality, provider, 1.0)
        quality >= min_quality
      end)

    if eligible == [] do
      {:error, "No available provider meeting quality requirements"}
    else
      # Sort by cost (cheapest first)
      sorted =
        Enum.sort_by(eligible, fn provider ->
          Map.get(router.costs, provider, 0.0)
        end)

      {:ok, List.first(sorted), router}
    end
  end

  defp has_keywords?(words, keywords) do
    Enum.any?(words, &(&1 in keywords))
  end
end
