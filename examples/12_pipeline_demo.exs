# examples/12_pipeline_demo.exs
#
# Demonstrates: Data Processing Pipeline for Code Indexing
# Modules Used: Various indexing modules
# Prerequisites: None
#
# Usage: mix run examples/12_pipeline_demo.exs [path_to_directory]
#
# This demo shows a complete code indexing pipeline:
# 1. Scan for source files
# 2. Parse each file (parallel)
# 3. Chunk code for indexing
# 4. Build search index
# 5. Build knowledge graph
# 6. Generate statistics

alias PortfolioCoder.Indexer.Parser
alias PortfolioCoder.Indexer.CodeChunker
alias PortfolioCoder.Indexer.InMemorySearch
alias PortfolioCoder.Graph.InMemoryGraph

defmodule PipelineDemo do
  @moduledoc """
  Demonstrates a complete code indexing pipeline.
  """

  def run(path) do
    print_header("Code Indexing Pipeline Demo")

    IO.puts("Source directory: #{path}\n")

    # Initialize pipeline state
    state = %{
      path: path,
      files: [],
      parsed: [],
      chunks: [],
      search_index: nil,
      graph: nil,
      stats: %{},
      timings: %{}
    }

    # Run pipeline stages
    state =
      state
      |> stage_scan()
      |> stage_parse()
      |> stage_chunk()
      |> stage_index()
      |> stage_graph()
      |> stage_stats()

    # Print results
    print_results(state)

    # Demo queries
    print_section("Pipeline Output Demo")
    demo_queries(state)

    IO.puts("")
    print_header("Pipeline Complete")
  end

  defp stage_scan(state) do
    IO.puts("Stage 1: Scanning for source files...")
    start_time = System.monotonic_time(:millisecond)

    files =
      state.path
      |> Path.join("**/*.{ex,exs,py,js,ts}")
      |> Path.wildcard()
      |> Enum.filter(fn file ->
        not String.contains?(file, ["deps/", "_build/", "node_modules/", ".git/"])
      end)
      |> Enum.sort()

    duration = System.monotonic_time(:millisecond) - start_time
    IO.puts("  Found #{length(files)} files in #{duration}ms\n")

    %{state | files: files, timings: Map.put(state.timings, :scan, duration)}
  end

  defp stage_parse(state) do
    IO.puts("Stage 2: Parsing source files (parallel)...")
    start_time = System.monotonic_time(:millisecond)

    parsed =
      state.files
      |> Task.async_stream(
        fn file ->
          case Parser.parse(file) do
            {:ok, result} -> {:ok, file, result}
            {:error, reason} -> {:error, file, reason}
          end
        end,
        max_concurrency: System.schedulers_online(),
        timeout: 30_000
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, "unknown", reason}
      end)

    {successes, failures} = Enum.split_with(parsed, fn {status, _, _} -> status == :ok end)

    duration = System.monotonic_time(:millisecond) - start_time

    IO.puts(
      "  Parsed #{length(successes)} files, #{length(failures)} failures in #{duration}ms\n"
    )

    %{
      state
      | parsed: successes,
        timings: Map.put(state.timings, :parse, duration),
        stats:
          Map.merge(state.stats, %{parse_success: length(successes), parse_fail: length(failures)})
    }
  end

  defp stage_chunk(state) do
    IO.puts("Stage 3: Chunking code for indexing...")
    start_time = System.monotonic_time(:millisecond)

    chunks =
      state.parsed
      |> Enum.flat_map(fn {:ok, file, parsed} ->
        case CodeChunker.chunk_file(file, strategy: :hybrid, chunk_size: 800) do
          {:ok, file_chunks} ->
            Enum.map(file_chunks, fn chunk ->
              %{
                file: file,
                language: parsed.language,
                chunk: chunk
              }
            end)

          {:error, _} ->
            []
        end
      end)

    duration = System.monotonic_time(:millisecond) - start_time
    IO.puts("  Created #{length(chunks)} chunks in #{duration}ms\n")

    %{
      state
      | chunks: chunks,
        timings: Map.put(state.timings, :chunk, duration),
        stats: Map.put(state.stats, :chunks, length(chunks))
    }
  end

  defp stage_index(state) do
    IO.puts("Stage 4: Building search index...")
    start_time = System.monotonic_time(:millisecond)

    {:ok, index} = InMemorySearch.new()

    docs =
      state.chunks
      |> Enum.with_index()
      |> Enum.map(fn {item, idx} ->
        %{
          id: "#{Path.basename(item.file)}:#{idx}",
          content: item.chunk.content,
          metadata: %{
            path: item.file,
            language: item.language,
            type: item.chunk.type,
            name: item.chunk.name
          }
        }
      end)

    :ok = InMemorySearch.add_all(index, docs)
    stats = InMemorySearch.stats(index)

    duration = System.monotonic_time(:millisecond) - start_time

    IO.puts(
      "  Indexed #{stats.document_count} documents, #{stats.term_count} terms in #{duration}ms\n"
    )

    %{
      state
      | search_index: index,
        timings: Map.put(state.timings, :index, duration),
        stats: Map.merge(state.stats, %{documents: stats.document_count, terms: stats.term_count})
    }
  end

  defp stage_graph(state) do
    IO.puts("Stage 5: Building knowledge graph...")
    start_time = System.monotonic_time(:millisecond)

    {:ok, graph} = InMemoryGraph.new()

    for {:ok, file, parsed} <- state.parsed do
      InMemoryGraph.add_from_parsed(graph, parsed, file)
    end

    stats = InMemoryGraph.stats(graph)

    duration = System.monotonic_time(:millisecond) - start_time
    IO.puts("  Created #{stats.node_count} nodes, #{stats.edge_count} edges in #{duration}ms\n")

    %{
      state
      | graph: graph,
        timings: Map.put(state.timings, :graph, duration),
        stats: Map.merge(state.stats, %{nodes: stats.node_count, edges: stats.edge_count})
    }
  end

  defp stage_stats(state) do
    IO.puts("Stage 6: Generating statistics...")

    # Language breakdown
    languages =
      state.parsed
      |> Enum.map(fn {:ok, _, parsed} -> parsed.language end)
      |> Enum.frequencies()

    # Symbol counts
    symbols =
      state.parsed
      |> Enum.flat_map(fn {:ok, _, parsed} -> parsed.symbols end)
      |> Enum.group_by(& &1.type)
      |> Enum.map(fn {type, list} -> {type, length(list)} end)
      |> Map.new()

    IO.puts("  Statistics computed\n")

    %{state | stats: Map.merge(state.stats, %{languages: languages, symbols: symbols})}
  end

  defp print_results(state) do
    print_section("Pipeline Results")

    IO.puts("Timing Summary:")

    total_time =
      state.timings
      |> Map.values()
      |> Enum.sum()

    for {stage, duration} <- Enum.sort(state.timings) do
      pct = Float.round(duration / total_time * 100, 1)
      IO.puts("  #{stage}: #{duration}ms (#{pct}%)")
    end

    IO.puts("  Total: #{total_time}ms\n")

    IO.puts("Index Summary:")
    IO.puts("  Files processed: #{state.stats[:parse_success]}")
    IO.puts("  Chunks created: #{state.stats[:chunks]}")
    IO.puts("  Documents indexed: #{state.stats[:documents]}")
    IO.puts("  Unique terms: #{state.stats[:terms]}")
    IO.puts("  Graph nodes: #{state.stats[:nodes]}")
    IO.puts("  Graph edges: #{state.stats[:edges]}")
    IO.puts("")

    IO.puts("Languages:")

    for {lang, count} <- Map.get(state.stats, :languages, %{}) do
      IO.puts("  #{lang}: #{count} files")
    end

    IO.puts("")

    IO.puts("Symbols:")

    for {type, count} <- Map.get(state.stats, :symbols, %{}) do
      IO.puts("  #{type}: #{count}")
    end
  end

  defp demo_queries(state) do
    IO.puts("\nDemo: Search Query")
    {:ok, results} = InMemorySearch.search(state.search_index, "function parse", limit: 3)
    IO.puts("  Query: 'function parse'")
    IO.puts("  Results: #{length(results)}")

    for r <- results do
      IO.puts("    - #{Path.basename(r.metadata[:path])}: #{r.metadata[:name] || "unnamed"}")
    end

    IO.puts("\nDemo: Graph Query")
    {:ok, modules} = InMemoryGraph.nodes_by_type(state.graph, :module)
    IO.puts("  Modules found: #{length(modules)}")

    for m <- Enum.take(modules, 5) do
      IO.puts("    - #{m.name}")
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
  PipelineDemo.run(path)
else
  IO.puts(:stderr, "Directory not found: #{path}")
  System.halt(1)
end
