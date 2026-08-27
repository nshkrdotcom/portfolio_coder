# examples/07_rag_graph_demo.exs
#
# Demonstrates: Graph-Augmented RAG for Code Q&A
# Modules Used: PortfolioCoder.Graph.InMemoryGraph, PortfolioCoder.Indexer.Parser,
#               PortfolioCoder.Indexer.InMemorySearch, PortfolioCoder.LLM
# Prerequisites: LLM provider configured
#
# Usage: mix run examples/07_rag_graph_demo.exs [path_to_directory]
#
# This demo shows how to enhance RAG with graph context:
# 1. Build both search index and code graph
# 2. For each query, retrieve related graph context
# 3. Enhance context with related modules, imports, and dependencies
# 4. Generate answers with richer code understanding

alias PortfolioCoder.Indexer.Parser
alias PortfolioCoder.Indexer.CodeChunker
alias PortfolioCoder.Indexer.InMemorySearch
alias PortfolioCoder.Graph.InMemoryGraph
alias PortfolioCoder.LLM

defmodule RAGGraphDemo do
  @answer_prompt """
  You are a helpful code assistant. Answer the user's question using both the code snippets and the relationship context.

  Code Context:
  <%= code_context %>

  Relationship Context:
  <%= graph_context %>

  Question: <%= question %>

  Answer:
  """

  def run(path) do
    print_header("Graph-Augmented RAG Demo")

    check_api_key()

    IO.puts("Source directory: #{path}\n")

    # Step 1: Build search index and graph
    IO.puts("Step 1: Building search index and code graph...")
    {:ok, index} = InMemorySearch.new()
    {:ok, graph} = InMemoryGraph.new()

    files = scan_files(path)

    for file <- files do
      case Parser.parse(file) do
        {:ok, parsed} ->
          # Add to graph
          :ok = InMemoryGraph.add_from_parsed(graph, parsed, file)

          # Add to search index
          case CodeChunker.chunk_file(file, strategy: :hybrid, chunk_size: 800) do
            {:ok, chunks} ->
              docs =
                Enum.with_index(chunks)
                |> Enum.map(fn {chunk, idx} ->
                  %{
                    id: "#{Path.basename(file)}:#{idx}",
                    content: chunk.content,
                    metadata: %{
                      path: file,
                      language: parsed.language,
                      type: chunk.type,
                      name: chunk.name,
                      start_line: chunk.start_line
                    }
                  }
                end)

              InMemorySearch.add_all(index, docs)

            {:error, _} ->
              :ok
          end

        {:error, _} ->
          :ok
      end
    end

    search_stats = InMemorySearch.stats(index)
    graph_stats = InMemoryGraph.stats(graph)
    IO.puts("  Search index: #{search_stats.document_count} documents")
    IO.puts("  Code graph: #{graph_stats.node_count} nodes, #{graph_stats.edge_count} edges\n")

    # Step 2: Demo questions with graph context
    print_section("Graph-Augmented Q&A")

    questions = [
      "What modules does Parser depend on?",
      "How are the different parsers organized?",
      "What are the relationships between indexer components?"
    ]

    for question <- questions do
      demo_question(index, graph, question)
    end

    # Step 3: Interactive mode
    IO.puts("\n")
    print_section("Interactive Q&A")
    IO.puts("Ask questions about the code (type 'quit' to exit):\n")

    interactive_loop(index, graph)
  end

  defp scan_files(path) do
    path
    |> Path.join("**/*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.filter(fn file ->
      not String.contains?(file, ["deps/", "_build/", ".git/"])
    end)
    |> Enum.take(30)
  end

  defp demo_question(index, graph, question) do
    IO.puts("Q: #{question}")
    IO.puts(String.duplicate("-", 60))

    case answer_with_graph(index, graph, question) do
      {:ok, answer} ->
        IO.puts("\nA: #{answer}")

      {:error, reason} ->
        IO.puts("\nError: #{inspect(reason)}")
    end

    IO.puts("\n")
  end

  defp answer_with_graph(index, graph, question) do
    # Step 1: Retrieve relevant code
    {:ok, search_results} = InMemorySearch.search(index, question, limit: 3)

    code_context =
      if Enum.empty?(search_results) do
        "No relevant code found."
      else
        search_results
        |> Enum.map(fn r ->
          """
          File: #{r.metadata[:path] |> Path.basename()}:#{r.metadata[:start_line]}
          #{r.content}
          """
        end)
        |> Enum.join("\n---\n")
      end

    # Step 2: Get graph context
    graph_context = build_graph_context(graph, search_results, question)

    # Step 3: Generate answer
    prompt =
      @answer_prompt
      |> String.replace("<%= code_context %>", code_context)
      |> String.replace("<%= graph_context %>", graph_context)
      |> String.replace("<%= question %>", question)

    messages = [%{role: :user, content: prompt}]

    case LLM.complete(messages, max_tokens: 1000) do
      {:ok, response} ->
        {:ok, String.trim(extract_answer(response))}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_graph_context(graph, search_results, question) do
    # Extract module names from search results
    modules_mentioned =
      search_results
      |> Enum.flat_map(fn r ->
        content = r.content
        # Simple regex to find module names
        Regex.scan(~r/defmodule\s+([A-Z][\w.]+)/, content)
        |> Enum.map(fn [_, name] -> name end)
      end)
      |> Enum.uniq()

    # Also check if question mentions specific modules
    {:ok, all_modules} = InMemoryGraph.nodes_by_type(graph, :module)

    question_modules =
      all_modules
      |> Enum.filter(fn m ->
        short_name = m.name |> String.split(".") |> List.last()
        String.contains?(String.downcase(question), String.downcase(short_name))
      end)
      |> Enum.map(& &1.id)

    target_modules = Enum.uniq(modules_mentioned ++ question_modules)

    if Enum.empty?(target_modules) do
      "No specific module relationships found."
    else
      target_modules
      |> Enum.map(fn mod_id ->
        {:ok, imports} = InMemoryGraph.imports_of(graph, mod_id)
        {:ok, functions} = InMemoryGraph.functions_of(graph, mod_id)

        import_str =
          if Enum.empty?(imports) do
            "none"
          else
            Enum.take(imports, 5) |> Enum.join(", ")
          end

        function_str =
          if Enum.empty?(functions) do
            "none"
          else
            functions
            |> Enum.take(5)
            |> Enum.map(&(&1 |> String.split("/") |> hd()))
            |> Enum.join(", ")
          end

        "Module #{mod_id}:\n  - Imports: #{import_str}\n  - Functions: #{function_str}"
      end)
      |> Enum.join("\n\n")
    end
  end

  defp interactive_loop(index, graph) do
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
            interactive_loop(index, graph)

          true ->
            case answer_with_graph(index, graph, question) do
              {:ok, answer} ->
                IO.puts("\n#{answer}")

              {:error, reason} ->
                IO.puts("\nError: #{inspect(reason)}")
            end

            IO.puts("")
            interactive_loop(index, graph)
        end
    end
  end

  defp extract_answer(%{content: content}) when is_binary(content), do: content
  defp extract_answer(%{output: output}) when is_binary(output), do: output
  defp extract_answer(%{text: text}) when is_binary(text), do: text
  defp extract_answer(other), do: inspect(other)

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
  RAGGraphDemo.run(path)
else
  IO.puts(:stderr, "Directory not found: #{path}")
  System.halt(1)
end
