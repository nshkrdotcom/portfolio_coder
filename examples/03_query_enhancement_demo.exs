# examples/03_query_enhancement_demo.exs
#
# Demonstrates: Query Enhancement for Code Search
# Modules Used: PortfolioCoder.Search.QueryEnhancer
# Prerequisites: GEMINI_API_KEY or other LLM API key configured
#
# Usage: mix run examples/03_query_enhancement_demo.exs
#
# This demo shows how to improve search queries for better code retrieval:
# 1. Rewrite conversational queries into focused search terms
# 2. Expand queries with synonyms and related terms
# 3. Decompose complex questions into simpler sub-queries
# 4. Run the full enhancement pipeline

alias PortfolioCoder.Search.QueryEnhancer

defmodule QueryEnhancementDemo do
  def run do
    print_header("Query Enhancement Demo")

    check_api_key()

    # Demo queries
    queries = [
      # Conversational query that needs cleaning
      "Hey, can you help me understand how Phoenix LiveView handles real-time updates?",
      # Technical query that benefits from expansion
      "GenServer state management",
      # Complex comparison query that needs decomposition
      "Compare Elixir's concurrency model with Go's goroutines for building APIs",
      # Simple focused query (should stay mostly unchanged)
      "function definition parsing"
    ]

    # Demo 1: Query Rewriting
    print_section("1. Query Rewriting")
    IO.puts("Removes conversational filler and extracts core intent.\n")

    for query <- queries do
      demo_rewrite(query)
    end

    # Demo 2: Query Expansion
    print_section("2. Query Expansion")
    IO.puts("Adds synonyms and related terms for better recall.\n")

    expansion_queries = [
      "GenServer state",
      "auth middleware",
      "ML models",
      "REST API"
    ]

    for query <- expansion_queries do
      demo_expand(query)
    end

    # Demo 3: Query Decomposition
    print_section("3. Query Decomposition")
    IO.puts("Breaks complex questions into simpler sub-queries.\n")

    complex_queries = [
      "Compare Elixir and Go for building web services",
      "How does Phoenix LiveView work and what are its performance characteristics?",
      "What is pattern matching?",
      "What is GenServer and how does it relate to OTP?"
    ]

    for query <- complex_queries do
      demo_decompose(query)
    end

    # Demo 4: Full Pipeline
    print_section("4. Full Enhancement Pipeline")
    IO.puts("Combines rewriting, expansion, and decomposition.\n")

    pipeline_queries = [
      "Hey, can you explain how we handle user authentication in the app?",
      "I want to understand the difference between processes and threads"
    ]

    for query <- pipeline_queries do
      demo_full_pipeline(query)
    end

    # Demo 5: Code-specific Enhancement
    print_section("5. Code-Specific Enhancement")
    IO.puts("Specialized enhancement for code search.\n")

    code_queries = [
      "how do we handle user login?",
      "where is error handling done?"
    ]

    for query <- code_queries do
      demo_code_specific(query)
    end

    IO.puts("\n")
    print_header("Demo Complete")
  end

  defp demo_rewrite(query) do
    IO.puts("Original: \"#{query}\"")

    case QueryEnhancer.rewrite(query) do
      {:ok, result} ->
        IO.puts("Rewritten: \"#{result.rewritten}\"")

        if result.changes_made != [] do
          IO.puts("Changes: #{Enum.join(result.changes_made, ", ")}")
        end

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end

    IO.puts("")
  end

  defp demo_expand(query) do
    IO.puts("Original: \"#{query}\"")

    case QueryEnhancer.expand(query) do
      {:ok, result} ->
        IO.puts("Expanded: \"#{result.expanded}\"")

        if result.added_terms != [] do
          IO.puts("Added terms: #{Enum.join(result.added_terms, ", ")}")
        end

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end

    IO.puts("")
  end

  defp demo_decompose(query) do
    IO.puts("Original: \"#{query}\"")

    case QueryEnhancer.decompose(query) do
      {:ok, result} ->
        IO.puts("Complex: #{result.is_complex}")

        IO.puts("Sub-queries:")

        for {sq, idx} <- Enum.with_index(result.sub_questions, 1) do
          IO.puts("  #{idx}. #{sq}")
        end

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end

    IO.puts("")
  end

  defp demo_full_pipeline(query) do
    IO.puts("Original: \"#{query}\"")

    case QueryEnhancer.enhance(query) do
      {:ok, result} ->
        IO.puts("Rewritten: \"#{result.rewritten}\"")
        IO.puts("Expanded: \"#{result.expanded}\"")
        IO.puts("Is complex: #{result.is_complex}")

        if length(result.sub_queries) > 1 do
          IO.puts("Sub-queries:")

          for {sq, idx} <- Enum.with_index(result.sub_queries, 1) do
            IO.puts("  #{idx}. #{sq}")
          end
        end

        if result.changes != [] do
          IO.puts("Changes made: #{Enum.join(result.changes, ", ")}")
        end

        if result.added_terms != [] do
          IO.puts("Added terms: #{Enum.join(Enum.take(result.added_terms, 5), ", ")}...")
        end

      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end

    IO.puts("")
  end

  defp demo_code_specific(query) do
    IO.puts("Original: \"#{query}\"")

    rewritten = QueryEnhancer.rewrite_for_code(query)
    IO.puts("Code search terms: \"#{rewritten}\"")

    expanded = QueryEnhancer.expand_with_code_terms(query)
    IO.puts("With code synonyms: \"#{expanded}\"")

    IO.puts("")
  end

  defp check_api_key do
    cond do
      System.get_env("GEMINI_API_KEY") ->
        IO.puts("Using Gemini API (GEMINI_API_KEY found)\n")

      System.get_env("OPENAI_API_KEY") ->
        IO.puts("Using OpenAI API (OPENAI_API_KEY found)\n")

      System.get_env("ANTHROPIC_API_KEY") ->
        IO.puts("Using Anthropic API (ANTHROPIC_API_KEY found)\n")

      true ->
        IO.puts(:stderr, """
        Warning: No LLM API key found!

        Set one of:
          - GEMINI_API_KEY
          - OPENAI_API_KEY
          - ANTHROPIC_API_KEY

        The demo will attempt to continue but may fail.
        """)
    end
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

# Run the demo
QueryEnhancementDemo.run()
