defmodule PortfolioCoder.AgentSessionFacadeTest do
  use ExUnit.Case, async: false

  alias PortfolioCoder.AgentSession

  defmodule FailProvider do
    def start_session(_agent_id, _opts), do: {:ok, "fail-session"}
    def execute(_session_id, _prompt, _opts), do: {:error, :timeout}
    def end_session(_session_id), do: :ok
  end

  defmodule OkProvider do
    def start_session(_agent_id, _opts), do: {:ok, "ok-session"}
    def execute(_session_id, _prompt, _opts), do: {:ok, %{output: "ok"}}
    def end_session(_session_id), do: :ok
  end

  test "falls back to next provider on transient error" do
    opts = [
      provider: :auto,
      fallback_providers: [:claude, :codex],
      provider_modules: %{claude: FailProvider, codex: OkProvider},
      store: :noop_store,
      adapter: :noop_adapter,
      retry_attempts: 0
    ]

    assert {:ok, result} = AgentSession.run("hello", opts)
    assert result.provider == :codex
    assert result.output == "ok"
    assert result.session_id == "ok-session"
  end
end
