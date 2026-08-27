# examples/15_full_demo.exs
#
# Demonstrates: Complete End-to-End Code Intelligence Pipeline
# Modules Used: All portfolio_coder modules
# Prerequisites: LLM provider configured
#
# Usage: mix run examples/15_full_demo.exs [path_to_directory]
#
# This comprehensive demo showcases all features:
# 1. Parse and index a codebase
# 2. Build search index and knowledge graph
# 3. Enhance queries for better retrieval
# 4. Use RAG to answer questions
# 5. Analyze dependencies
# 6. Show evaluation metrics

alias PortfolioCoder.Indexer.Parser
alias PortfolioCoder.Indexer.CodeChunker
alias PortfolioCoder.Indexer.InMemorySearch
alias PortfolioCoder.Search.QueryEnhancer
alias PortfolioCoder.Graph.InMemoryGraph
alias PortfolioCoder.LLM

defmodule FullDemo do
  @moduledoc """
  Complete demonstration of all portfolio_coder features.
  """

  def run(path) do
    print_header("Portfolio Coder - Complete Demo")

    providers = available_llm_providers()

    IO.puts("Source directory: #{path}")
    IO.puts("LLM: #{format_llm_status(providers)}")
    IO.puts("")

    # Phase 1: Indexing
    print_phase("Phase 1: Code Indexing")
    state = index_codebase(path)
    IO.puts("")

    # Phase 2: Search
    print_phase("Phase 2: Code Search")
    demo_search(state)
    IO.puts("")

    # Phase 3: Query Enhancement
    print_phase("Phase 3: Query Enhancement")
    demo_query_enhancement()
    IO.puts("")

    # Phase 4: RAG Q&A
    print_phase("Phase 4: RAG-based Q&A")
    demo_rag(state)
    IO.puts("")

    # Phase 5: Dependency Analysis
    print_phase("Phase 5: Dependency Analysis")
    demo_dependencies(state)
    IO.puts("")

    # Phase 6: Summary
    print_phase("Phase 6: Summary Statistics")
    print_summary(state)

    IO.puts("")
    print_header("Demo Complete!")

    IO.puts("""

    To explore further, try these examples:
    - mix run examples/02_search_demo.exs     # Interactive search
    - mix run examples/06_rag_hybrid_demo.exs # RAG Q&A
    - mix run examples/09_agent_basic_demo.exs # Code agent

    """)
  end

  defp index_codebase(path) do
    IO.puts("Scanning and parsing source files...")

    files =
      path
      |> Path.join("**/*.{ex,exs}")
      |> Path.wildcard()
      |> Enum.filter(&(not String.contains?(&1, ["deps/", "_build/", ".git/"])))
      |> Enum.sort()

    IO.puts("  Found #{length(files)} files")

    # Create search index and graph
    {:ok, index} = InMemorySearch.new()
    {:ok, graph} = InMemoryGraph.new()

    {parsed_count, chunk_count} =
      files
      |> Enum.reduce({0, 0}, fn file, {p_count, c_count} ->
        case Parser.parse(file) do
          {:ok, parsed} ->
            # Add to graph
            InMemoryGraph.add_from_parsed(graph, parsed, file)

            # Chunk and index
            case CodeChunker.chunk_file(file, strategy: :hybrid, chunk_size: 800) do
              {:ok, chunks} ->
                docs =
                  chunks
                  |> Enum.with_index()
                  |> Enum.map(fn {chunk, idx} ->
                    %{
                      id: "#{Path.basename(file)}:#{idx}",
                      content: chunk.content,
                      metadata: %{
                        path: file,
                        language: parsed.language,
                        type: chunk.type,
                        name: chunk.name
                      }
                    }
                  end)

                InMemorySearch.add_all(index, docs)
                {p_count + 1, c_count + length(chunks)}

              {:error, _} ->
                {p_count + 1, c_count}
            end

          {:error, _} ->
            {p_count, c_count}
        end
      end)

    search_stats = InMemorySearch.stats(index)
    graph_stats = InMemoryGraph.stats(graph)

    IO.puts("  Parsed #{parsed_count} files")
    IO.puts("  Created #{chunk_count} chunks")

    IO.puts(
      "  Search index: #{search_stats.document_count} documents, #{search_stats.term_count} terms"
    )

    IO.puts("  Knowledge graph: #{graph_stats.node_count} nodes, #{graph_stats.edge_count} edges")

    %{
      index: index,
      graph: graph,
      files: files,
      parsed_count: parsed_count,
      chunk_count: chunk_count
    }
  end

  defp demo_search(state) do
    queries = ["parse", "function definition", "search index"]

    for query <- queries do
      IO.puts("Query: \"#{query}\"")
      {:ok, results} = InMemorySearch.search(state.index, query, limit: 3)

      if Enum.empty?(results) do
        IO.puts("  No results")
      else
        for r <- results do
          name = r.metadata[:name] || Path.basename(r.metadata[:path])
          IO.puts("  - #{name} (score: #{Float.round(r.score, 2)})")
        end
      end

      IO.puts("")
    end
  end

  defp demo_query_enhancement do
    queries = [
      "Hey, how does the parser work?",
      "GenServer state management"
    ]

    for query <- queries do
      IO.puts("Original: \"#{query}\"")

      case QueryEnhancer.rewrite(query) do
        {:ok, %{rewritten: rewritten}} ->
          IO.puts("Rewritten: \"#{rewritten}\"")

        {:error, _} ->
          IO.puts("  (enhancement not available)")
      end

      IO.puts("")
    end
  end

  defp demo_rag(state) do
    question = "What is the purpose of the InMemorySearch module?"

    IO.puts("Question: #{question}")
    IO.puts("")

    # Retrieve context
    {:ok, results} = InMemorySearch.search(state.index, question, limit: 3)

    context =
      results
      |> Enum.map(fn r ->
        "File: #{Path.basename(r.metadata[:path])}\n#{String.slice(r.content, 0, 400)}"
      end)
      |> Enum.join("\n---\n")

    IO.puts("Retrieved #{length(results)} relevant documents")

    if llm_available?() do
      prompt = """
      Answer this question based on the context.

      Context:
      #{context}

      Question: #{question}

      Provide a concise answer:
      """

      messages = [%{role: :user, content: prompt}]

      case LLM.complete(messages, max_tokens: 500) do
        {:ok, response} ->
          IO.puts("")
          IO.puts("Answer:")
          IO.puts("  #{String.slice(extract_answer(response), 0, 300)}...")

        {:error, reason} ->
          IO.puts("  LLM error: #{LLM.format_error(reason)}")
      end
    else
      IO.puts("  (No LLM provider configured; skipping answer generation)")
    end
  end

  defp demo_dependencies(state) do
    {:ok, modules} = InMemoryGraph.nodes_by_type(state.graph, :module)
    {:ok, externals} = InMemoryGraph.nodes_by_type(state.graph, :external)

    IO.puts("Internal modules: #{length(modules)}")

    modules
    |> Enum.take(5)
    |> Enum.each(fn m ->
      {:ok, imports} = InMemoryGraph.imports_of(state.graph, m.id)
      IO.puts("  #{shorten(m.name)}: #{length(imports)} imports")
    end)

    IO.puts("")
    IO.puts("External dependencies: #{length(externals)}")

    externals
    |> Enum.map(fn ext ->
      {:ok, importers} = InMemoryGraph.imported_by(state.graph, ext.id)
      {ext, length(importers)}
    end)
    |> Enum.sort_by(fn {_, count} -> -count end)
    |> Enum.take(5)
    |> Enum.each(fn {ext, count} ->
      IO.puts("  #{ext.name}: used by #{count} modules")
    end)
  end

  defp print_summary(state) do
    graph_stats = InMemoryGraph.stats(state.graph)

    IO.puts("Files indexed: #{state.parsed_count}")
    IO.puts("Code chunks: #{state.chunk_count}")
    IO.puts("Graph nodes: #{graph_stats.node_count}")
    IO.puts("Graph edges: #{graph_stats.edge_count}")
    IO.puts("")
    IO.puts("Node types:")

    for {type, count} <- graph_stats.nodes_by_type do
      IO.puts("  #{type}: #{count}")
    end

    IO.puts("")
    IO.puts("Edge types:")

    for {type, count} <- graph_stats.edges_by_type do
      IO.puts("  #{type}: #{count}")
    end
  end

  defp extract_answer(%{content: content}) when is_binary(content), do: content
  defp extract_answer(%{output: output}) when is_binary(output), do: output
  defp extract_answer(%{text: text}) when is_binary(text), do: text
  defp extract_answer(other), do: inspect(other)

  defp available_llm_providers do
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
  end

  defp llm_available? do
    available_llm_providers() != []
  end

  defp format_llm_status([]), do: "Not configured"
  defp format_llm_status(providers), do: Enum.join(providers, ", ")

  defp shorten(name) do
    name
    |> String.replace("PortfolioCoder.", "")
    |> String.replace("PortfolioIndex.", "Index.")
    |> String.replace("PortfolioManager.", "Manager.")
  end

  defp print_header(text) do
    IO.puts("")
    IO.puts(String.duplicate("=", 70))
    IO.puts(text)
    IO.puts(String.duplicate("=", 70))
    IO.puts("")
  end

  defp print_phase(text) do
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
  FullDemo.run(path)
else
  IO.puts(:stderr, "Directory not found: #{path}")
  System.halt(1)
end
