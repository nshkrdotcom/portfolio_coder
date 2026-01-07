defmodule Mix.Tasks.Code.Docs do
  @moduledoc """
  Analyze and generate documentation.

  ## Usage

      mix code.docs [path]
      mix code.docs --coverage
      mix code.docs --generate

  ## Options

    * `--coverage` - Show documentation coverage report
    * `--generate` - Generate documentation for undocumented modules
    * `--format` - Output format (markdown, html)
    * `--output` - Output directory for generated docs

  ## Examples

      # Check documentation coverage
      mix code.docs --coverage lib

      # Generate README
      mix code.docs --generate --format markdown
  """

  use Mix.Task

  alias PortfolioCoder.Agent.Specialists.DocsAgent
  alias PortfolioCoder.Docs.Generator
  alias PortfolioCoder.Graph.InMemoryGraph
  alias PortfolioCoder.Indexer.CodeChunker
  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.Indexer.Parser

  @shortdoc "Analyze and generate documentation"

  @switches [
    coverage: :boolean,
    generate: :boolean,
    format: :string,
    output: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, paths, _} = OptionParser.parse(args, switches: @switches)

    path = List.first(paths) || "lib"

    Mix.shell().info("Documentation Analysis")
    Mix.shell().info(String.duplicate("=", 60))

    # Build index and graph
    Mix.shell().info("\nIndexing code...")
    {:ok, index} = InMemorySearch.new()
    {:ok, graph} = InMemoryGraph.new()

    doc_count = build_index(path, index, graph)
    Mix.shell().info("  Indexed #{doc_count} documents\n")

    cond do
      Keyword.get(opts, :coverage, false) ->
        show_coverage(index, graph)

      Keyword.get(opts, :generate, false) ->
        generate_docs(index, graph, opts)

      true ->
        # Default: show coverage
        show_coverage(index, graph)
    end
  end

  defp build_index(path, index, graph) do
    path
    |> Path.join("**/*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.reject(&excluded_path?/1)
    |> Enum.reduce(0, fn file, count ->
      case index_file(file, index, graph) do
        {:ok, docs_added} -> count + docs_added
        :skip -> count
      end
    end)
  end

  defp excluded_path?(file) do
    String.contains?(file, ["deps/", "_build/", ".git/"])
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
          type: chunk.type
        }
      }
    end)
  end

  defp show_coverage(index, graph) do
    agent = DocsAgent.new(index, graph)

    Mix.shell().info("--- Documentation Coverage ---\n")

    {:ok, coverage} = DocsAgent.check_doc_coverage(agent)

    Mix.shell().info("Overall Coverage: #{coverage.coverage_percentage}%")
    Mix.shell().info("")
    Mix.shell().info("  Total modules: #{coverage.total_modules}")
    Mix.shell().info("  Documented: #{coverage.documented_modules}")
    Mix.shell().info("  Undocumented: #{coverage.undocumented_modules}")

    if coverage.undocumented_modules > 0 do
      Mix.shell().info("\nUndocumented modules:")

      for mod <- Enum.take(coverage.undocumented, 15) do
        Mix.shell().info("  ✗ #{mod.name}")
        Mix.shell().info("    #{mod.path}")
      end

      undocumented_count = length(coverage.undocumented)

      if undocumented_count > 15 do
        Mix.shell().info("  ... and #{undocumented_count - 15} more")
      end
    end

    # Validate existing docs
    {:ok, issues} = DocsAgent.validate_docs(agent)

    if issues != [] do
      Mix.shell().info("\nDocumentation Issues:")

      for issue <- Enum.take(issues, 10) do
        Mix.shell().info("  ⚠ #{issue.module}: #{issue.message}")
      end
    end

    # Show suggestions
    Mix.shell().info("\n--- Suggestions ---")

    if coverage.coverage_percentage < 50 do
      Mix.shell().info(
        "• Documentation coverage is below 50%. Consider documenting core modules first."
      )
    end

    undoc_with_deps =
      coverage.undocumented
      |> Enum.filter(fn m -> String.contains?(m.name, ".") end)
      |> length()

    if undoc_with_deps > 5 do
      Mix.shell().info(
        "• #{undoc_with_deps} public modules are undocumented. Start with the most used ones."
      )
    end
  end

  defp generate_docs(index, graph, opts) do
    format = Keyword.get(opts, :format, "markdown") |> String.to_atom()
    output_dir = Keyword.get(opts, :output, "docs")

    gen = Generator.new(index, graph, format: format)

    Mix.shell().info("--- Generating Documentation ---\n")

    # Generate README
    {:ok, readme} = Generator.generate_readme(gen)
    readme_path = Path.join(output_dir, "README.md")

    File.mkdir_p!(output_dir)
    File.write!(readme_path, readme)
    Mix.shell().info("Generated: #{readme_path}")

    # Generate module docs
    agent = DocsAgent.new(index, graph)
    {:ok, coverage} = DocsAgent.check_doc_coverage(agent)

    for mod <- Enum.take(coverage.documented, 10) do
      {:ok, doc} = Generator.generate_module_doc(gen, mod.name)

      filename =
        mod.name
        |> String.replace(".", "_")
        |> String.downcase()

      doc_path = Path.join(output_dir, "#{filename}.md")
      File.write!(doc_path, doc)
      Mix.shell().info("Generated: #{doc_path}")
    end

    Mix.shell().info("\nDone! Generated documentation in #{output_dir}/")
  end
end
