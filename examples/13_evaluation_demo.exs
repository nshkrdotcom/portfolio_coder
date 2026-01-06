# examples/13_evaluation_demo.exs
#
# Demonstrates: RAG Evaluation Metrics
# Modules Used: InMemorySearch, LLM
# Prerequisites: GEMINI_API_KEY
#
# Usage: mix run examples/13_evaluation_demo.exs
#
# This demo shows how to evaluate RAG system quality:
# 1. Context Relevance - Are retrieved documents relevant?
# 2. Answer Faithfulness - Is the answer grounded in context?
# 3. Answer Relevance - Does the answer address the question?

alias PortfolioCoder.Indexer.Parser
alias PortfolioCoder.Indexer.CodeChunker
alias PortfolioCoder.Indexer.InMemorySearch

defmodule EvaluationDemo do
  @context_relevance_prompt """
  Rate how relevant this context is to the question on a scale of 0-10.

  Question: <%= question %>

  Context:
  <%= context %>

  Respond with JSON only: {"score": X, "reasoning": "brief explanation"}
  """

  @faithfulness_prompt """
  Check if this answer is faithful to (supported by) the context.
  Rate on a scale of 0-10 where 10 means fully supported.

  Context:
  <%= context %>

  Answer: <%= answer %>

  Respond with JSON only: {"score": X, "unsupported_claims": ["claim1", "claim2"]}
  """

  @relevance_prompt """
  Rate how well this answer addresses the question on a scale of 0-10.

  Question: <%= question %>
  Answer: <%= answer %>

  Respond with JSON only: {"score": X, "reasoning": "brief explanation"}
  """

  def run do
    print_header("RAG Evaluation Demo")

    check_api_key()

    # Build test index
    IO.puts("Building test index...")
    {:ok, index} = InMemorySearch.new()
    build_test_index(index)
    IO.puts("  Index built\n")

    # Test cases for evaluation
    test_cases = [
      %{
        question: "What is the purpose of InMemorySearch?",
        expected_topics: ["search", "index", "keyword"]
      },
      %{
        question: "How does code chunking work?",
        expected_topics: ["chunk", "split", "strategy"]
      },
      %{
        question: "What languages does the parser support?",
        expected_topics: ["elixir", "python", "javascript"]
      }
    ]

    # Evaluate each test case
    print_section("Evaluation Results")

    results =
      for test_case <- test_cases do
        evaluate_test_case(index, test_case)
      end

    # Summary
    print_section("Summary")
    print_summary(results)

    IO.puts("")
    print_header("Evaluation Complete")
  end

  defp build_test_index(index) do
    path = Path.expand("lib/portfolio_coder")

    path
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.filter(&(not String.contains?(&1, ["deps/", "_build/"])))
    |> Enum.take(20)
    |> Enum.each(fn file ->
      case Parser.parse(file) do
        {:ok, parsed} ->
          case CodeChunker.chunk_file(file, strategy: :hybrid, chunk_size: 800) do
            {:ok, chunks} ->
              docs =
                Enum.with_index(chunks)
                |> Enum.map(fn {chunk, idx} ->
                  %{
                    id: "#{Path.basename(file)}:#{idx}",
                    content: chunk.content,
                    metadata: %{path: file, language: parsed.language}
                  }
                end)

              InMemorySearch.add_all(index, docs)

            _ ->
              :ok
          end

        _ ->
          :ok
      end
    end)
  end

  defp evaluate_test_case(index, test_case) do
    IO.puts("Question: #{test_case.question}")
    IO.puts(String.duplicate("-", 50))

    # Step 1: Retrieve context
    {:ok, results} = InMemorySearch.search(index, test_case.question, limit: 3)
    context = format_context(results)

    # Step 2: Generate answer
    answer = generate_answer(test_case.question, context)

    # Step 3: Evaluate
    context_score = evaluate_context_relevance(test_case.question, context)
    faithfulness_score = evaluate_faithfulness(context, answer)
    relevance_score = evaluate_answer_relevance(test_case.question, answer)

    IO.puts("")
    IO.puts("Retrieved #{length(results)} documents")
    IO.puts("")
    IO.puts("Generated Answer:")
    IO.puts("  #{String.slice(answer, 0, 150)}...")
    IO.puts("")
    IO.puts("Evaluation Scores:")
    IO.puts("  Context Relevance: #{context_score.score}/10")
    IO.puts("    #{context_score.reasoning}")
    IO.puts("  Faithfulness: #{faithfulness_score.score}/10")

    if length(faithfulness_score.unsupported_claims) > 0 do
      IO.puts("    Unsupported claims: #{Enum.join(faithfulness_score.unsupported_claims, ", ")}")
    end

    IO.puts("  Answer Relevance: #{relevance_score.score}/10")
    IO.puts("    #{relevance_score.reasoning}")
    IO.puts("")

    %{
      question: test_case.question,
      context_relevance: context_score.score,
      faithfulness: faithfulness_score.score,
      answer_relevance: relevance_score.score
    }
  end

  defp format_context(results) do
    results
    |> Enum.map(fn r -> String.slice(r.content, 0, 500) end)
    |> Enum.join("\n---\n")
  end

  defp generate_answer(question, context) do
    prompt = """
    Answer this question based on the context.

    Context:
    #{context}

    Question: #{question}

    Provide a concise answer:
    """

    messages = [%{role: :user, content: prompt}]

    case PortfolioIndex.Adapters.LLM.Gemini.complete(messages, max_tokens: 300) do
      {:ok, %{content: answer}} -> String.trim(answer)
      {:error, _} -> "Error generating answer"
    end
  end

  defp evaluate_context_relevance(question, context) do
    prompt =
      @context_relevance_prompt
      |> String.replace("<%= question %>", question)
      |> String.replace("<%= context %>", String.slice(context, 0, 1500))

    parse_evaluation(prompt, %{score: 5, reasoning: "Unable to evaluate"})
  end

  defp evaluate_faithfulness(context, answer) do
    prompt =
      @faithfulness_prompt
      |> String.replace("<%= context %>", String.slice(context, 0, 1500))
      |> String.replace("<%= answer %>", answer)

    parse_evaluation(prompt, %{score: 5, unsupported_claims: []})
  end

  defp evaluate_answer_relevance(question, answer) do
    prompt =
      @relevance_prompt
      |> String.replace("<%= question %>", question)
      |> String.replace("<%= answer %>", answer)

    parse_evaluation(prompt, %{score: 5, reasoning: "Unable to evaluate"})
  end

  defp parse_evaluation(prompt, default) do
    messages = [%{role: :user, content: prompt}]

    case PortfolioIndex.Adapters.LLM.Gemini.complete(messages, max_tokens: 200) do
      {:ok, %{content: response}} ->
        case Regex.run(~r/\{[^}]+\}/, response) do
          [json_str] ->
            case Jason.decode(json_str) do
              {:ok, data} ->
                %{
                  score: Map.get(data, "score", 5),
                  reasoning: Map.get(data, "reasoning", ""),
                  unsupported_claims: Map.get(data, "unsupported_claims", [])
                }

              _ ->
                default
            end

          _ ->
            default
        end

      {:error, _} ->
        default
    end
  end

  defp print_summary(results) do
    avg_context = Enum.sum(Enum.map(results, & &1.context_relevance)) / length(results)
    avg_faith = Enum.sum(Enum.map(results, & &1.faithfulness)) / length(results)
    avg_relevance = Enum.sum(Enum.map(results, & &1.answer_relevance)) / length(results)

    IO.puts("Average Scores (across #{length(results)} test cases):")
    IO.puts("  Context Relevance: #{Float.round(avg_context, 1)}/10")
    IO.puts("  Faithfulness: #{Float.round(avg_faith, 1)}/10")
    IO.puts("  Answer Relevance: #{Float.round(avg_relevance, 1)}/10")
    IO.puts("")

    overall = (avg_context + avg_faith + avg_relevance) / 3
    IO.puts("  Overall RAG Quality: #{Float.round(overall, 1)}/10")

    quality_level =
      cond do
        overall >= 8 -> "Excellent"
        overall >= 6 -> "Good"
        overall >= 4 -> "Fair"
        true -> "Needs Improvement"
      end

    IO.puts("  Quality Level: #{quality_level}")
  end

  defp check_api_key do
    if System.get_env("GEMINI_API_KEY") do
      IO.puts("Using Gemini API\n")
    else
      IO.puts(:stderr, "Warning: GEMINI_API_KEY not set\n")
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

EvaluationDemo.run()
