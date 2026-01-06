defmodule Mix.Tasks.Code.Deps do
  @moduledoc """
  Analyze code dependencies.

  Build and query dependency graphs for code repositories using
  in-memory graph storage.

  ## Usage

      mix code.deps COMMAND PATH [OPTIONS]

  ## Commands

    * `build` - Build a dependency graph from parsed code
    * `show` - Show dependencies (imports) of a module
    * `reverse` - Show reverse dependencies (imported by)
    * `stats` - Show graph statistics

  ## Options

    * `--graph` - Name of the graph (default: "deps")

  ## Examples

      mix code.deps build ./my_project
      mix code.deps show MyModule --graph my_project
      mix code.deps reverse GenServer
      mix code.deps stats

  """
  use Mix.Task

  alias PortfolioCoder.Indexer.Parser
  alias PortfolioCoder.Graph.InMemoryGraph

  @shortdoc "Analyze code dependencies"

  @default_exclude [
    "deps/",
    "_build/",
    "node_modules/",
    ".git/"
  ]

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:portfolio_coder)

    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          graph: :string,
          help: :boolean
        ],
        aliases: [g: :graph, h: :help]
      )

    if opts[:help] do
      shell_info(@moduledoc)
    else
      case positional do
        ["build", path | _] -> build_graph(path, opts)
        ["show", entity | _] -> show_deps(entity, opts)
        ["reverse", entity | _] -> show_reverse_deps(entity, opts)
        ["stats" | _] -> show_stats(opts)
        _ -> shell_error("Unknown command. Use --help for usage.")
      end
    end
  end

  defp build_graph(path, opts) do
    path = Path.expand(path)
    graph_name = opts[:graph] || "deps"

    unless File.dir?(path) do
      shell_error("Error: #{path} is not a directory")
      exit({:shutdown, 1})
    end

    shell_info("Building dependency graph for: #{path}")

    # Find all source files
    files =
      path
      |> Path.join("**/*.{ex,exs,py,js,ts}")
      |> Path.wildcard()
      |> Enum.filter(fn file ->
        not Enum.any?(@default_exclude, &String.contains?(file, &1))
      end)
      |> Enum.sort()

    shell_info("Found #{length(files)} files to analyze")

    # Create or get the graph
    {:ok, graph} = get_or_create_graph(graph_name)

    # Process files
    files_processed =
      files
      |> Enum.reduce(0, fn file, count ->
        case Parser.parse(file) do
          {:ok, parsed} ->
            InMemoryGraph.add_from_parsed(graph, parsed, file)
            count + 1

          {:error, _} ->
            count
        end
      end)

    stats = InMemoryGraph.stats(graph)

    shell_info("""

    Dependency graph built!
      Graph name: #{graph_name}
      Files processed: #{files_processed}
      Nodes: #{stats.node_count}
      Edges: #{stats.edge_count}

    Node types:
    #{format_type_counts(stats.nodes_by_type)}

    Edge types:
    #{format_type_counts(stats.edges_by_type)}
    """)
  end

  defp show_deps(entity, opts) do
    graph_name = opts[:graph] || "deps"

    case get_graph(graph_name) do
      {:ok, graph} ->
        shell_info("Dependencies (imports) of #{entity}:\n")

        {:ok, imports} = InMemoryGraph.imports_of(graph, entity)

        if imports == [] do
          shell_info("No dependencies found.")
        else
          Enum.each(imports, fn imp ->
            shell_info("  * #{imp}")
          end)

          shell_info("\nTotal: #{length(imports)} dependencies")
        end

      {:error, :not_found} ->
        shell_error("Graph '#{graph_name}' not found. Run `mix code.deps build` first.")
    end
  end

  defp show_reverse_deps(entity, opts) do
    graph_name = opts[:graph] || "deps"

    case get_graph(graph_name) do
      {:ok, graph} ->
        shell_info("Modules that import #{entity}:\n")

        {:ok, importers} = InMemoryGraph.imported_by(graph, entity)

        if importers == [] do
          shell_info("No modules import this entity.")
        else
          Enum.each(importers, fn imp ->
            shell_info("  * #{imp}")
          end)

          shell_info("\nTotal: #{length(importers)} importers")
        end

      {:error, :not_found} ->
        shell_error("Graph '#{graph_name}' not found. Run `mix code.deps build` first.")
    end
  end

  defp show_stats(opts) do
    graph_name = opts[:graph] || "deps"

    case get_graph(graph_name) do
      {:ok, graph} ->
        stats = InMemoryGraph.stats(graph)

        shell_info("""
        Graph Statistics: #{graph_name}

        Nodes: #{stats.node_count}
        Edges: #{stats.edge_count}

        Node types:
        #{format_type_counts(stats.nodes_by_type)}

        Edge types:
        #{format_type_counts(stats.edges_by_type)}
        """)

        # Show top modules by connections
        {:ok, modules} = InMemoryGraph.nodes_by_type(graph, :module)

        if length(modules) > 0 do
          shell_info("Top modules by import count:")

          modules
          |> Enum.map(fn m ->
            {:ok, imports} = InMemoryGraph.imports_of(graph, m.id)
            {m.name, length(imports)}
          end)
          |> Enum.sort_by(fn {_, count} -> -count end)
          |> Enum.take(10)
          |> Enum.each(fn {name, count} ->
            shell_info("  #{name}: #{count} imports")
          end)
        end

      {:error, :not_found} ->
        shell_error("Graph '#{graph_name}' not found. Run `mix code.deps build` first.")
    end
  end

  defp get_or_create_graph(name) do
    key = {:code_graph, name}

    case :persistent_term.get(key, nil) do
      nil ->
        {:ok, graph} = InMemoryGraph.new()
        :persistent_term.put(key, graph)
        {:ok, graph}

      graph ->
        {:ok, graph}
    end
  end

  defp get_graph(name) do
    key = {:code_graph, name}

    case :persistent_term.get(key, nil) do
      nil -> {:error, :not_found}
      graph -> {:ok, graph}
    end
  end

  defp format_type_counts(type_map) do
    type_map
    |> Enum.sort_by(fn {_, count} -> -count end)
    |> Enum.map(fn {type, count} -> "  #{type}: #{count}" end)
    |> Enum.join("\n")
  end

  defp shell_info(message), do: IO.puts(message)
  defp shell_error(message), do: IO.puts(:stderr, message)
end
