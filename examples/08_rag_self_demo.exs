# examples/08_rag_self_demo.exs
#
# Demonstrates: Self-RAG with Retrieval Reflection
# Modules Used: PortfolioCoder.Indexer.InMemorySearch, LLM
# Prerequisites: GEMINI_API_KEY or other LLM API key
#
# Usage: mix run examples/08_rag_self_demo.exs [path_to_directory]
#
# This demo shows Self-RAG pattern for improved answer quality:
# 1. Retrieve initial context
# 2. Generate initial answer
# 3. Critique the answer (is it complete? accurate?)
# 4. If needed, retrieve more context
# 5. Refine the answer

alias PortfolioCoder.Indexer.Parser
alias PortfolioCoder.Indexer.CodeChunker
alias PortfolioCoder.Indexer.InMemorySearch

defmodule SelfRAGDemo do
  @generation_prompt """
  Answer this question about the codebase using the provided context.

  Context:
  <%= context %>

  Question: <%= question %>

  Provide a detailed answer:
  """

  @critique_prompt """
  Review this answer and determine if it adequately answers the question.

  Question: <%= question %>

  Answer: <%= answer %>

  Context used: <%= context_summary %>

  Evaluate:
  1. Is the answer complete?
  2. Does it directly address the question?
  3. Is there information that seems missing?

  Respond with JSON:
  {"is_sufficient": true/false, "missing_aspects": ["aspect1", "aspect2"], "confidence": 0.0-1.0}
  """

  @refinement_prompt """
  Improve this answer using the additional context.

  Original Question: <%= question %>
  Previous Answer: <%= previous_answer %>
  Missing Aspects: <%= missing %>

  Additional Context:
  <%= new_context %>

  Provide an improved, more complete answer:
  """

  def run(path) do
    print_header("Self-RAG Demo")

    check_api_key()

    IO.puts("Source directory: #{path}\n")

    # Build index
    IO.puts("Step 1: Building search index...")
    {:ok, index} = InMemorySearch.new()
    build_index(index, path)
    stats = InMemorySearch.stats(index)
    IO.puts("  Index built: #{stats.document_count} documents\n")

    # Demo questions
    print_section("Self-RAG Q&A with Reflection")

    questions = [
      "What is the purpose of the InMemorySearch module?",
      "How does query enhancement work?"
    ]

    for question <- questions do
      demo_self_rag(index, question)
    end

    IO.puts("\n")
    print_header("Demo Complete")
  end

  defp build_index(index, path) do
    path
    |> Path.join("**/*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.filter(&(not String.contains?(&1, ["deps/", "_build/"])))
    |> Enum.take(30)
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

            {:error, _} ->
              :ok
          end

        {:error, _} ->
          :ok
      end
    end)
  end

  defp demo_self_rag(index, question) do
    IO.puts("Q: #{question}")
    IO.puts(String.duplicate("-", 60))
    IO.puts("")

    # Step 1: Initial retrieval
    IO.puts("Step 1: Initial retrieval...")
    {:ok, results} = InMemorySearch.search(index, question, limit: 3)
    context = format_context(results)
    IO.puts("  Retrieved #{length(results)} documents\n")

    # Step 2: Generate initial answer
    IO.puts("Step 2: Generating initial answer...")
    {:ok, initial_answer} = generate_answer(question, context)
    IO.puts("  Initial answer generated\n")

    # Step 3: Critique
    IO.puts("Step 3: Self-critique...")
    critique = critique_answer(question, initial_answer, results)
    IO.puts("  Confidence: #{Float.round(critique.confidence, 2)}")
    IO.puts("  Sufficient: #{critique.is_sufficient}\n")

    # Step 4: Refine if needed
    final_answer =
      if critique.is_sufficient or critique.confidence > 0.8 do
        IO.puts("Step 4: Answer deemed sufficient, no refinement needed\n")
        initial_answer
      else
        IO.puts("Step 4: Retrieving additional context for refinement...")

        # Search for missing aspects
        additional_context =
          critique.missing_aspects
          |> Enum.flat_map(fn aspect ->
            {:ok, more} = InMemorySearch.search(index, aspect, limit: 2)
            more
          end)
          |> Enum.uniq_by(& &1.id)
          |> Enum.take(3)

        if Enum.empty?(additional_context) do
          IO.puts("  No additional context found\n")
          initial_answer
        else
          IO.puts("  Found #{length(additional_context)} additional documents")
          new_context = format_context(additional_context)

          {:ok, refined} =
            refine_answer(question, initial_answer, critique.missing_aspects, new_context)

          IO.puts("  Answer refined\n")
          refined
        end
      end

    IO.puts("Final Answer:")
    IO.puts(final_answer)
    IO.puts("\n")
  end

  defp format_context(results) do
    results
    |> Enum.map(fn r ->
      "File: #{Path.basename(r.metadata[:path] || "unknown")}\n#{r.content}"
    end)
    |> Enum.join("\n---\n")
  end

  defp generate_answer(question, context) do
    prompt =
      @generation_prompt
      |> String.replace("<%= context %>", context)
      |> String.replace("<%= question %>", question)

    call_llm(prompt)
  end

  defp critique_answer(question, answer, results) do
    context_summary =
      results
      |> Enum.map(fn r -> Path.basename(r.metadata[:path] || "unknown") end)
      |> Enum.join(", ")

    prompt =
      @critique_prompt
      |> String.replace("<%= question %>", question)
      |> String.replace("<%= answer %>", answer)
      |> String.replace("<%= context_summary %>", context_summary)

    case call_llm(prompt) do
      {:ok, response} ->
        parse_critique(response)

      {:error, _} ->
        %{is_sufficient: true, missing_aspects: [], confidence: 0.5}
    end
  end

  defp parse_critique(response) do
    # Try to extract JSON from response
    case Regex.run(~r/\{[^}]+\}/, response) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, data} ->
            %{
              is_sufficient: Map.get(data, "is_sufficient", true),
              missing_aspects: Map.get(data, "missing_aspects", []),
              confidence: Map.get(data, "confidence", 0.5)
            }

          {:error, _} ->
            %{is_sufficient: true, missing_aspects: [], confidence: 0.5}
        end

      nil ->
        %{is_sufficient: true, missing_aspects: [], confidence: 0.5}
    end
  end

  defp refine_answer(question, previous, missing, new_context) do
    missing_str = Enum.join(missing, ", ")

    prompt =
      @refinement_prompt
      |> String.replace("<%= question %>", question)
      |> String.replace("<%= previous_answer %>", previous)
      |> String.replace("<%= missing %>", missing_str)
      |> String.replace("<%= new_context %>", new_context)

    call_llm(prompt)
  end

  defp call_llm(prompt) do
    messages = [%{role: :user, content: prompt}]

    case PortfolioIndex.Adapters.LLM.Gemini.complete(messages, max_tokens: 1000) do
      {:ok, %{content: answer}} ->
        {:ok, String.trim(answer)}

      {:error, reason} ->
        {:error, reason}
    end
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

# Main execution
path =
  case System.argv() do
    [arg | _] -> Path.expand(arg)
    [] -> Path.expand("lib/portfolio_coder")
  end

if File.dir?(path) do
  SelfRAGDemo.run(path)
else
  IO.puts(:stderr, "Directory not found: #{path}")
  System.halt(1)
end
