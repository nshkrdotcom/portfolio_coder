defmodule Mix.Tasks.Code.Deps do
  @moduledoc """
  Analyze code dependencies.

  Build and query dependency graphs for code repositories.

  ## Usage

      mix code.deps COMMAND PATH [OPTIONS]

  ## Commands

    * `build` - Build a dependency graph
    * `show` - Show dependencies of an entity
    * `reverse` - Show reverse dependencies (dependents)
    * `cycles` - Find circular dependencies

  ## Options

    * `--graph` - Name of the graph (default: "deps")
    * `--language` - Project language (auto-detected)
    * `--depth` - Traversal depth for queries (default: 1)

  ## Examples

      mix code.deps build ./my_project
      mix code.deps show my_module --graph my_project
      mix code.deps reverse utils --depth 2
      mix code.deps cycles --graph my_project

  """
  use Mix.Task

  @shortdoc "Analyze code dependencies"

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:portfolio_coder)

    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          graph: :string,
          language: :string,
          depth: :integer,
          help: :boolean
        ],
        aliases: [g: :graph, l: :language, d: :depth, h: :help]
      )

    if opts[:help] do
      shell_info(@moduledoc)
    else
      case positional do
        ["build", path | _] -> build_graph(path, opts)
        ["show", entity | _] -> show_deps(entity, opts)
        ["reverse", entity | _] -> show_reverse_deps(entity, opts)
        ["cycles" | _] -> find_cycles(opts)
        _ -> shell_error("Unknown command. Use --help for usage.")
      end
    end
  end

  defp build_graph(path, opts) do
    path = Path.expand(path)
    graph_id = opts[:graph] || "deps"

    shell_info("Building dependency graph for: #{path}")

    build_opts =
      []
      |> maybe_add(:language, parse_language(opts[:language]))

    case PortfolioCoder.build_dependency_graph(graph_id, path, build_opts) do
      {:ok, stats} ->
        shell_info("""

        Dependency graph built!
          Graph ID: #{graph_id}
          Nodes: #{stats[:nodes] || "unknown"}
          Edges: #{stats[:edges] || "unknown"}
        """)

      {:error, reason} ->
        shell_error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp show_deps(entity, opts) do
    graph_id = opts[:graph] || "deps"
    depth = opts[:depth] || 1

    shell_info("Dependencies of #{entity} (depth: #{depth}):\n")

    case PortfolioCoder.get_dependencies(graph_id, entity, depth: depth) do
      {:ok, deps} ->
        if deps == [] do
          shell_info("No dependencies found.")
        else
          Enum.each(deps, &print_dep/1)
        end

      {:error, reason} ->
        shell_error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp show_reverse_deps(entity, opts) do
    graph_id = opts[:graph] || "deps"
    depth = opts[:depth] || 1

    shell_info("Dependents of #{entity} (depth: #{depth}):\n")

    case PortfolioCoder.get_dependents(graph_id, entity, depth: depth) do
      {:ok, deps} ->
        if deps == [] do
          shell_info("No dependents found.")
        else
          Enum.each(deps, &print_dep/1)
        end

      {:error, reason} ->
        shell_error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp find_cycles(opts) do
    graph_id = opts[:graph] || "deps"

    shell_info("Finding circular dependencies in graph: #{graph_id}\n")

    {:ok, cycles} = PortfolioCoder.find_cycles(graph_id)
    print_cycles(cycles)
  end

  defp print_cycles([]) do
    shell_info("No circular dependencies found!")
  end

  # dialyzer:no_return - cycles detection is a stub that always returns []
  @dialyzer {:nowarn_function, print_cycles: 1}
  defp print_cycles(cycles) do
    shell_info("Found #{length(cycles)} circular dependencies:\n")

    Enum.each(cycles, fn cycle ->
      path = Enum.join(cycle, " -> ")
      shell_info("  Warning: #{path}")
    end)
  end

  defp print_dep(dep) when is_map(dep) do
    name = dep[:id] || dep[:name] || "unknown"
    type = dep[:type] || ""
    shell_info("  * #{name} #{type}")
  end

  defp print_dep(dep), do: shell_info("  * #{dep}")

  defp shell_info(message), do: IO.puts(message)
  defp shell_error(message), do: IO.puts(:stderr, message)

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_language(nil), do: nil
  defp parse_language(lang), do: String.to_existing_atom(lang)
end
