# examples/11_router_demo.exs
#
# Demonstrates: Multi-Provider LLM Routing
# Modules Used: Various LLM adapters from portfolio_index
# Prerequisites: At least one LLM API key (GEMINI_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY)
#
# Usage: mix run examples/11_router_demo.exs
#
# This demo shows how to route requests to different LLM providers based on:
# 1. Task complexity
# 2. Cost optimization
# 3. Provider availability
# 4. Specific capability requirements

defmodule RouterDemo do
  @moduledoc """
  Demonstrates intelligent LLM routing between providers.
  """

  @providers [
    {:gemini, PortfolioIndex.Adapters.LLM.Gemini, "GEMINI_API_KEY"},
    {:anthropic, PortfolioIndex.Adapters.LLM.Anthropic, "ANTHROPIC_API_KEY"},
    {:openai, PortfolioIndex.Adapters.LLM.OpenAI, "OPENAI_API_KEY"}
  ]

  def run do
    print_header("Multi-Provider LLM Router Demo")

    # Check available providers
    available = check_providers()

    if Enum.empty?(available) do
      IO.puts(
        :stderr,
        "No LLM API keys found. Set GEMINI_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY"
      )

      System.halt(1)
    end

    IO.puts("Available providers: #{Enum.map(available, & &1.name) |> Enum.join(", ")}\n")

    # Demo routing scenarios
    print_section("Routing Scenarios")

    scenarios = [
      {"Simple question", "What is 2 + 2?", :fast},
      {"Code generation", "Write a function to check if a number is prime", :capable},
      {"Complex analysis", "Explain the trade-offs between microservices and monoliths", :smart}
    ]

    for {name, prompt, strategy} <- scenarios do
      IO.puts("Scenario: #{name}")
      IO.puts("Strategy: #{strategy}")
      IO.puts("Prompt: #{String.slice(prompt, 0, 50)}...")

      case route_and_complete(prompt, strategy, available) do
        {:ok, provider, response, duration} ->
          IO.puts("Routed to: #{provider}")
          IO.puts("Response time: #{duration}ms")
          IO.puts("Response: #{String.slice(response, 0, 100)}...")

        {:error, reason} ->
          IO.puts("Error: #{inspect(reason)}")
      end

      IO.puts("")
    end

    # Demo fallback behavior
    print_section("Fallback Demo")
    demo_fallback(available)

    print_section("Cost-Aware Routing")
    demo_cost_routing(available)

    IO.puts("")
    print_header("Demo Complete")
  end

  defp check_providers do
    @providers
    |> Enum.filter(fn {_name, _module, env_var} ->
      System.get_env(env_var) != nil
    end)
    |> Enum.map(fn {name, module, _env_var} ->
      %{name: name, module: module}
    end)
  end

  defp route_and_complete(prompt, strategy, available) do
    provider = select_provider(strategy, available)

    start_time = System.monotonic_time(:millisecond)
    messages = [%{role: :user, content: prompt}]

    case provider.module.complete(messages, max_tokens: 500) do
      {:ok, %{content: response}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        {:ok, provider.name, response, duration}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp select_provider(:fast, available) do
    # Prefer Gemini for fast responses
    Enum.find(available, &(&1.name == :gemini)) || hd(available)
  end

  defp select_provider(:capable, available) do
    # Prefer Claude for code generation
    Enum.find(available, &(&1.name == :anthropic)) ||
      Enum.find(available, &(&1.name == :openai)) ||
      hd(available)
  end

  defp select_provider(:smart, available) do
    # Prefer the most capable available
    Enum.find(available, &(&1.name == :anthropic)) ||
      Enum.find(available, &(&1.name == :openai)) ||
      Enum.find(available, &(&1.name == :gemini)) ||
      hd(available)
  end

  defp select_provider(:cheap, available) do
    # Prefer cheaper options
    Enum.find(available, &(&1.name == :gemini)) ||
      Enum.find(available, &(&1.name == :openai)) ||
      hd(available)
  end

  defp demo_fallback(available) do
    IO.puts("Testing automatic fallback between providers...\n")

    prompt = "What is the capital of France?"

    # Try each provider in order
    results =
      available
      |> Enum.reduce_while([], fn provider, acc ->
        IO.puts("Trying #{provider.name}...")
        start_time = System.monotonic_time(:millisecond)
        messages = [%{role: :user, content: prompt}]

        case provider.module.complete(messages, max_tokens: 100) do
          {:ok, %{content: response}} ->
            duration = System.monotonic_time(:millisecond) - start_time
            IO.puts("  Success in #{duration}ms")
            {:halt, [{provider.name, :ok, response} | acc]}

          {:error, reason} ->
            IO.puts("  Failed: #{inspect(reason)}")
            {:cont, [{provider.name, :error, reason} | acc]}
        end
      end)

    IO.puts("\nFallback chain completed with #{length(results)} attempt(s)\n")
  end

  defp demo_cost_routing(available) do
    IO.puts("Cost-aware routing demo...\n")

    tasks = [
      {"Trivial: Yes/No question", "Is Elixir a programming language? Answer yes or no.", :cheap},
      {"Standard: Short explanation", "Explain pattern matching briefly", :cheap},
      {"Complex: Detailed analysis", "Analyze the architecture of a typical Phoenix application",
       :smart}
    ]

    for {name, prompt, strategy} <- tasks do
      provider = select_provider(strategy, available)
      IO.puts("Task: #{name}")
      IO.puts("  -> Routed to: #{provider.name} (#{strategy} strategy)")
    end

    IO.puts("")
  end

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
