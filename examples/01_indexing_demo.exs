# examples/01_indexing_demo.exs
#
# Demonstrates: Code Parsing and Chunking Pipeline
# Modules Used: PortfolioCoder.Indexer.Parser, PortfolioCoder.Indexer.CodeChunker
# Prerequisites: None (no database required)
#
# Usage: mix run examples/01_indexing_demo.exs [path_to_file_or_directory]
#
# This demo shows the code intelligence pipeline without database storage:
# 1. Parse source files to extract symbols and references
# 2. Chunk code using different strategies
# 3. Display extracted information

alias PortfolioCoder.Indexer.Parser
alias PortfolioCoder.Indexer.CodeChunker

defmodule IndexingDemo do
  def run(path) do
    print_header("Code Indexing Pipeline Demo")

    if File.dir?(path) do
      demo_directory(path)
    else
      demo_single_file(path)
    end
  end

  defp demo_single_file(path) do
    IO.puts("Analyzing file: #{path}\n")

    case Parser.parse(path) do
      {:ok, result} ->
        display_parse_result(path, result)
        demo_chunking(path, result.language)

      {:error, reason} ->
        IO.puts(:stderr, "Error parsing file: #{inspect(reason)}")
    end
  end

  defp demo_directory(path) do
    IO.puts("Scanning directory: #{path}\n")

    files = find_source_files(path)
    IO.puts("Found #{length(files)} source files\n")

    # Parse each file and collect stats
    results =
      files
      |> Enum.take(10)
      |> Enum.map(fn file ->
        case Parser.parse(file) do
          {:ok, result} -> {:ok, file, result}
          {:error, reason} -> {:error, file, reason}
        end
      end)

    # Display summary
    display_directory_summary(results)

    # Pick first successful file for chunking demo
    case Enum.find(results, fn {status, _, _} -> status == :ok end) do
      {:ok, file, result} ->
        IO.puts("\n")
        print_header("Detailed Analysis: #{Path.basename(file)}")
        display_parse_result(file, result)
        demo_chunking(file, result.language)

      nil ->
        IO.puts("No files could be parsed successfully.")
    end
  end

  defp find_source_files(path) do
    extensions = [".ex", ".exs", ".py", ".js", ".ts"]

    path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(fn file ->
      File.regular?(file) and
        Path.extname(file) in extensions and
        not String.contains?(file, ["deps/", "_build/", "node_modules/", ".git/"])
    end)
    |> Enum.sort()
  end

  defp display_parse_result(_path, result) do
    IO.puts("Language: #{result.language}")
    IO.puts("")

    # Symbols
    print_subheader("Symbols (#{length(result.symbols)})")

    result.symbols
    |> Enum.group_by(& &1.type)
    |> Enum.each(fn {type, symbols} ->
      IO.puts("  #{type}: #{length(symbols)}")

      symbols
      |> Enum.take(5)
      |> Enum.each(fn s ->
        visibility = if s.visibility == :private, do: " (private)", else: ""
        IO.puts("    - #{s.name}#{visibility} [line #{s.line}]")
      end)

      if length(symbols) > 5 do
        IO.puts("    ... and #{length(symbols) - 5} more")
      end
    end)

    IO.puts("")

    # References
    print_subheader("References (#{length(result.references)})")

    result.references
    |> Enum.group_by(& &1.type)
    |> Enum.each(fn {type, refs} ->
      IO.puts("  #{type}: #{length(refs)}")

      refs
      |> Enum.take(3)
      |> Enum.each(fn r ->
        IO.puts("    - #{r.module} [line #{r.line}]")
      end)
    end)

    IO.puts("")
  end

  defp display_directory_summary(results) do
    successful = Enum.count(results, fn {s, _, _} -> s == :ok end)
    failed = Enum.count(results, fn {s, _, _} -> s == :error end)

    print_subheader("Parse Results")
    IO.puts("  Successful: #{successful}")
    IO.puts("  Failed: #{failed}")
    IO.puts("")

    # Aggregate stats
    all_symbols =
      results
      |> Enum.filter(fn {s, _, _} -> s == :ok end)
      |> Enum.flat_map(fn {:ok, _, result} -> result.symbols end)

    all_refs =
      results
      |> Enum.filter(fn {s, _, _} -> s == :ok end)
      |> Enum.flat_map(fn {:ok, _, result} -> result.references end)

    print_subheader("Symbol Summary")

    all_symbols
    |> Enum.group_by(& &1.type)
    |> Enum.sort_by(fn {_, items} -> -length(items) end)
    |> Enum.each(fn {type, items} ->
      IO.puts("  #{type}: #{length(items)}")
    end)

    IO.puts("")

    print_subheader("Reference Summary")

    all_refs
    |> Enum.group_by(& &1.type)
    |> Enum.sort_by(fn {_, items} -> -length(items) end)
    |> Enum.each(fn {type, items} ->
      IO.puts("  #{type}: #{length(items)}")
    end)
  end

  defp demo_chunking(path, _language) do
    print_header("Code Chunking Demo")

    strategies = [:function, :hybrid, :lines]

    for strategy <- strategies do
      IO.puts("Strategy: #{strategy}")

      case CodeChunker.chunk_file(path, strategy: strategy, chunk_size: 1000) do
        {:ok, chunks} ->
          IO.puts("  Chunks created: #{length(chunks)}")

          chunks
          |> Enum.take(3)
          |> Enum.with_index(1)
          |> Enum.each(fn {chunk, idx} ->
            preview = chunk.content |> String.slice(0, 60) |> String.replace("\n", " ")
            IO.puts("  #{idx}. [#{chunk.type}] #{chunk.name || "unnamed"}")
            IO.puts("     Lines #{chunk.start_line}-#{chunk.end_line}: \"#{preview}...\"")
          end)

          if length(chunks) > 3 do
            IO.puts("  ... and #{length(chunks) - 3} more chunks")
          end

        {:error, reason} ->
          IO.puts("  Error: #{inspect(reason)}")
      end

      IO.puts("")
    end
  end

  defp print_header(text) do
    IO.puts(String.duplicate("=", 60))
    IO.puts(text)
    IO.puts(String.duplicate("=", 60))
    IO.puts("")
  end

  defp print_subheader(text) do
    IO.puts("#{text}")
    IO.puts(String.duplicate("-", String.length(text)))
  end
end

# Main execution
path =
  case System.argv() do
    [arg | _] -> Path.expand(arg)
    [] -> Path.expand("lib/portfolio_coder")
  end

if File.exists?(path) do
  IndexingDemo.run(path)
else
  IO.puts(:stderr, "Path not found: #{path}")
  System.halt(1)
end

IO.puts("")
IO.puts("Demo complete!")
