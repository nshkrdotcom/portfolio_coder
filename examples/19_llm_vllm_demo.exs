# examples/19_llm_vllm_demo.exs
#
# Demonstrates: vLLM adapter usage
# Modules Used: PortfolioCoder.LLM
# Prerequisites: VLLM_ENABLED=1 (or VLLM_BASE_URL/VLLM_URL) and a working vLLM setup
#
# Usage: mix run examples/19_llm_vllm_demo.exs

alias PortfolioCoder.LLM

defmodule VLLMDemo do
  def run do
    print_header("vLLM Demo")

    ensure_prereqs()

    prompt = "Summarize the purpose of this repo in two sentences."
    messages = [%{role: :user, content: prompt}]

    opts =
      [
        providers: [
          %{name: :vllm, module: PortfolioIndex.Adapters.LLM.VLLM, config: %{}, priority: 1}
        ],
        max_tokens: 200
      ]
      |> maybe_put(:model, System.get_env("VLLM_MODEL"))

    case LLM.complete(messages, opts) do
      {:ok, response} ->
        IO.puts("Response:\n#{extract_answer(response)}")

      {:error, reason} ->
        IO.puts(:stderr, "vLLM error: #{LLM.format_error(reason)}")
    end
  end

  defp ensure_prereqs do
    unless Code.ensure_loaded?(PortfolioIndex.Adapters.LLM.VLLM) do
      IO.puts(:stderr, "Skipping: vLLM adapter not available.")
      System.halt(0)
    end

    if vllm_enabled?() do
      IO.puts("Using vLLM provider\n")
    else
      IO.puts(:stderr, "Skipping: vLLM not enabled.")
      IO.puts(:stderr, "Set VLLM_ENABLED=1 (or VLLM_BASE_URL/VLLM_URL) to run.")
      System.halt(0)
    end
  end

  defp vllm_enabled? do
    env_set?("VLLM_ENABLED") or env_set?("VLLM_BASE_URL") or env_set?("VLLM_URL") or
      System.get_env("ALLOW_VLLM") == "1"
  end

  defp env_set?(key) do
    case System.get_env(key) do
      value when is_binary(value) and value != "" -> true
      _ -> false
    end
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

VLLMDemo.run()
