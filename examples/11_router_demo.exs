# examples/11_router_demo.exs
#
# Demonstrates: Multi-Provider LLM Routing
# Modules Used: PortfolioManager.Router, PortfolioCoder.LLM
# Prerequisites: At least one configured LLM provider
#
# Usage: mix run examples/11_router_demo.exs
#
# This demo shows how to route requests to different LLM providers based on:
# 1. Task complexity
# 2. Cost optimization
# 3. Provider availability
# 4. Specific capability requirements

alias PortfolioCoder.LLM
alias PortfolioManager.Router

defmodule RouterDemo do
  @moduledoc """
  Demonstrates intelligent LLM routing between providers.
  """

  def run do
    print_header("Multi-Provider LLM Router Demo")

    providers = configured_providers()

    if providers == [] do
      IO.puts(:stderr, "No LLM providers configured. Set API keys or local provider URLs.")
      System.halt(0)
    end

    ensure_router(providers)

    IO.puts("Available providers: #{providers |> Enum.map(& &1.name) |> Enum.join(", ")}\n")

    print_section("Routing Scenarios")

    scenarios = [
      {"Simple question", "What is 2 + 2?", :specialist, :quick},
      {"Code generation", "Write a function to check if a number is prime", :specialist, :code},
      {"Complex analysis", "Explain the trade-offs between microservices and monoliths", :specialist,
       :reasoning}
    ]

    for {name, prompt, strategy, task_type} <- scenarios do
      IO.puts("Scenario: #{name}")
      IO.puts("Strategy: #{strategy}")
      IO.puts("Prompt: #{String.slice(prompt, 0, 50)}...")

      case route_and_complete(prompt, strategy, task_type) do
        {:ok, provider, response, duration} ->
          IO.puts("Routed to: #{provider}")
          IO.puts("Response time: #{duration}ms")
          IO.puts("Response: #{String.slice(response, 0, 100)}...")

        {:error, reason} ->
          IO.puts("Error: #{inspect(reason)}")
      end

      IO.puts("")
    end

    print_section("Fallback Demo")
    demo_fallback(providers)

    print_section("Cost-Aware Routing")
    demo_cost_routing(providers)

    IO.puts("")
    print_header("Demo Complete")
  end

  defp configured_providers do
    candidates = [
      %{
        name: :gemini,
        module: PortfolioIndex.Adapters.LLM.Gemini,
        enabled: env_set?("GEMINI_API_KEY"),
        capabilities: [:fast, :generation, :reasoning, :code],
        priority: 1,
        cost_per_token: 0.0005
      },
      %{
        name: :anthropic,
        module: PortfolioIndex.Adapters.LLM.Anthropic,
        enabled: env_set?("ANTHROPIC_API_KEY"),
        capabilities: [:reasoning, :code, :generation],
        priority: 2,
        cost_per_token: 0.0015
      },
      %{
        name: :openai,
        module: PortfolioIndex.Adapters.LLM.OpenAI,
        enabled: env_set?("OPENAI_API_KEY"),
        capabilities: [:code, :generation, :reasoning],
        priority: 3,
        cost_per_token: 0.002
      },
      %{
        name: :ollama,
        module: PortfolioIndex.Adapters.LLM.Ollama,
        enabled: env_set?("OLLAMA_BASE_URL") or env_set?("OLLAMA_HOST"),
        capabilities: [:local, :generation],
        priority: 4,
        cost_per_token: 0.0
      },
      %{
        name: :vllm,
        module: PortfolioIndex.Adapters.LLM.VLLM,
        enabled: env_set?("VLLM_BASE_URL") or env_set?("VLLM_URL") or env_set?("VLLM_ENABLED"),
        capabilities: [:local, :generation],
        priority: 5,
        cost_per_token: 0.0
      }
    ]

    candidates
    |> Enum.filter(fn provider ->
      provider.enabled and Code.ensure_loaded?(provider.module)
    end)
    |> Enum.map(&Map.drop(&1, [:enabled]))
  end

  defp env_set?(key) do
    case System.get_env(key) do
      value when is_binary(value) and value != "" -> true
      _ -> false
    end
  end

  defp ensure_router(providers) do
    case Process.whereis(Router) do
      nil ->
        {:ok, _pid} = Router.start_link(strategy: :fallback, providers: providers)

      _pid ->
        existing = Router.list_providers() |> Enum.map(& &1.name)

        providers
        |> Enum.reject(&(&1.name in existing))
        |> Enum.each(fn provider ->
          _ = Router.register_provider(provider)
        end)
    end
  end

  defp route_and_complete(prompt, strategy, task_type) do
    messages = [%{role: :user, content: prompt}]

    with {:ok, provider} <- Router.route(messages, strategy: strategy, task_type: task_type) do
      start_time = System.monotonic_time(:millisecond)

      case Router.execute(messages, strategy: strategy, task_type: task_type) do
        {:ok, response} ->
          duration = System.monotonic_time(:millisecond) - start_time
          {:ok, provider.name, extract_answer(response), duration}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp demo_fallback(providers) do
    IO.puts("Testing fallback with PortfolioCoder.LLM...\n")

    prompt = "What is the capital of France?"
    messages = [%{role: :user, content: prompt}]

    case LLM.complete(messages, providers: providers, retry_attempts: 1) do
      {:ok, response} ->
        IO.puts("Success using fallback chain")
        IO.puts("Response: #{String.slice(extract_answer(response), 0, 100)}...")

      {:error, reason} ->
        IO.puts("Fallback failed: #{LLM.format_error(reason)}")
    end

    IO.puts("")
  end

  defp demo_cost_routing(providers) do
    IO.puts("Cost-aware routing demo...\n")

    tasks = [
      {"Trivial: Yes/No question", "Is Elixir a programming language? Answer yes or no.",
       :cost_optimized},
      {"Standard: Short explanation", "Explain pattern matching briefly", :cost_optimized},
      {"Complex: Detailed analysis", "Analyze the architecture of a typical Phoenix application",
       :cost_optimized}
    ]

    for {name, prompt, strategy} <- tasks do
      messages = [%{role: :user, content: prompt}]

      case Router.route(messages, strategy: strategy, task_type: :general) do
        {:ok, provider} ->
          IO.puts("Task: #{name}")
          IO.puts("  -> Routed to: #{provider.name} (#{strategy} strategy)")

        {:error, reason} ->
          IO.puts("Task: #{name}")
          IO.puts("  -> Routing failed: #{inspect(reason)}")
      end
    end

    IO.puts("")
  end

  defp extract_answer(%{content: content}) when is_binary(content), do: content
  defp extract_answer(%{output: output}) when is_binary(output), do: output
  defp extract_answer(%{text: text}) when is_binary(text), do: text
  defp extract_answer(other), do: inspect(other)

  defp print_header(text) do
    IO.puts(String.duplicate("=", 70))
    IO.puts(text)
    IO.puts(String.duplicate("=", 70))
    IO.puts("")
  end

  defp print_section(text) do
    IO.puts(String.duplicate("-", 70))
    IO.puts(text)
    IO.puts(String.duplicate("-", 70))
    IO.puts("")
  end
end

RouterDemo.run()
