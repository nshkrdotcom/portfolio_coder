# examples/17_agent_session_codex_demo.exs
#
# Demonstrates: Codex autonomous agent sessions
# Modules Used: PortfolioCoder.AgentSession
# Prerequisites: OPENAI_API_KEY (or CODEX_API_KEY) and a working directory
#
# Usage: mix run examples/17_agent_session_codex_demo.exs [working_dir]

alias PortfolioCoder.AgentSession

defmodule AgentSessionCodexDemo do
  def run(args) do
    print_header("Codex Agent Session Demo")

    working_dir = resolve_working_dir(args)

    ensure_prereqs(working_dir)

    prompt = "List the top-level files in this repo and summarize what it is."

    IO.puts("Working directory: #{working_dir}")
    IO.puts("Prompt: #{prompt}\n")

    opts =
      [
        provider: :codex,
        working_directory: working_dir,
        print_events: true
      ]
      |> maybe_put(:model, codex_model())

    case AgentSession.run(prompt, opts) do
      {:ok, result} ->
        IO.puts("\nOutput:\n")
        IO.puts(extract_output(result))

      {:error, reason} ->
        IO.puts(:stderr, "Agent session failed: #{inspect(reason)}")
    end
  end

  defp resolve_working_dir(args) do
    case args do
      [path | _] -> Path.expand(path)
      _ -> System.get_env("CODEX_WORKING_DIR") || System.get_env("CODEX_WORKDIR")
    end
  end

  defp ensure_prereqs(working_dir) do
    unless Code.ensure_loaded?(PortfolioIndex.Adapters.AgentSession.Codex) do
      IO.puts(:stderr, "Skipping: Codex agent session adapter not available.")
      System.halt(0)
    end

    if is_nil(working_dir) or working_dir == "" or not File.dir?(working_dir) do
      IO.puts(:stderr, "Skipping: working directory missing or invalid.")
      IO.puts(:stderr, "Provide a path argument or set CODEX_WORKING_DIR.")
      System.halt(0)
    end

    if env_set?("OPENAI_API_KEY") or env_set?("CODEX_API_KEY") do
      IO.puts("Using Codex API credentials\n")
    else
      allow = System.get_env("ALLOW_CODEX_SESSION") == "1"

      if allow do
        IO.puts("OPENAI_API_KEY/CODEX_API_KEY not set; attempting anyway\n")
      else
        IO.puts(:stderr, "Skipping: OPENAI_API_KEY or CODEX_API_KEY not set.")
        IO.puts(:stderr, "Set ALLOW_CODEX_SESSION=1 to run anyway.")
        System.halt(0)
      end
    end
  end

  defp codex_model do
    System.get_env("CODEX_MODEL") || System.get_env("OPENAI_MODEL")
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

AgentSessionCodexDemo.run(System.argv())
