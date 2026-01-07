defmodule Mix.Tasks.Code.Agent do
  @moduledoc """
  Run an interactive code agent session.

  ## Usage

      mix code.agent [path]
      mix code.agent --specialist debug
      mix code.agent --specialist refactor

  ## Options

    * `--specialist` - Use a specialist agent (debug, refactor, docs, test)
    * `--model` - LLM model to use (default: gemini)
    * `--verbose` - Show detailed output

  ## Examples

      # Start interactive agent
      mix code.agent

      # Start debug specialist
      mix code.agent --specialist debug lib/my_app

      # Start refactor analysis
      mix code.agent --specialist refactor lib/my_app/parser.ex
  """

  use Mix.Task

  alias PortfolioCoder.Agent.Specialists.DebugAgent
  alias PortfolioCoder.Agent.Specialists.DocsAgent
  alias PortfolioCoder.Agent.Specialists.RefactorAgent
  alias PortfolioCoder.Agent.Specialists.TestAgent
  alias PortfolioCoder.Graph.InMemoryGraph
  alias PortfolioCoder.Indexer.CodeChunker
  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.Indexer.Parser

  @shortdoc "Run interactive code agent"

  @switches [
    specialist: :string,
    model: :string,
    verbose: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, paths, _} = OptionParser.parse(args, switches: @switches)

    path = List.first(paths) || "lib"
    specialist = Keyword.get(opts, :specialist)
    verbose = Keyword.get(opts, :verbose, false)

    Mix.shell().info("Code Agent")
    Mix.shell().info(String.duplicate("=", 60))

    # Build index and graph
    Mix.shell().info("\nBuilding code index...")
    {:ok, index} = InMemorySearch.new()
    {:ok, graph} = InMemoryGraph.new()

    {doc_count, node_count} = build_index(path, index, graph, verbose)

    Mix.shell().info("  Indexed #{doc_count} documents, #{node_count} graph nodes")

    # Run appropriate agent
    case specialist do
      "debug" ->
        run_debug_agent(index, graph, path, verbose)

      "refactor" ->
        run_refactor_agent(index, graph, path, verbose)

      "docs" ->
        run_docs_agent(index, graph, verbose)

      "test" ->
        run_test_agent(index, graph, verbose)

      nil ->
        run_interactive(index, graph)

      other ->
        Mix.shell().error("Unknown specialist: #{other}")
        Mix.shell().info("Available: debug, refactor, docs, test")
    end
  end

  defp build_index(path, index, graph, verbose) do
    files = scan_files(path)

    maybe_log_file_count(verbose, files)
    doc_count = index_files(files, index, graph)

    stats = InMemoryGraph.stats(graph)
    {doc_count, stats.node_count}
  end

  defp maybe_log_file_count(true, files),
    do: Mix.shell().info("  Found #{length(files)} files")

  defp maybe_log_file_count(false, _files), do: :ok

  defp index_files(files, index, graph) do
    Enum.reduce(files, 0, fn file, count ->
      case index_file(file, index, graph) do
        {:ok, docs_added} -> count + docs_added
        :skip -> count
      end
    end)
  end

  defp index_file(file, index, graph) do
    with {:ok, parsed} <- Parser.parse(file),
         :ok <- InMemoryGraph.add_from_parsed(graph, parsed, file),
         {:ok, chunks} <- CodeChunker.chunk_file(file, strategy: :hybrid, chunk_size: 800) do
      docs = build_docs(file, parsed, chunks)
      InMemorySearch.add_all(index, docs)
      {:ok, length(docs)}
    else
      {:error, _} -> :skip
    end
  end

  defp build_docs(file, parsed, chunks) do
    Enum.with_index(chunks)
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
  end

  defp scan_files(path) do
    path
    |> Path.join("**/*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.filter(fn file ->
      not String.contains?(file, ["deps/", "_build/", ".git/"])
    end)
    |> Enum.take(50)
  end

  defp run_debug_agent(index, graph, path, _verbose) do
    Mix.shell().info("\n--- Debug Agent ---\n")

    # Create session with index and graph context
    session = DebugAgent.new_session(index: index, graph: graph)

    Mix.shell().info("Analyzing #{path} for issues...")

    # Use find_suspicious_code which returns a tuple with search results
    {:ok, result, _session} = DebugAgent.find_suspicious_code(session, "error handling issues")

    if Enum.empty?(result.search_matches) do
      Mix.shell().info("No suspicious patterns found.")
    else
      Mix.shell().info("\nPotential issues found:")

      for item <- Enum.take(result.search_matches, 10) do
        label = item.name || item.path || "unknown"
        Mix.shell().info("  - #{label}")
      end

      if not Enum.empty?(result.highly_connected) do
        Mix.shell().info("\nHighly connected (complex) code:")

        for func <- Enum.take(result.highly_connected, 5) do
          label = func.name || func.id || "unknown"
          Mix.shell().info("  - #{label}")
        end
      end
    end
  end

  defp run_refactor_agent(index, graph, path, _verbose) do
    Mix.shell().info("\n--- Refactor Agent ---\n")

    # Create session with index and graph context
    session = RefactorAgent.new_session(index: index, graph: graph)

    Mix.shell().info("Analyzing #{path} for refactoring opportunities...")

    {:ok, opportunities, _session} = RefactorAgent.find_opportunities(session)

    if Enum.empty?(opportunities) do
      Mix.shell().info("No refactoring opportunities found.")
    else
      Mix.shell().info("\nRefactoring opportunities:")

      for opp <- opportunities do
        Mix.shell().info("  [#{opp.type}] #{opp.description}")
        Mix.shell().info("    Impact: #{opp.impact}")
      end
    end
  end

  defp run_docs_agent(index, graph, _verbose) do
    Mix.shell().info("\n--- Documentation Agent ---\n")
    agent = DocsAgent.new(index, graph)

    {:ok, coverage} = DocsAgent.check_doc_coverage(agent)

    Mix.shell().info("Documentation Coverage: #{coverage.coverage_percentage}%")
    Mix.shell().info("  Documented: #{coverage.documented_modules}")
    Mix.shell().info("  Undocumented: #{coverage.undocumented_modules}")

    if coverage.undocumented_modules > 0 do
      Mix.shell().info("\nUndocumented modules:")

      for mod <- Enum.take(coverage.undocumented, 10) do
        Mix.shell().info("  - #{mod.name}")
      end
    end
  end

  defp run_test_agent(index, graph, _verbose) do
    Mix.shell().info("\n--- Test Agent ---\n")
    agent = TestAgent.new(index, graph)

    {:ok, report} = TestAgent.generate_test_report(agent)

    Mix.shell().info("Test Coverage:")
    Mix.shell().info("  Test files: #{report.summary.total_test_files}")
    Mix.shell().info("  Total tests: #{report.summary.total_tests}")
    Mix.shell().info("  Untested modules: #{report.summary.untested_modules}")

    if report.untested != [] do
      Mix.shell().info("\nUntested modules:")

      for mod <- Enum.take(report.untested, 10) do
        Mix.shell().info("  - #{mod.name}")
      end
    end
  end

  defp run_interactive(index, _graph) do
    Mix.shell().info("\n--- Interactive Mode ---")
    Mix.shell().info("Type a query to search code, or 'quit' to exit.\n")

    interactive_loop(index)
  end

  defp interactive_loop(index) do
    case IO.gets("> ") do
      :eof ->
        goodbye()

      {:error, _} ->
        goodbye()

      input ->
        handle_query(index, String.trim(input))
    end
  end

  defp handle_query(_index, query) when query in ["quit", "exit", "q"], do: goodbye()
  defp handle_query(index, ""), do: interactive_loop(index)

  defp handle_query(index, query) do
    show_results(index, query)
    interactive_loop(index)
  end

  defp show_results(index, query) do
    {:ok, results} = InMemorySearch.search(index, query, limit: 5)

    if Enum.empty?(results) do
      Mix.shell().info("No results found.\n")
    else
      Enum.each(results, &print_result/1)
    end
  end

  defp print_result(result) do
    path = result.metadata[:path] || result.id
    Mix.shell().info("#{path}:")
    Mix.shell().info("  #{String.slice(result.content, 0, 100)}...\n")
  end

  defp goodbye do
    Mix.shell().info("\nGoodbye!")
  end
end
