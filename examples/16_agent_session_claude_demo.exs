# examples/16_agent_session_claude_demo.exs
#
# Demonstrates: Claude autonomous agent sessions
# Modules Used: PortfolioCoder.AgentSession
# Prerequisites: ANTHROPIC_API_KEY (or `claude login` session)
#
# Usage: mix run examples/16_agent_session_claude_demo.exs

alias PortfolioCoder.AgentSession

defmodule AgentSessionClaudeDemo do
  def run do
    print_header("Claude Agent Session Demo")
    ensure_prereqs()

    prompt = "Summarize the architecture of this repo in 5 bullet points."

    IO.puts("Prompt: #{prompt}\n")

    opts =
      [
        provider: :claude,
        print_events: true
      ]
      |> maybe_put(:model, claude_model())

    case AgentSession.run(prompt, opts) do
      {:ok, result} ->
        IO.puts("\nOutput:\n")
        IO.puts(extract_output(result))

      {:error, reason} ->
        IO.puts(:stderr, "Agent session failed: #{inspect(reason)}")
    end
  end

  defp ensure_prereqs do
    unless Code.ensure_loaded?(PortfolioIndex.Adapters.AgentSession.Claude) do
      IO.puts(:stderr, "Skipping: Claude agent session adapter not available.")
      System.halt(0)
    end

    if env_set?("ANTHROPIC_API_KEY") do
      IO.puts("Using ANTHROPIC_API_KEY\n")
    else
      allow = System.get_env("ALLOW_CLAUDE_SESSION") == "1"

      if allow do
        IO.puts("ANTHROPIC_API_KEY not set; relying on claude login session\n")
      else
        IO.puts(:stderr, "Skipping: ANTHROPIC_API_KEY not set.")
        IO.puts(:stderr, "Set ALLOW_CLAUDE_SESSION=1 to run with claude login.")
        System.halt(0)
      end
    end
  end

  defp claude_model do
    System.get_env("CLAUDE_MODEL") || System.get_env("ANTHROPIC_MODEL")
  end

  defp env_set?(key) do
    case System.get_env(key) do
      value when is_binary(value) and value != "" -> true
      _ -> false
    end
  end

  defp extract_output(%{output: output}) when is_binary(output), do: output
  defp extract_output(%{content: content}) when is_binary(content), do: content
  defp extract_output(%{text: text}) when is_binary(text), do: text
  defp extract_output(other), do: inspect(other)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp print_header(text) do
    IO.puts(String.duplicate("=", 70))
    IO.puts(text)
    IO.puts(String.duplicate("=", 70))
    IO.puts("")
  end
end

AgentSessionClaudeDemo.run()
