defmodule PortfolioCoder.LLM do
  @moduledoc """
  LLM facade with provider routing and graceful degradation.

  Uses `PortfolioManager.Router` for provider selection when available, and
  adds error classification, retries, and a circuit breaker for cooldowns.
  """

  require Logger

  alias PortfolioCoder.LLM.CircuitBreaker
  alias PortfolioManager.Router

  @default_retry_attempts 2
  @default_retry_delay_ms 200
  @default_jitter_ms 75
  @default_strategy :fallback

  @type provider :: %{
          name: atom(),
          module: module() | nil,
          config: map(),
          priority: non_neg_integer()
        }

  @doc """
  Complete a message list with graceful fallback.

  Options:
    - `:providers` - override provider list (skips router)
    - `:strategy` - router strategy (default: :fallback)
    - `:task_type` - router task type override
    - `:retry_attempts` - retries for transient errors (default: #{@default_retry_attempts})
    - `:retry_delay_ms` - base delay for retries (default: #{@default_retry_delay_ms})
    - `:circuit_breaker` - options forwarded to circuit breaker
  """
  @spec complete([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def complete(messages, opts \\ []) when is_list(messages) do
    run_with_fallback(:complete, messages, opts)
  end

  @doc """
  Stream a response with graceful fallback.

  The callback receives each streamed chunk.
  """
  @spec stream([map()], (String.t() -> any()), keyword()) :: :ok | {:error, term()}
  def stream(messages, callback, opts \\ []) when is_list(messages) and is_function(callback, 1) do
    run_with_fallback(:stream, messages, Keyword.put(opts, :callback, callback))
  end

  @doc """
  Classify an error as `:fatal` or `:transient`.
  """
  @spec classify_error(term()) :: {:fatal | :transient, atom()}
  def classify_error(error) do
    reason = unwrap_error(error)
    status_code = extract_status_code(reason)
    error_code = extract_error_code(reason)

    cond do
      insufficient_quota?(status_code, error_code, reason) -> {:fatal, :insufficient_quota}
      status_code in [401, 403] -> {:fatal, :unauthorized}
      status_code == 404 -> {:fatal, :not_found}
      status_code == 429 -> {:transient, :rate_limited}
      status_code in 500..599 -> {:transient, :server_error}
      transient_reason?(reason) -> {:transient, :network}
      true -> {:fatal, :unknown}
    end
  end

  @doc """
  Build a short user-facing error message.
  """
  @spec format_error(term()) :: String.t()
  def format_error(:no_providers), do: "No LLM providers configured."
  def format_error({:all_providers_failed, reason}), do: "All providers failed. Last error: #{inspect(reason)}"
  def format_error(error) do
    {class, reason} = classify_error(error)

    case {class, reason} do
      {:fatal, :insufficient_quota} ->
        "Provider quota exhausted (insufficient quota). Configure another provider or update billing."

      {:fatal, :unauthorized} ->
        "Provider authentication failed. Check your API key."

      {:transient, :rate_limited} ->
        "Provider rate limited. Retrying or falling back to another provider."

      _ ->
        "Provider error (#{class}): #{inspect(error)}"
    end
  end

  # Internal execution

  defp run_with_fallback(type, messages, opts) do
    providers = resolve_providers(messages, opts)

    case providers do
      [] ->
        {:error, :no_providers}

      provider_list ->
        attempts = Keyword.get(opts, :retry_attempts, @default_retry_attempts)
        delay_ms = Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms)
        circuit_opts = Keyword.get(opts, :circuit_breaker, [])

        try_providers(type, messages, opts, provider_list, attempts, delay_ms, circuit_opts, nil)
    end
  end

  defp try_providers(_type, _messages, _opts, [], _attempts, _delay_ms, _cb_opts, last_error) do
    {:error, {:all_providers_failed, last_error}}
  end

  defp try_providers(type, messages, opts, [provider | rest], attempts, delay_ms, cb_opts, _last_error) do
    context = %{
      type: type,
      messages: messages,
      opts: opts,
      provider: provider,
      rest: rest,
      attempts: attempts,
      delay_ms: delay_ms,
      cb_opts: cb_opts
    }

    if CircuitBreaker.blocked?(provider.name, cb_opts) do
      try_providers(type, messages, opts, rest, attempts, delay_ms, cb_opts, :blocked)
    else
      handle_provider_call(context)
    end
  end

  defp handle_provider_call(%{type: type, messages: messages, opts: opts, provider: provider} = context) do
    case call_provider(type, provider, messages, opts) do
      {:ok, _} = success ->
        CircuitBreaker.record_success(provider.name)
        success

      :ok ->
        CircuitBreaker.record_success(provider.name)
        :ok

      {:error, reason} = error ->
        handle_provider_error(context, reason, error)
    end
  end

  defp handle_provider_error(
         %{
           type: type,
           messages: messages,
           opts: opts,
           provider: provider,
           rest: rest,
           attempts: attempts,
           delay_ms: delay_ms,
           cb_opts: cb_opts
         },
         reason,
         error
       ) do
    {class, _reason} = classify_error(reason)
    CircuitBreaker.record_failure(provider.name, class, cb_opts)
    maybe_report(provider.name, :failure, reason)

    case {class, attempts} do
      {:transient, n} when n > 0 ->
        backoff_sleep(delay_ms, attempts)
        try_providers(type, messages, opts, [provider | rest], attempts - 1, delay_ms, cb_opts, error)

      _ ->
        try_providers(type, messages, opts, rest, attempts, delay_ms, cb_opts, error)
    end
  end

  defp call_provider(:complete, provider, messages, opts) do
    llm_opts = build_llm_opts(provider, opts)

    result =
      case provider.module do
        module when is_atom(module) ->
          module.complete(messages, llm_opts)

        _ ->
          PortfolioManager.LLM.complete(messages, llm_opts)
      end

    maybe_report(provider.name, :success, result)
    result
  rescue
    e -> {:error, e}
  end

  defp call_provider(:stream, provider, messages, opts) do
    callback = Keyword.fetch!(opts, :callback)
    llm_opts = build_llm_opts(provider, opts)

    result =
      case provider.module do
        module when is_atom(module) ->
          module.stream(messages, llm_opts)

        _ ->
          PortfolioManager.LLM.stream(messages, llm_opts)
      end

    case result do
      {:ok, stream} ->
        Enum.each(stream, callback)
        maybe_report(provider.name, :success, :ok)
        :ok

      {:error, _} = error ->
        error
    end
  rescue
    e -> {:error, e}
  end

  defp build_llm_opts(provider, opts) do
    provider_opts = provider.config |> Enum.into([])
    internal_keys = [:providers, :strategy, :task_type, :retry_attempts, :retry_delay_ms, :circuit_breaker, :callback]
    Keyword.merge(provider_opts, Keyword.drop(opts, internal_keys))
  end

  defp resolve_providers(messages, opts) do
    case Keyword.get(opts, :providers) do
      nil ->
        ensure_router_started(opts)
        case Process.whereis(Router) do
          nil -> normalize_providers(default_providers())
          _pid -> select_providers_from_router(messages, opts)
        end

      providers ->
        normalize_providers(providers)
    end
  end

  defp select_providers_from_router(messages, opts) do
    strategy = Keyword.get(opts, :strategy, @default_strategy)
    route_opts = opts |> Keyword.put(:strategy, strategy) |> Keyword.delete(:providers)

    case Router.route(messages, route_opts) do
      {:ok, provider} ->
        build_provider_sequence(provider, route_opts)

      {:error, _} ->
        Router.list_providers() |> normalize_providers()
    end
  end

  defp build_provider_sequence(first, opts) do
    providers =
      Stream.unfold(first, fn current ->
        case Router.next_provider(current.name, opts) do
          {:ok, next_provider} -> {current, next_provider}
          {:error, :no_more} -> {current, nil}
        end
      end)
      |> Enum.to_list()

    normalize_providers(providers)
  end

  defp normalize_providers(providers) do
    providers
    |> Enum.map(fn provider ->
      %{
        name: provider.name,
        module: Map.get(provider, :module),
        config: Map.get(provider, :config, %{}),
        priority: Map.get(provider, :priority, 1)
      }
    end)
    |> Enum.sort_by(& &1.priority)
  end

  defp ensure_router_started(opts) do
    case Process.whereis(Router) do
      nil ->
        router_opts = build_router_opts(opts)

        case Router.start_link(router_opts) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> Logger.warning("Failed to start LLM router: #{inspect(reason)}")
        end

      _pid ->
        :ok
    end

    ensure_default_providers()
  end

  defp build_router_opts(opts) do
    configured = Application.get_env(:portfolio_coder, :llm_router, [])
    strategy = Keyword.get(opts, :strategy, Keyword.get(configured, :strategy, @default_strategy))
    providers = Keyword.get(configured, :providers, default_providers())

    [strategy: strategy, providers: providers]
  end

  defp ensure_default_providers do
    with pid when is_pid(pid) <- Process.whereis(Router),
         [] <- Router.list_providers() do
      Enum.each(default_providers(), &Router.register_provider/1)
    end

    :ok
  end

  defp default_providers do
    order = Application.get_env(:portfolio_coder, :llm_provider_order, [
      :gemini,
      :anthropic,
      :openai,
      :codex,
      :ollama,
      :vllm
    ])

    order
    |> Enum.reduce([], fn provider, acc ->
      case provider_definition(provider) do
        nil -> acc
        defn -> acc ++ [defn]
      end
    end)
  end

  defp provider_definition(:gemini) do
    if (env_set?("GEMINI_API_KEY") || config_key_present?(:gemini_ex, :api_key, :api_key) ||
          config_key_present?(:portfolio_index, :gemini, :api_key)) &&
         Code.ensure_loaded?(PortfolioIndex.Adapters.LLM.Gemini) do
      %{name: :gemini, module: PortfolioIndex.Adapters.LLM.Gemini, config: %{}, priority: 1}
    end
  end

  defp provider_definition(:anthropic) do
    if (env_set?("ANTHROPIC_API_KEY") || config_key_present?(:portfolio_index, :anthropic, :api_key)) &&
         Code.ensure_loaded?(PortfolioIndex.Adapters.LLM.Anthropic) do
      %{name: :anthropic, module: PortfolioIndex.Adapters.LLM.Anthropic, config: %{}, priority: 2}
    end
  end

  defp provider_definition(:openai) do
    if (env_set?("OPENAI_API_KEY") || config_key_present?(:portfolio_index, :openai, :api_key)) &&
         Code.ensure_loaded?(PortfolioIndex.Adapters.LLM.OpenAI) do
      %{name: :openai, module: PortfolioIndex.Adapters.LLM.OpenAI, config: %{}, priority: 3}
    end
  end

  defp provider_definition(:codex) do
    if (env_set?("CODEX_API_KEY") || config_present?(:portfolio_index, :codex)) &&
         Code.ensure_loaded?(PortfolioIndex.Adapters.LLM.Codex) do
      %{name: :codex, module: PortfolioIndex.Adapters.LLM.Codex, config: %{}, priority: 4}
    end
  end

  defp provider_definition(:ollama) do
    if (env_set?("OLLAMA_BASE_URL") || env_set?("OLLAMA_HOST") ||
          config_present?(:portfolio_index, :ollama)) &&
         Code.ensure_loaded?(PortfolioIndex.Adapters.LLM.Ollama) do
      %{name: :ollama, module: PortfolioIndex.Adapters.LLM.Ollama, config: %{}, priority: 5}
    end
  end

  defp provider_definition(:vllm) do
    if (env_set?("VLLM_BASE_URL") || env_set?("VLLM_URL") ||
          env_set?("VLLM_ENABLED") || config_present?(:portfolio_index, :vllm)) &&
         Code.ensure_loaded?(PortfolioIndex.Adapters.LLM.VLLM) do
      %{name: :vllm, module: PortfolioIndex.Adapters.LLM.VLLM, config: %{}, priority: 6}
    end
  end

  defp provider_definition(_), do: nil

  defp backoff_sleep(delay_ms, attempt) do
    jitter = :rand.uniform(@default_jitter_ms)
    Process.sleep(delay_ms * attempt + jitter)
  end

  defp maybe_report(provider_name, result, meta) do
    case Process.whereis(Router) do
      nil -> :ok
      _pid -> do_report(provider_name, result, meta)
    end
  end

  defp do_report(provider_name, :success, _meta) do
    Router.report_result(provider_name, :success, %{})
  end

  defp do_report(provider_name, :failure, meta) do
    Router.report_result(provider_name, :failure, %{error: meta})
  end

  # Error classification helpers

  defp unwrap_error({:error, reason}), do: reason
  defp unwrap_error(reason), do: reason

  defp extract_status_code(%{status_code: code}) when is_integer(code), do: code
  defp extract_status_code(%{"status_code" => code}) when is_integer(code), do: code
  defp extract_status_code(%{body: %{"status" => code}}) when is_integer(code), do: code
  defp extract_status_code(_), do: nil

  defp extract_error_code(%{code: code}) when is_binary(code), do: code
  defp extract_error_code(%{type: code}) when is_binary(code), do: code
  defp extract_error_code(%{body: %{"code" => code}}) when is_binary(code), do: code
  defp extract_error_code(_), do: nil

  defp insufficient_quota?(status, code, reason) do
    status == 429 and
      (code == "insufficient_quota" or
         code == "billing_hard_limit_reached" or
         String.contains?(inspect(reason), "insufficient_quota"))
  end

  defp transient_reason?(%{reason: reason}) when is_atom(reason), do: transient_reason?(reason)
  defp transient_reason?(%{error: reason}), do: transient_reason?(reason)
  defp transient_reason?(reason) when is_atom(reason), do: reason in transient_atoms()
  defp transient_reason?(reason) when is_binary(reason),
    do: String.contains?(String.downcase(reason), "timeout")

  defp transient_reason?(_), do: false

  defp transient_atoms do
    [:timeout, :nxdomain, :econnrefused, :closed, :econnreset, :enetunreach]
  end

  defp env_set?(key) do
    case System.get_env(key) do
      value when is_binary(value) and value != "" -> true
      _ -> false
    end
  end

  defp config_present?(app, key) do
    case Application.get_env(app, key) do
      nil -> false
      [] -> false
      _ -> true
    end
  end

  defp config_key_present?(app, key, config_key) do
    case Application.get_env(app, key) do
      opts when is_list(opts) -> Keyword.get(opts, config_key) not in [nil, ""]
      opts when is_map(opts) -> Map.get(opts, config_key) not in [nil, ""]
      value when is_binary(value) -> value != ""
      _ -> false
    end
  end
end
