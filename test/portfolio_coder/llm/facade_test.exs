defmodule PortfolioCoder.LLMFacadeTest do
  use ExUnit.Case, async: false

  alias PortfolioCoder.LLM
  alias PortfolioCoder.LLM.CircuitBreaker

  defmodule FailProvider do
    def complete(_messages, _opts), do: {:error, %{status_code: 429, code: "insufficient_quota"}}
  end

  defmodule OkProvider do
    def complete(_messages, _opts), do: {:ok, %{content: "ok"}}
  end

  defmodule TransientFailProvider do
    def complete(_messages, _opts) do
      Process.put(:transient_calls, (Process.get(:transient_calls, 0) + 1))
      {:error, %{status_code: 503}}
    end
  end

  setup do
    CircuitBreaker.reset()
    Process.delete(:transient_calls)
    :ok
  end

  test "classify_error flags insufficient quota as fatal" do
    assert {:fatal, :insufficient_quota} =
             LLM.classify_error({:error, %{status_code: 429, code: "insufficient_quota"}})
  end

  test "classify_error flags rate limit as transient" do
    assert {:transient, :rate_limited} =
             LLM.classify_error({:error, %{status_code: 429, code: "rate_limit"}})
  end

  test "falls back to next provider on fatal error" do
    providers = [
      %{name: :fail, module: FailProvider, config: %{}, priority: 1},
      %{name: :ok, module: OkProvider, config: %{}, priority: 2}
    ]

    assert {:ok, %{content: "ok"}} =
             LLM.complete([%{role: :user, content: "hi"}], providers: providers, retry_attempts: 0)
  end

  test "circuit breaker skips provider after threshold" do
    providers = [
      %{name: :flaky, module: TransientFailProvider, config: %{}, priority: 1},
      %{name: :ok, module: OkProvider, config: %{}, priority: 2}
    ]

    assert {:ok, %{content: "ok"}} =
             LLM.complete([%{role: :user, content: "hi"}],
               providers: providers,
               retry_attempts: 0,
               circuit_breaker: [failure_threshold: 1, transient_cooldown_ms: 60_000]
             )

    assert Process.get(:transient_calls) == 1

    assert {:ok, %{content: "ok"}} =
             LLM.complete([%{role: :user, content: "hi again"}],
               providers: providers,
               retry_attempts: 0,
               circuit_breaker: [failure_threshold: 1, transient_cooldown_ms: 60_000]
             )

    assert Process.get(:transient_calls) == 1
  end
end
