# examples/04_graph_build_demo.exs
#
# Demonstrates: Code Graph Building and Querying
# Modules Used: PortfolioCoder.Indexer.Parser, PortfolioCoder.Graph.InMemoryGraph
# Prerequisites: None (no database required)
#
# Usage: mix run examples/04_graph_build_demo.exs [path_to_directory]
#
# This demo shows how to build a code graph from source files:
# 1. Parse source files to extract symbols and references
# 2. Build an in-memory graph of code relationships
# 3. Query the graph for dependencies, callers/callees, etc.
# 4. Find paths between code entities

alias PortfolioCoder.Indexer.Parser
alias PortfolioCoder.Graph.InMemoryGraph

defmodule GraphBuildDemo do
  def run(path) do
    print_header("Code Graph Building Demo")

    IO.puts("Source directory: #{path}\n")

    # Step 1: Create graph
    IO.puts("Step 1: Creating in-memory graph...")
    {:ok, graph} = InMemoryGraph.new()
    IO.puts("  Graph created.\n")

    # Step 2: Scan and parse files
    IO.puts("Step 2: Scanning and parsing source files...")
    files = scan_files(path)
    IO.puts("  Found #{length(files)} files.\n")

    # Step 3: Build graph from parsed files
    IO.puts("Step 3: Building graph from parsed code...")
    {success_count, error_count} = build_graph_from_files(graph, files)
    IO.puts("  Processed #{success_count} files successfully, #{error_count} errors.\n")

    # Step 4: Display graph statistics
    print_section("Graph Statistics")
    stats = InMemoryGraph.stats(graph)
    display_stats(stats)

    # Step 5: Query examples
    print_section("Graph Queries")

    # Show all modules
    demo_modules(graph)

    # Show imports for each module
    demo_imports(graph)

    # Show function definitions
    demo_functions(graph)

    # Show external dependencies
    demo_external_deps(graph)

    # Step 6: Path finding (if we have enough nodes)
    print_section("Path Finding")
    demo_path_finding(graph)

    IO.puts("\n")
    print_header("Demo Complete")
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
    |> Enum.take(30)
    |> Enum.sort()
  end

  defp build_graph_from_files(graph, files) do
    files
    |> Enum.reduce({0, 0}, fn file, {success, errors} ->
      case Parser.parse(file) do
        {:ok, parsed} ->
          :ok = InMemoryGraph.add_from_parsed(graph, parsed, file)
          {success + 1, errors}

        {:error, _reason} ->
          {success, errors + 1}
      end
    end)
  end

  defp display_stats(stats) do
    IO.puts("Total nodes: #{stats.node_count}")
    IO.puts("Total edges: #{stats.edge_count}")
    IO.puts("")

    IO.puts("Nodes by type:")

    stats.nodes_by_type
    |> Enum.sort_by(fn {_, count} -> -count end)
    |> Enum.each(fn {type, count} ->
      IO.puts("  #{type}: #{count}")
    end)

    IO.puts("")

    IO.puts("Edges by type:")

    stats.edges_by_type
    |> Enum.sort_by(fn {_, count} -> -count end)
    |> Enum.each(fn {type, count} ->
      IO.puts("  #{type}: #{count}")
    end)

    IO.puts("")
  end

  defp demo_modules(graph) do
    {:ok, modules} = InMemoryGraph.nodes_by_type(graph, :module)

    if Enum.empty?(modules) do
      IO.puts("No modules found in the graph.\n")
    else
      IO.puts("Modules (#{length(modules)}):")

      modules
      |> Enum.take(10)
      |> Enum.each(fn module ->
        IO.puts("  - #{module.name}")
      end)

      if length(modules) > 10 do
        IO.puts("  ... and #{length(modules) - 10} more")
      end

      IO.puts("")
    end
  end

  defp demo_imports(graph) do
    {:ok, modules} = InMemoryGraph.nodes_by_type(graph, :module)

    modules_with_imports =
      modules
      |> Enum.map(fn module ->
        {:ok, imports} = InMemoryGraph.imports_of(graph, module.id)
        {module, imports}
      end)
      |> Enum.filter(fn {_, imports} -> length(imports) > 0 end)
      |> Enum.take(5)

    if Enum.empty?(modules_with_imports) do
      IO.puts("No imports found in modules.\n")
    else
      IO.puts("Module imports (showing up to 5 modules):")

      modules_with_imports
      |> Enum.each(fn {module, imports} ->
        IO.puts("  #{module.name} imports:")

        imports
        |> Enum.take(5)
        |> Enum.each(fn imp ->
          IO.puts("    - #{imp}")
        end)

        if length(imports) > 5 do
          IO.puts("    ... and #{length(imports) - 5} more")
        end
      end)

      IO.puts("")
    end
  end

  defp demo_functions(graph) do
    {:ok, functions} = InMemoryGraph.nodes_by_type(graph, :function)

    if Enum.empty?(functions) do
      IO.puts("No functions found in the graph.\n")
    else
      IO.puts("Functions (#{length(functions)}, showing 15):")

      functions
      |> Enum.take(15)
      |> Enum.each(fn func ->
        visibility = if func.metadata[:visibility] == :private, do: " (private)", else: ""
        IO.puts("  - #{func.id}#{visibility}")
      end)

      if length(functions) > 15 do
        IO.puts("  ... and #{length(functions) - 15} more")
      end

      IO.puts("")
    end
  end

  defp demo_external_deps(graph) do
    {:ok, externals} = InMemoryGraph.nodes_by_type(graph, :external)

    if Enum.empty?(externals) do
      IO.puts("No external dependencies found.\n")
    else
      # Group by how many modules import each external
      external_usage =
        externals
        |> Enum.map(fn ext ->
          {:ok, importers} = InMemoryGraph.imported_by(graph, ext.id)
          {ext, length(importers)}
        end)
        |> Enum.sort_by(fn {_, count} -> -count end)
        |> Enum.take(10)

      IO.puts("External dependencies (top 10 by usage):")

      external_usage
      |> Enum.each(fn {ext, count} ->
        IO.puts("  #{ext.name}: used by #{count} module(s)")
      end)

      IO.puts("")
    end
  end

  defp demo_path_finding(graph) do
    {:ok, modules} = InMemoryGraph.nodes_by_type(graph, :module)

    if length(modules) >= 2 do
      # Try to find a path between the first two modules
      [m1, m2 | _] = modules

      IO.puts("Finding path from #{m1.id} to #{m2.id}...")

      case InMemoryGraph.find_path(graph, m1.id, m2.id, max_depth: 5) do
        {:ok, path} ->
          IO.puts("  Path found:")
          path_str = Enum.join(path, " -> ")
          IO.puts("    #{path_str}")

        {:error, :no_path} ->
          IO.puts("  No direct path found (modules may not be connected).")
      end

      # Try finding path to an external dependency
      {:ok, externals} = InMemoryGraph.nodes_by_type(graph, :external)

      if length(externals) > 0 do
        ext = hd(externals)
        IO.puts("\nFinding path from #{m1.id} to external #{ext.id}...")

        case InMemoryGraph.find_path(graph, m1.id, ext.id, max_depth: 3) do
          {:ok, path} ->
            IO.puts("  Path found:")
            path_str = Enum.join(path, " -> ")
            IO.puts("    #{path_str}")

          {:error, :no_path} ->
            IO.puts("  No path found.")
        end
      end
    else
      IO.puts("Not enough modules for path finding demo.")
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
  GraphBuildDemo.run(path)
else
  IO.puts(:stderr, "Directory not found: #{path}")
  System.halt(1)
end
