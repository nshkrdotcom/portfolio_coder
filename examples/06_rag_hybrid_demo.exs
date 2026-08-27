# examples/06_rag_hybrid_demo.exs
#
# Demonstrates: Retrieval-Augmented Generation (RAG) for Code Q&A
# Modules Used: PortfolioCoder.Indexer.Parser, PortfolioCoder.Indexer.InMemorySearch,
#               PortfolioCoder.Search.QueryEnhancer, PortfolioCoder.LLM
# Prerequisites: LLM provider configured
#
# Usage: mix run examples/06_rag_hybrid_demo.exs [path_to_directory]
#
# This demo shows a complete RAG pipeline for code Q&A:
# 1. Parse and index source code into a searchable format
# 2. Enhance user queries for better retrieval
# 3. Retrieve relevant code context
# 4. Generate answers using LLM with retrieved context
#
# Note: This uses in-memory search. For production, use PortfolioManager.RAG
# with a vector database (Pgvector) for semantic search.

alias PortfolioCoder.Indexer.Parser
alias PortfolioCoder.Indexer.CodeChunker
alias PortfolioCoder.Indexer.InMemorySearch
alias PortfolioCoder.Search.QueryEnhancer
alias PortfolioCoder.LLM

defmodule RAGHybridDemo do
  @answer_prompt """
  You are a helpful code assistant. Answer the user's question based on the provided code context.

  Rules:
  - Only use information from the provided context
  - If the context doesn't contain enough information, say so
  - Include relevant code snippets in your answer when helpful
  - Keep answers concise but complete

  Context (relevant code):
  <%= context %>

  Question: <%= question %>

  Answer:
  """

  def run(path) do
    print_header("RAG Code Q&A Demo")

    check_api_key()

    IO.puts("Source directory: #{path}\n")

    # Step 1: Build the search index
    IO.puts("Step 1: Building search index...")
    {:ok, index} = InMemorySearch.new()
    documents = build_index(path)
    :ok = InMemorySearch.add_all(index, documents)
    stats = InMemorySearch.stats(index)
    IO.puts("  Index built: #{stats.document_count} documents, #{stats.term_count} terms\n")

    # Step 2: Demo Q&A sessions
    print_section("Code Q&A Demo")

    questions = [
      "What functions are defined in the Parser module?",
      "How does the code chunking work?",
      "What types of symbols does the parser extract?",
      "How is search implemented?"
    ]

    for question <- questions do
      demo_question(index, question)
    end

    # Step 3: Interactive mode
    IO.puts("\n")
    print_section("Interactive Q&A")
    IO.puts("Ask questions about the code (type 'quit' to exit):\n")

    interactive_loop(index)
  end

  defp build_index(path) do
    files = scan_files(path)

    files
    |> Enum.flat_map(fn file ->
      case process_file(file) do
        {:ok, docs} -> docs
        {:error, _} -> []
      end
    end)
  end

  defp scan_files(path) do
    extensions = [".ex", ".exs"]

    path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(fn file ->
      File.regular?(file) and
        Path.extname(file) in extensions and
        not String.contains?(file, ["deps/", "_build/", "node_modules/", ".git/"])
    end)
    |> Enum.take(30)
  end

  defp process_file(path) do
    case Parser.parse(path) do
      {:ok, parsed} ->
        case CodeChunker.chunk_file(path, strategy: :hybrid, chunk_size: 800) do
          {:ok, chunks} ->
            docs =
              chunks
              |> Enum.with_index()
              |> Enum.map(fn {chunk, idx} ->
                %{
                  id: "#{Path.basename(path)}:#{idx}:#{chunk.name || "chunk"}",
                  content: chunk.content,
                  metadata: %{
                    path: path,
                    relative_path: Path.relative_to_cwd(path),
                    language: parsed.language,
                    type: chunk.type,
                    name: chunk.name,
                    start_line: chunk.start_line,
                    end_line: chunk.end_line
                  }
                }
              end)

            {:ok, docs}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp demo_question(index, question) do
    IO.puts("Q: #{question}")
    IO.puts(String.duplicate("-", 60))

    case answer_question(index, question) do
      {:ok, answer, sources} ->
        IO.puts("\nA: #{answer}\n")
        IO.puts("Sources:")

        for source <- Enum.take(sources, 3) do
          IO.puts(
            "  - #{source.metadata[:relative_path] || source.metadata[:path]}:#{source.metadata[:start_line]}"
          )
        end

      {:error, reason} ->
        IO.puts("\nError: #{inspect(reason)}")
    end

    IO.puts("\n")
  end

  defp answer_question(index, question) do
    # Step 1: Enhance the query
    enhanced_query =
      case QueryEnhancer.rewrite(question) do
        {:ok, %{rewritten: rewritten}} -> rewritten
        {:error, _} -> question
      end

    # Step 2: Retrieve relevant context
    {:ok, results} = InMemorySearch.search(index, enhanced_query, limit: 5)

    if Enum.empty?(results) do
      {:ok, "I couldn't find relevant code to answer this question.", []}
    else
      # Step 3: Format context for LLM
      context =
        results
        |> Enum.map(fn result ->
          path = result.metadata[:relative_path] || result.metadata[:path] || "unknown"
          lines = "L#{result.metadata[:start_line]}-#{result.metadata[:end_line]}"

          """
          File: #{path} (#{lines})
          ```
          #{result.content}
          ```
          """
        end)
        |> Enum.join("\n")

      # Step 4: Generate answer with LLM
      prompt =
        @answer_prompt
        |> String.replace("<%= context %>", context)
        |> String.replace("<%= question %>", question)

      messages = [%{role: :user, content: prompt}]

      case LLM.complete(messages, max_tokens: 1000) do
        {:ok, response} ->
          {:ok, String.trim(extract_answer(response)), results}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp extract_answer(%{content: content}) when is_binary(content), do: content
  defp extract_answer(%{output: output}) when is_binary(output), do: output
  defp extract_answer(%{text: text}) when is_binary(text), do: text
  defp extract_answer(other), do: inspect(other)

  defp interactive_loop(index) do
    case IO.gets("> ") do
      :eof ->
        IO.puts("\nGoodbye!")

      {:error, _} ->
        IO.puts("\nGoodbye!")

      input ->
        question = String.trim(input)

        cond do
          question in ["quit", "exit", "q"] ->
            IO.puts("Goodbye!")

          question == "" ->
            interactive_loop(index)

          true ->
            case answer_question(index, question) do
              {:ok, answer, sources} ->
                IO.puts("\n#{answer}\n")

                unless Enum.empty?(sources) do
                  IO.puts("Sources:")

                  for source <- Enum.take(sources, 3) do
                    IO.puts(
                      "  - #{source.metadata[:relative_path] || source.metadata[:path]}:#{source.metadata[:start_line]}"
                    )
                  end
                end

              {:error, reason} ->
                IO.puts("\nError: #{inspect(reason)}")
            end

            IO.puts("")
            interactive_loop(index)
        end
    end
  end

  defp check_api_key do
    providers =
      [
        {"gemini", System.get_env("GEMINI_API_KEY")},
        {"openai", System.get_env("OPENAI_API_KEY")},
        {"codex", System.get_env("CODEX_API_KEY")},
        {"anthropic", System.get_env("ANTHROPIC_API_KEY")},
        {"ollama", System.get_env("OLLAMA_BASE_URL") || System.get_env("OLLAMA_HOST")},
        {"vllm",
         System.get_env("VLLM_BASE_URL") || System.get_env("VLLM_URL") ||
           System.get_env("VLLM_ENABLED")}
      ]
      |> Enum.filter(fn {_name, value} -> is_binary(value) and value != "" end)
      |> Enum.map(&elem(&1, 0))

    if providers == [] do
      IO.puts(:stderr, """
      Skipping: no LLM provider configured.

      Set GEMINI_API_KEY, OPENAI_API_KEY, ANTHROPIC_API_KEY,
      OLLAMA_BASE_URL/OLLAMA_HOST, or VLLM_BASE_URL/VLLM_URL.
      """)

      System.halt(0)
    else
      IO.puts("LLM providers available: #{Enum.join(providers, ", ")}\n")
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
  RAGHybridDemo.run(path)
else
  IO.puts(:stderr, "Directory not found: #{path}")
  System.halt(1)
end
