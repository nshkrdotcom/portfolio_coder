# examples/18_llm_ollama_demo.exs
#
# Demonstrates: Ollama LLM adapter usage
# Modules Used: PortfolioCoder.LLM
# Prerequisites: OLLAMA_BASE_URL or OLLAMA_HOST (local Ollama server)
#
# Usage: mix run examples/18_llm_ollama_demo.exs

alias PortfolioCoder.LLM

defmodule OllamaDemo do
  def run do
    print_header("Ollama LLM Demo")

    ensure_prereqs()

    prompt = "Explain in one sentence what this repo does."
    messages = [%{role: :user, content: prompt}]

    opts =
      [
        providers: [
          %{name: :ollama, module: PortfolioIndex.Adapters.LLM.Ollama, config: %{}, priority: 1}
        ],
        max_tokens: 200
      ]
      |> maybe_put(:model, System.get_env("OLLAMA_MODEL"))
      |> maybe_put(:base_url, ollama_base_url())

    case LLM.complete(messages, opts) do
      {:ok, response} ->
        IO.puts("Response:\n#{extract_answer(response)}")

      {:error, reason} ->
        IO.puts(:stderr, "Ollama error: #{LLM.format_error(reason)}")
    end
  end

  defp ensure_prereqs do
    unless Code.ensure_loaded?(PortfolioIndex.Adapters.LLM.Ollama) do
      IO.puts(:stderr, "Skipping: Ollama adapter not available.")
      System.halt(0)
    end

    if ollama_base_url() || allow_ollama?() do
      IO.puts("Using Ollama provider\n")
    else
      IO.puts(:stderr, "Skipping: OLLAMA_BASE_URL or OLLAMA_HOST not set.")
      IO.puts(:stderr, "Set ALLOW_OLLAMA=1 to run with config-based settings.")
      System.halt(0)
    end
  end

  defp allow_ollama?, do: System.get_env("ALLOW_OLLAMA") == "1"

  defp ollama_base_url do
    System.get_env("OLLAMA_BASE_URL") || System.get_env("OLLAMA_HOST")
  end

  defp extract_answer(%{content: content}) when is_binary(content), do: content
  defp extract_answer(%{output: output}) when is_binary(output), do: output
  defp extract_answer(%{text: text}) when is_binary(text), do: text
  defp extract_answer(other), do: inspect(other)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp print_header(text) do
    IO.puts(String.duplicate("=", 70))
    IO.puts(text)
    IO.puts(String.duplicate("=", 70))
    IO.puts("")
  end
end

OllamaDemo.run()
