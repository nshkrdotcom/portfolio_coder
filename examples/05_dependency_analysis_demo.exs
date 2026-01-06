# examples/05_dependency_analysis_demo.exs
#
# Demonstrates: Code-Level Dependency Analysis
# Modules Used: PortfolioCoder.Indexer.Parser, PortfolioCoder.Graph.InMemoryGraph
# Prerequisites: None (no database required)
#
# Usage: mix run examples/05_dependency_analysis_demo.exs [path_to_directory]
#
# This demo shows how to analyze dependencies at the code level:
# 1. Extract imports, uses, and aliases from source files
# 2. Build a dependency graph
# 3. Detect internal vs external dependencies
# 4. Find dependency chains and cycles
# 5. Identify most-depended-on modules

alias PortfolioCoder.Indexer.Parser
alias PortfolioCoder.Graph.InMemoryGraph

defmodule DependencyAnalysisDemo do
  def run(path) do
    print_header("Code-Level Dependency Analysis Demo")

    IO.puts("Source directory: #{path}\n")

    # Step 1: Build graph
    IO.puts("Step 1: Parsing and building dependency graph...")
    {:ok, graph} = InMemoryGraph.new()
    files = scan_files(path)
    {success, _errors} = build_graph(graph, files)
    IO.puts("  Analyzed #{success} files.\n")

    # Step 2: Extract dependency information
    print_section("Internal Module Dependencies")
    analyze_internal_dependencies(graph)

    print_section("External Dependencies")
    analyze_external_dependencies(graph)

    print_section("Dependency Metrics")
    calculate_dependency_metrics(graph)

    print_section("Module Coupling Analysis")
    analyze_coupling(graph)

    print_section("Potential Issues")
    detect_issues(graph)

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
        not String.contains?(file, ["deps/", "_build/", "node_modules/", ".git/", "test/"])
    end)
    |> Enum.take(50)
    |> Enum.sort()
  end

  defp build_graph(graph, files) do
    files
    |> Enum.reduce({0, 0}, fn file, {success, errors} ->
      case Parser.parse(file) do
        {:ok, parsed} ->
          :ok = InMemoryGraph.add_from_parsed(graph, parsed, file)
          {success + 1, errors}

        {:error, _} ->
          {success, errors + 1}
      end
    end)
  end

  defp analyze_internal_dependencies(graph) do
    {:ok, modules} = InMemoryGraph.nodes_by_type(graph, :module)
    module_ids = MapSet.new(Enum.map(modules, & &1.id))

    # Find internal dependencies (module -> module where both exist in codebase)
    internal_deps =
      modules
      |> Enum.flat_map(fn module ->
        {:ok, imports} = InMemoryGraph.imports_of(graph, module.id)

        imports
        |> Enum.filter(fn imp -> MapSet.member?(module_ids, imp) end)
        |> Enum.map(fn imp -> {module.id, imp} end)
      end)

    if Enum.empty?(internal_deps) do
      IO.puts("No internal module dependencies detected.\n")
    else
      IO.puts("Found #{length(internal_deps)} internal dependencies:\n")

      internal_deps
      |> Enum.group_by(fn {from, _} -> from end)
      |> Enum.take(10)
      |> Enum.each(fn {from, deps} ->
        IO.puts("  #{shorten_module(from)}:")

        deps
        |> Enum.map(fn {_, to} -> to end)
        |> Enum.take(5)
        |> Enum.each(fn to ->
          IO.puts("    -> #{shorten_module(to)}")
        end)

        if length(deps) > 5 do
          IO.puts("    ... and #{length(deps) - 5} more")
        end
      end)

      IO.puts("")
    end
  end

  defp analyze_external_dependencies(graph) do
    {:ok, externals} = InMemoryGraph.nodes_by_type(graph, :external)

    if Enum.empty?(externals) do
      IO.puts("No external dependencies detected.\n")
    else
      # Group externals by category
      {elixir_core, other} =
        Enum.split_with(externals, fn ext ->
          ext.name in ~w(GenServer Supervisor Agent Task Application Logger File IO Enum Map List String Kernel)
        end)

      {hex_deps, truly_external} =
        Enum.split_with(other, fn ext ->
          String.starts_with?(ext.name, "PortfolioCore") or
            String.starts_with?(ext.name, "PortfolioIndex") or
            String.starts_with?(ext.name, "PortfolioManager") or
            String.starts_with?(ext.name, "Jason") or
            String.starts_with?(ext.name, "Phoenix") or
            String.starts_with?(ext.name, "Ecto")
        end)

      IO.puts("External dependencies by category:\n")

      unless Enum.empty?(elixir_core) do
        IO.puts("  Elixir Core (#{length(elixir_core)}):")

        elixir_core
        |> Enum.take(5)
        |> Enum.each(fn ext ->
          {:ok, importers} = InMemoryGraph.imported_by(graph, ext.id)
          IO.puts("    - #{ext.name} (used by #{length(importers)})")
        end)

        IO.puts("")
      end

      unless Enum.empty?(hex_deps) do
        IO.puts("  Libraries/Hex (#{length(hex_deps)}):")

        hex_deps
        |> Enum.map(fn ext ->
          {:ok, importers} = InMemoryGraph.imported_by(graph, ext.id)
          {ext, length(importers)}
        end)
        |> Enum.sort_by(fn {_, count} -> -count end)
        |> Enum.take(10)
        |> Enum.each(fn {ext, count} ->
          IO.puts("    - #{ext.name} (used by #{count})")
        end)

        IO.puts("")
      end

      unless Enum.empty?(truly_external) do
        IO.puts("  Other External (#{length(truly_external)}):")

        truly_external
        |> Enum.take(10)
        |> Enum.each(fn ext ->
          IO.puts("    - #{ext.name}")
        end)

        IO.puts("")
      end
    end
  end

  defp calculate_dependency_metrics(graph) do
    {:ok, modules} = InMemoryGraph.nodes_by_type(graph, :module)

    if Enum.empty?(modules) do
      IO.puts("No modules to analyze.\n")
    else
      metrics =
        modules
        |> Enum.map(fn module ->
          {:ok, imports} = InMemoryGraph.imports_of(graph, module.id)
          {:ok, importers} = InMemoryGraph.imported_by(graph, module.id)

          %{
            module: module.id,
            afferent: length(importers),
            efferent: length(imports),
            instability:
              if length(importers) + length(imports) > 0 do
                length(imports) / (length(importers) + length(imports))
              else
                0.5
              end
          }
        end)

      # Summary stats
      total_afferent = Enum.sum(Enum.map(metrics, & &1.afferent))
      total_efferent = Enum.sum(Enum.map(metrics, & &1.efferent))
      avg_instability = Enum.sum(Enum.map(metrics, & &1.instability)) / max(length(metrics), 1)

      IO.puts("Summary:")
      IO.puts("  Total incoming dependencies (Ca): #{total_afferent}")
      IO.puts("  Total outgoing dependencies (Ce): #{total_efferent}")
      IO.puts("  Average instability: #{Float.round(avg_instability, 2)}")
      IO.puts("")

      # Most stable modules (low instability, many dependents)
      stable =
        metrics
        |> Enum.filter(fn m -> m.afferent > 0 end)
        |> Enum.sort_by(& &1.instability)
        |> Enum.take(5)

      unless Enum.empty?(stable) do
        IO.puts("Most stable modules (low instability):")

        for m <- stable do
          IO.puts(
            "  #{shorten_module(m.module)}: I=#{Float.round(m.instability, 2)} (Ca=#{m.afferent}, Ce=#{m.efferent})"
          )
        end

        IO.puts("")
      end

      # Most unstable modules (high instability)
      unstable =
        metrics
        |> Enum.filter(fn m -> m.efferent > 0 end)
        |> Enum.sort_by(fn m -> -m.instability end)
        |> Enum.take(5)

      unless Enum.empty?(unstable) do
        IO.puts("Most unstable modules (high instability):")

        for m <- unstable do
          IO.puts(
            "  #{shorten_module(m.module)}: I=#{Float.round(m.instability, 2)} (Ca=#{m.afferent}, Ce=#{m.efferent})"
          )
        end

        IO.puts("")
      end
    end
  end

  defp analyze_coupling(graph) do
    {:ok, modules} = InMemoryGraph.nodes_by_type(graph, :module)

    if Enum.empty?(modules) do
      IO.puts("No modules to analyze.\n")
    else
      # Find modules with high coupling (many dependencies in or out)
      coupling_data =
        modules
        |> Enum.map(fn module ->
          {:ok, imports} = InMemoryGraph.imports_of(graph, module.id)
          {:ok, importers} = InMemoryGraph.imported_by(graph, module.id)
          total = length(imports) + length(importers)
          {module.id, total, length(imports), length(importers)}
        end)
        |> Enum.filter(fn {_, total, _, _} -> total > 0 end)
        |> Enum.sort_by(fn {_, total, _, _} -> -total end)
        |> Enum.take(10)

      if Enum.empty?(coupling_data) do
        IO.puts("No coupling detected between modules.\n")
      else
        IO.puts("Modules with highest coupling:")

        for {name, total, out, in_} <- coupling_data do
          IO.puts("  #{shorten_module(name)}: #{total} total (#{out} out, #{in_} in)")
        end

        IO.puts("")
      end
    end
  end

  defp detect_issues(graph) do
    issues = []

    # Check for modules with too many dependencies
    {:ok, modules} = InMemoryGraph.nodes_by_type(graph, :module)

    high_dep_modules =
      modules
      |> Enum.filter(fn module ->
        {:ok, imports} = InMemoryGraph.imports_of(graph, module.id)
        length(imports) > 10
      end)

    issues =
      if Enum.empty?(high_dep_modules) do
        issues
      else
        names = Enum.map(high_dep_modules, & &1.id) |> Enum.map(&shorten_module/1)
        [{"High dependency count (>10)", names} | issues]
      end

    # Check for orphan modules (no imports, no importers)
    orphans =
      modules
      |> Enum.filter(fn module ->
        {:ok, imports} = InMemoryGraph.imports_of(graph, module.id)
        {:ok, importers} = InMemoryGraph.imported_by(graph, module.id)
        Enum.empty?(imports) and Enum.empty?(importers)
      end)

    issues =
      if Enum.empty?(orphans) do
        issues
      else
        names = Enum.map(orphans, & &1.id) |> Enum.map(&shorten_module/1)
        [{"Isolated modules (no dependencies)", names} | issues]
      end

    if Enum.empty?(issues) do
      IO.puts("No potential issues detected.\n")
    else
      for {issue, items} <- issues do
        IO.puts("#{issue}:")

        for item <- Enum.take(items, 5) do
          IO.puts("  - #{item}")
        end

        if length(items) > 5 do
          IO.puts("  ... and #{length(items) - 5} more")
        end

        IO.puts("")
      end
    end
  end

  defp shorten_module(name) do
    # Remove common prefixes for readability
    name
    |> String.replace("PortfolioCoder.", "")
    |> String.replace("PortfolioCore.", "Core.")
    |> String.replace("PortfolioIndex.", "Index.")
    |> String.replace("PortfolioManager.", "Manager.")
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
  DependencyAnalysisDemo.run(path)
else
  IO.puts(:stderr, "Directory not found: #{path}")
  System.halt(1)
end
