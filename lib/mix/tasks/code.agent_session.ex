defmodule Mix.Tasks.Code.AgentSession do
  @moduledoc """
  Run an autonomous agent session (Claude or Codex).

  Usage:

      mix code.agent_session "Explain the architecture" [OPTIONS]

  Options:
    --provider auto|claude|codex   Provider selection (default: auto)
    --fallback claude,codex        Fallback order (default: claude,codex)
    --working-dir PATH             Working directory for Codex
    --model MODEL                  Model override
    --print-events                 Print streaming events
  """

  use Mix.Task

  alias PortfolioCoder.AgentSession

  @shortdoc "Run an autonomous agent session"

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:portfolio_coder)

    {opts, prompt_parts, _} =
      OptionParser.parse(args,
        strict: [
          provider: :string,
          fallback: :string,
          "working-dir": :string,
          model: :string,
          "print-events": :boolean,
          help: :boolean
        ],
        aliases: [p: :provider, f: :fallback, m: :model, h: :help]
      )

    if opts[:help] do
      IO.puts(@moduledoc)
    else
      prompt = Enum.join(prompt_parts, " ")

      if prompt == "" do
        Mix.shell().error("Error: Please provide a prompt")
        exit({:shutdown, 1})
      end

      run_session(prompt, opts)
    end
  end

  defp run_session(prompt, opts) do
    provider = parse_provider(opts[:provider] || "auto")
    fallback = parse_fallback(opts[:fallback] || "claude,codex")
    working_dir = opts[:"working-dir"]
    model = opts[:model]
    print_events = opts[:"print-events"] || false

    session_opts =
      [
        provider: provider,
        fallback_providers: fallback,
        print_events: print_events
      ]
      |> maybe_put(:working_directory, working_dir)
      |> maybe_put(:model, model)

    Mix.shell().info("Provider: #{provider}")
    Mix.shell().info("Fallback: #{Enum.join(fallback, ", ")}\n")

    case AgentSession.run(prompt, session_opts) do
      {:ok, result} ->
        Mix.shell().info("Output:\n")
        Mix.shell().info(extract_output(result))

      {:error, reason} ->
        Mix.shell().error("Agent session failed: #{inspect(reason)}")
    end
  end

  defp parse_provider("auto"), do: :auto
  defp parse_provider("claude"), do: :claude
  defp parse_provider("codex"), do: :codex
  defp parse_provider(other), do: String.to_atom(other)

  defp parse_fallback(list) do
    list
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.to_atom/1)
  end

  defp extract_output(%{output: output}) when is_binary(output), do: output
  defp extract_output(%{content: content}) when is_binary(content), do: content
  defp extract_output(%{text: text}) when is_binary(text), do: text
  defp extract_output(other), do: inspect(other)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
