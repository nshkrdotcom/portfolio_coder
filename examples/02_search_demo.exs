# examples/02_search_demo.exs
#
# Demonstrates: Code Search with In-Memory Index
# Modules Used: PortfolioCoder.Indexer.Parser, PortfolioCoder.Indexer.CodeChunker,
#               PortfolioCoder.Indexer.InMemorySearch
# Prerequisites: None (no database required)
#
# Usage: mix run examples/02_search_demo.exs [path_to_directory]
#
# This demo shows a complete search pipeline:
# 1. Scan and parse source files
# 2. Chunk code into searchable units
# 3. Build an in-memory search index
# 4. Run interactive search queries

alias PortfolioCoder.Indexer.Parser
alias PortfolioCoder.Indexer.CodeChunker
alias PortfolioCoder.Indexer.InMemorySearch

defmodule SearchDemo do
  def run(path) do
    print_header("Code Search Demo")

    IO.puts("Source directory: #{path}\n")

    # Step 1: Scan and parse files
    IO.puts("Step 1: Scanning source files...")
    files = scan_files(path)
    IO.puts("  Found #{length(files)} files\n")

    # Step 2: Parse and chunk all files
    IO.puts("Step 2: Parsing and chunking code...")
    documents = process_files(files)
    IO.puts("  Created #{length(documents)} searchable documents\n")

    # Step 3: Build search index
    IO.puts("Step 3: Building search index...")
    {:ok, index} = InMemorySearch.new()
    :ok = InMemorySearch.add_all(index, documents)
    stats = InMemorySearch.stats(index)

    IO.puts(
      "  Index built: #{stats.document_count} documents, #{stats.term_count} unique terms\n"
    )

    # Step 4: Run demo searches
    print_header("Search Results")

    demo_searches = [
      {"function definitions", []},
      {"parse", [language: :elixir]},
      {"class", [language: :python]},
      {"import", []},
      {"error handling", []},
      {"config", []},
      {"test", []}
    ]

    for {query, opts} <- demo_searches do
      run_search(index, query, opts)
    end

    # Step 5: Interactive mode if running in terminal
    IO.puts("\n")
    print_header("Interactive Search")
    IO.puts("Enter search queries (or 'quit' to exit):\n")

    interactive_loop(index)
  end

  defp scan_files(path) do
    extensions = [".ex", ".exs", ".py", ".js", ".ts"]

    path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(fn file ->
      File.regular?(file) and
        Path.extname(file) in extensions and
        not String.contains?(file, ["deps/", "_build/", "node_modules/", ".git/"])
    end)
    |> Enum.take(50)
    |> Enum.sort()
  end

  defp process_files(files) do
    files
    |> Enum.flat_map(fn file ->
      case process_file(file) do
        {:ok, docs} -> docs
        {:error, _} -> []
      end
    end)
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

  defp run_search(index, query, opts) do
    IO.puts("Query: \"#{query}\"#{format_opts(opts)}")

    {:ok, results} = InMemorySearch.search(index, query, [{:limit, 5} | opts])

    if Enum.empty?(results) do
      IO.puts("  No results found.\n")
    else
      for result <- results do
        score = Float.round(result.score, 2)
        path = result.metadata[:relative_path] || result.metadata[:path] || "unknown"
        name = result.metadata[:name] || "unnamed"
        type = result.metadata[:type] || "unknown"
        lines = "L#{result.metadata[:start_line]}-#{result.metadata[:end_line]}"

        IO.puts("  [#{score}] #{Path.basename(path)}:#{lines} (#{type}) #{name}")

        # Show snippet
        snippet =
          result.content
          |> String.trim()
          |> String.slice(0, 80)
          |> String.replace("\n", " ")

        IO.puts("        \"#{snippet}...\"")
      end

      IO.puts("")
    end
  end

  defp format_opts([]), do: ""

  defp format_opts(opts) do
    filters =
      opts
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join(", ")

    " [#{filters}]"
  end

  defp interactive_loop(index) do
    case IO.gets("> ") do
      :eof ->
        IO.puts("\nGoodbye!")

      {:error, _} ->
        IO.puts("\nGoodbye!")

      input ->
        query = String.trim(input)

        cond do
          query in ["quit", "exit", "q"] ->
            IO.puts("Goodbye!")

          query == "" ->
            interactive_loop(index)

          true ->
            run_search(index, query, limit: 10)
            interactive_loop(index)
        end
    end
  end

  defp print_header(text) do
    IO.puts(String.duplicate("=", 60))
    IO.puts(text)
    IO.puts(String.duplicate("=", 60))
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
  SearchDemo.run(path)
else
  IO.puts(:stderr, "Directory not found: #{path}")
  System.halt(1)
end
