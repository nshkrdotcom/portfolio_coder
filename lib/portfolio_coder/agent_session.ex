defmodule PortfolioCoder.AgentSession do
  @moduledoc """
  Thin facade for autonomous agent sessions (Claude / Codex).

  Delegates to `PortfolioIndex.Adapters.AgentSession.*`, adds provider
  selection, retries, and fallback between providers.
  """

  require Logger

  alias AgentSessionManager.Adapters.{ClaudeAdapter, CodexAdapter, InMemorySessionStore}
  alias PortfolioIndex.Adapters.AgentSession.Config

  @default_fallback [:claude, :codex]
  @default_retry_attempts 1
  @default_retry_delay_ms 200

  @type provider :: :claude | :codex

  @doc """
  Run a prompt through an autonomous agent session.

  Options:
    - `:provider` - :claude | :codex | :auto (default)
    - `:fallback_providers` - fallback order (default: #{inspect(@default_fallback)})
    - `:agent_id` - session agent_id (default: "portfolio_coder")
    - `:event_callback` - function for streaming events
    - `:print_events` - print events to STDOUT (default: false)
    - `:working_directory` - required for codex when no adapter configured
    - `:model` - optional model override for Claude/Codex adapters
    - `:store` / `:adapter` - override session store/adapter
  """
  @spec run(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(prompt, opts \\ []) when is_binary(prompt) do
    providers = resolve_providers(opts)
    retry_attempts = Keyword.get(opts, :retry_attempts, @default_retry_attempts)
    retry_delay_ms = Keyword.get(opts, :retry_delay_ms, @default_retry_delay_ms)

    do_run(prompt, opts, providers, retry_attempts, retry_delay_ms, nil)
  end

  defp do_run(_prompt, _opts, [], _retries, _delay_ms, last_error) do
    {:error, {:all_providers_failed, last_error}}
  end

  defp do_run(prompt, opts, [provider | rest], retries, delay_ms, _last_error) do
    module = provider_module(provider, opts)

    case run_provider(module, provider, prompt, opts, retries, delay_ms) do
      {:ok, _} = success ->
        success

      {:error, reason} = error ->
        Logger.warning("Agent session failed for #{provider}: #{inspect(reason)}")
        do_run(prompt, opts, rest, retries, delay_ms, error)
    end
  end

  defp run_provider(module, provider, prompt, opts, retries, delay_ms) do
    with {:ok, {store, store_owned}} <- ensure_store(opts) do
      case ensure_adapter(provider, opts) do
        {:ok, {adapter, adapter_owned}} ->
          run_session(module, provider, prompt, opts, retries, delay_ms, store, store_owned, adapter, adapter_owned)

        {:error, reason} ->
          cleanup_if_owned(store_owned, false, store, nil)
          {:error, reason}
      end
    end
  end

  defp run_session(module, provider, prompt, opts, retries, delay_ms, store, store_owned, adapter, adapter_owned) do
    case module.start_session(agent_id(opts), session_opts(store, adapter, opts)) do
      {:ok, session_id} ->
        result = execute_with_retry(module, session_id, prompt, opts, retries, delay_ms)
        _ = module.end_session(session_id)
        cleanup_if_owned(store_owned, adapter_owned, store, adapter)

        case result do
          {:ok, data} ->
            {:ok, Map.merge(data, %{provider: provider, session_id: session_id})}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        cleanup_if_owned(store_owned, adapter_owned, store, adapter)
        {:error, reason}
    end
  end

  defp execute_with_retry(module, session_id, prompt, opts, retries, delay_ms) do
    execute_opts = build_execute_opts(opts)

    case module.execute(session_id, prompt, execute_opts) do
      {:ok, _} = ok ->
        ok

      {:error, reason} = error ->
        if retries > 0 and transient_error?(reason) do
          Process.sleep(delay_ms)
          execute_with_retry(module, session_id, prompt, opts, retries - 1, delay_ms)
        else
          error
        end
    end
  end

  defp build_execute_opts(opts) do
    event_callback =
      case {Keyword.get(opts, :event_callback), Keyword.get(opts, :print_events, false)} do
        {callback, _} when is_function(callback, 1) ->
          callback

        {nil, true} ->
          fn event -> IO.puts("agent_event: #{inspect(event)}") end

        _ ->
          nil
      end

    opts
    |> Keyword.drop([
      :print_events,
      :provider,
      :fallback_providers,
      :provider_modules,
      :store,
      :adapter
    ])
    |> maybe_put(:event_callback, event_callback)
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp session_opts(store, adapter, opts) do
    opts
    |> Keyword.take([:context, :metadata, :tags])
    |> Keyword.put(:store, store)
    |> Keyword.put(:adapter, adapter)
  end

  defp resolve_providers(opts) do
    provider = Keyword.get(opts, :provider, :auto)
    fallback = Keyword.get(opts, :fallback_providers, @default_fallback)

    case provider do
      :auto -> fallback
      provider when is_atom(provider) -> [provider | Enum.reject(fallback, &(&1 == provider))]
    end
    |> Enum.filter(&provider_available?(&1, opts))
  end

  defp provider_available?(provider, opts) do
    case provider_module(provider, opts) do
      module when is_atom(module) -> Code.ensure_loaded?(module)
      _ -> false
    end
  end

  defp provider_module(provider, opts) do
    modules = Keyword.get(opts, :provider_modules, %{})

    Map.get(modules, provider) ||
      case provider do
        :claude -> PortfolioIndex.Adapters.AgentSession.Claude
        :codex -> PortfolioIndex.Adapters.AgentSession.Codex
      end
  end

  defp agent_id(opts), do: Keyword.get(opts, :agent_id, "portfolio_coder")

  defp ensure_store(opts) do
    case Keyword.get(opts, :store) do
      nil ->
        case Config.resolve_store(opts) do
          {:error, _} ->
            {:ok, store} = InMemorySessionStore.start_link([])
            {:ok, {store, true}}

          store ->
            {:ok, {store, false}}
        end

      store ->
        {:ok, {store, false}}
    end
  end

  defp ensure_adapter(provider, opts) do
    case Keyword.get(opts, :adapter) do
      nil ->
        case Config.resolve_adapter(provider, opts) do
          {:error, _} ->
            start_adapter(provider, opts)

          adapter ->
            {:ok, {adapter, false}}
        end

      adapter ->
        {:ok, {adapter, false}}
    end
  end

  defp start_adapter(:codex, opts) do
    working_dir =
      Keyword.get(opts, :working_directory) ||
        System.get_env("CODEX_WORKING_DIR") ||
        System.get_env("CODEX_WORKDIR")

    cond do
      is_nil(working_dir) ->
        {:error, {:missing_working_directory, :codex}}

      not File.dir?(working_dir) ->
        {:error, {:invalid_working_directory, working_dir}}

      true ->
        {:ok, adapter} =
          CodexAdapter.start_link(
            working_directory: working_dir,
            model: Keyword.get(opts, :model)
          )

        {:ok, {adapter, true}}
    end
  end

  defp start_adapter(:claude, opts) do
    {:ok, adapter} =
      ClaudeAdapter.start_link(model: Keyword.get(opts, :model))

    {:ok, {adapter, true}}
  end

  defp cleanup_if_owned(store_owned, adapter_owned, store, adapter) do
    if adapter_owned and adapter do
      _ = GenServer.stop(adapter, :normal)
    end

    if store_owned and store do
      _ = GenServer.stop(store, :normal)
    end
  end

  defp transient_error?(reason) do
    case reason do
      :timeout -> true
      {:error, :timeout} -> true
      %{status_code: code} when code in 500..599 -> true
      %{status_code: 429} -> true
      _ -> false
    end
  end
end
