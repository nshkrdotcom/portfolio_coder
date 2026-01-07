defmodule PortfolioCoder.Workflow.Workflows do
  @moduledoc """
  Pre-built workflows for common code intelligence tasks.

  This module provides ready-to-use pipeline configurations for:
  - Repository analysis (scan, parse, graph, embed)
  - Code review (diff analysis, context gathering, review generation)
  - Refactoring (impact analysis, safe ordering, execution)

  ## Usage

      # Analyze a repository
      {:ok, result} = Workflows.analyze_repo("/path/to/repo")

      # Review code changes
      {:ok, result} = Workflows.review_code(diff_text, context)

      # Plan refactoring
      {:ok, result} = Workflows.plan_refactoring(graph, functions)
  """

  alias PortfolioCoder.Graph.CallGraph
  alias PortfolioCoder.Graph.InMemoryGraph
  alias PortfolioCoder.Indexer.CodeChunker
  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.Indexer.Parser
  alias PortfolioCoder.Workflow.Pipeline

  @doc """
  Build and run a repository analysis pipeline.

  Analyzes a repository by:
  1. Scanning for source files
  2. Parsing files to AST
  3. Extracting symbols and relationships
  4. Building code graph
  5. Creating searchable index

  ## Options

  - `:patterns` - File patterns to include (default: ["**/*.ex", "**/*.exs"])
  - `:exclude` - Patterns to exclude (default: ["**/deps/**", "**/_build/**"])

  ## Returns

  Returns `{:ok, result}` where result contains:
  - `:files` - List of scanned files
  - `:parsed` - Parsed AST results
  - `:graph` - Code graph (InMemoryGraph)
  - `:index` - Searchable index (InMemorySearch)
  """
  @spec analyze_repo(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def analyze_repo(path, opts \\ []) do
    patterns = Keyword.get(opts, :patterns, ["**/*.ex", "**/*.exs"])
    exclude = Keyword.get(opts, :exclude, ["**/deps/**", "**/_build/**", "**/node_modules/**"])

    Pipeline.new(:analyze_repo,
      context: %{
        path: path,
        patterns: patterns,
        exclude: exclude,
        files: [],
        parsed: [],
        chunks: [],
        graph: nil,
        index: nil
      }
    )
    |> Pipeline.add_step(:scan_files, &scan_files/1)
    |> Pipeline.add_step(:parse_files, &parse_files/1, depends_on: [:scan_files])
    |> Pipeline.add_step(:build_graph, &build_graph/1, depends_on: [:parse_files])
    |> Pipeline.add_step(:chunk_code, &chunk_code/1, depends_on: [:parse_files], parallel: true)
    |> Pipeline.add_step(:build_index, &build_index/1, depends_on: [:chunk_code])
    |> Pipeline.add_step(:analyze_graph, &analyze_graph/1, depends_on: [:build_graph])
    |> Pipeline.run()
  end

  @doc """
  Build and run a code review pipeline.

  Reviews code changes by:
  1. Parsing the diff
  2. Analyzing changed files
  3. Gathering related context
  4. Generating review comments

  ## Options

  - `:index` - Optional search index for context gathering
  - `:graph` - Optional code graph for impact analysis

  ## Returns

  Returns `{:ok, result}` where result contains:
  - `:changes` - Parsed diff changes
  - `:analysis` - Code analysis results
  - `:context` - Related code context
  - `:review` - Generated review
  """
  @spec review_code(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def review_code(diff, opts \\ []) do
    Pipeline.new(:review_code,
      context: %{
        diff: diff,
        index: Keyword.get(opts, :index),
        graph: Keyword.get(opts, :graph),
        changes: [],
        analysis: nil,
        related_context: [],
        review: nil
      }
    )
    |> Pipeline.add_step(:parse_diff, &parse_diff/1)
    |> Pipeline.add_step(:analyze_changes, &analyze_changes/1, depends_on: [:parse_diff])
    |> Pipeline.add_step(:get_context, &get_related_context/1,
      depends_on: [:analyze_changes],
      parallel: true
    )
    |> Pipeline.add_step(:check_impact, &check_impact/1,
      depends_on: [:analyze_changes],
      parallel: true
    )
    |> Pipeline.add_step(:generate_review, &generate_review/1,
      depends_on: [:get_context, :check_impact]
    )
    |> Pipeline.run()
  end

  @doc """
  Build and run a refactoring planning pipeline.

  Plans a refactoring by:
  1. Analyzing target functions
  2. Calculating impact
  3. Determining safe refactoring order
  4. Generating refactoring plan

  ## Options

  - `:functions` - List of function IDs to refactor

  ## Returns

  Returns `{:ok, result}` where result contains:
  - `:impact` - Impact analysis per function
  - `:order` - Safe refactoring order
  - `:plan` - Generated refactoring plan
  """
  @spec plan_refactoring(InMemoryGraph.graph(), [String.t()]) :: {:ok, map()} | {:error, map()}
  def plan_refactoring(graph, function_ids) do
    Pipeline.new(:plan_refactoring,
      context: %{
        graph: graph,
        function_ids: function_ids,
        impact: %{},
        order: [],
        plan: nil
      }
    )
    |> Pipeline.add_step(:analyze_impact, &analyze_refactor_impact/1)
    |> Pipeline.add_step(:determine_order, &determine_refactor_order/1,
      depends_on: [:analyze_impact]
    )
    |> Pipeline.add_step(:generate_plan, &generate_refactor_plan/1,
      depends_on: [:determine_order]
    )
    |> Pipeline.run()
  end

  # Analyze repo step implementations

  defp scan_files(ctx) do
    path = ctx.path
    patterns = ctx.patterns
    exclude = ctx.exclude

    files =
      patterns
      |> Enum.flat_map(fn pattern ->
        Path.join(path, pattern)
        |> Path.wildcard()
      end)
      |> Enum.reject(fn file ->
        Enum.any?(exclude, fn excl ->
          String.contains?(file, String.replace(excl, "**", ""))
        end)
      end)
      |> Enum.filter(&File.regular?/1)

    {:ok, %{ctx | files: files}}
  end

  defp parse_files(ctx) do
    parsed =
      ctx.files
      |> Enum.map(fn file ->
        content = File.read!(file)
        ext = Path.extname(file)

        language =
          case ext do
            ".ex" -> :elixir
            ".exs" -> :elixir
            ".py" -> :python
            ".js" -> :javascript
            ".ts" -> :typescript
            _ -> :unknown
          end

        case Parser.parse_string(content, language) do
          {:ok, parsed} ->
            %{
              path: file,
              relative_path: Path.relative_to(file, ctx.path),
              language: language,
              symbols: parsed.symbols,
              ast: parsed.raw
            }

          {:error, _} ->
            %{
              path: file,
              relative_path: Path.relative_to(file, ctx.path),
              language: language,
              symbols: [],
              ast: nil
            }
        end
      end)

    {:ok, %{ctx | parsed: parsed}}
  end

  defp build_graph(ctx) do
    {:ok, graph} = InMemoryGraph.new()

    # Add nodes for each file and its symbols
    for parsed <- ctx.parsed do
      # Add file node
      file_id = "file:#{parsed.relative_path}"

      InMemoryGraph.add_node(graph, %{
        id: file_id,
        type: :file,
        name: Path.basename(parsed.path),
        metadata: %{path: parsed.path, language: parsed.language}
      })

      # Add symbol nodes
      for symbol <- parsed.symbols do
        symbol_id = "#{symbol.type}:#{symbol.name}"

        InMemoryGraph.add_node(graph, %{
          id: symbol_id,
          type: symbol.type,
          name: symbol.name,
          metadata: Map.merge(symbol.metadata || %{}, %{file: parsed.relative_path})
        })

        # Link file -> symbol
        InMemoryGraph.add_edge(graph, %{
          source: file_id,
          target: symbol_id,
          type: :defines,
          metadata: %{}
        })
      end
    end

    {:ok, %{ctx | graph: graph}}
  end

  defp chunk_code(ctx) do
    chunks =
      ctx.parsed
      |> Enum.flat_map(&chunk_file/1)

    {:ok, %{ctx | chunks: chunks}}
  end

  defp chunk_file(parsed) do
    content = File.read!(parsed.path)

    case CodeChunker.chunk_content(content,
           language: parsed.language,
           strategy: :hybrid,
           chunk_size: 500
         ) do
      {:ok, file_chunks} ->
        Enum.map(file_chunks, fn chunk ->
          Map.merge(chunk, %{
            file: parsed.relative_path,
            language: parsed.language
          })
        end)

      {:error, _} ->
        []
    end
  end

  defp build_index(ctx) do
    {:ok, index} = InMemorySearch.new()

    for {chunk, idx} <- Enum.with_index(ctx.chunks) do
      InMemorySearch.add(index, %{
        id: "chunk:#{chunk.file}:#{idx}",
        content: chunk.content,
        metadata: %{
          path: chunk.file,
          language: chunk.language,
          type: chunk[:type] || :code,
          start_line: chunk[:start_line],
          end_line: chunk[:end_line]
        }
      })
    end

    {:ok, %{ctx | index: index}}
  end

  defp analyze_graph(ctx) do
    graph = ctx.graph

    {:ok, entry_points} = CallGraph.entry_points(graph)
    {:ok, leaf_functions} = CallGraph.leaf_functions(graph)
    {:ok, hot_paths} = CallGraph.hot_paths(graph, limit: 10)
    {:ok, sccs} = CallGraph.strongly_connected_components(graph)

    analysis = %{
      entry_point_count: length(entry_points),
      leaf_function_count: length(leaf_functions),
      hot_paths: hot_paths,
      cycles: Enum.filter(sccs, &(length(&1) > 1))
    }

    {:ok, Map.put(ctx, :graph_analysis, analysis)}
  end

  # Code review step implementations

  defp parse_diff(ctx) do
    diff = ctx.diff

    # Simple diff parser - extracts file names and changes
    changes =
      diff
      |> String.split(~r/^diff --git/m, trim: true)
      |> Enum.map(fn chunk ->
        file_match = Regex.run(~r/a\/(.+?) b\//, chunk)
        file = if file_match, do: Enum.at(file_match, 1), else: "unknown"

        added = length(Regex.scan(~r/^\+[^+]/m, chunk))
        removed = length(Regex.scan(~r/^-[^-]/m, chunk))

        %{
          file: file,
          added_lines: added,
          removed_lines: removed,
          raw: chunk
        }
      end)
      |> Enum.reject(&(&1.file == "unknown"))

    {:ok, %{ctx | changes: changes}}
  end

  defp analyze_changes(ctx) do
    analysis = %{
      total_files: length(ctx.changes),
      total_added: Enum.sum(Enum.map(ctx.changes, & &1.added_lines)),
      total_removed: Enum.sum(Enum.map(ctx.changes, & &1.removed_lines)),
      files_by_extension:
        ctx.changes
        |> Enum.group_by(&Path.extname(&1.file))
        |> Enum.map(fn {ext, files} -> {ext, length(files)} end)
        |> Map.new()
    }

    {:ok, %{ctx | analysis: analysis}}
  end

  defp get_related_context(ctx) do
    # If we have an index, search for related code
    related =
      case ctx.index do
        nil ->
          []

        index ->
          # Search for each changed file
          ctx.changes
          |> Enum.flat_map(fn change ->
            {:ok, results} = InMemorySearch.search(index, Path.basename(change.file), limit: 3)
            results
          end)
          |> Enum.uniq_by(& &1.id)
          |> Enum.take(10)
      end

    {:ok, %{ctx | related_context: related}}
  end

  defp check_impact(ctx) do
    # Calculate impact based on change size
    total_changes = ctx.analysis.total_added + ctx.analysis.total_removed

    risk_level =
      cond do
        total_changes > 500 -> :high
        total_changes > 100 -> :medium
        true -> :low
      end

    impact = %{
      total_changes: total_changes,
      risk_level: risk_level,
      # Additional graph-based analysis if graph available
      affected_modules:
        case ctx.graph do
          nil ->
            []

          graph ->
            # Could do more sophisticated analysis with the graph
            {:ok, nodes} = InMemoryGraph.nodes_by_type(graph, :module)
            Enum.take(nodes, 5)
        end
    }

    {:ok, Map.put(ctx, :impact, impact)}
  end

  defp generate_review(ctx) do
    review = %{
      summary:
        "Reviewed #{ctx.analysis.total_files} files with #{ctx.analysis.total_added} additions and #{ctx.analysis.total_removed} deletions",
      risk_level: ctx.impact[:risk_level] || :unknown,
      suggestions: generate_review_suggestions(ctx),
      context_files: Enum.map(ctx.related_context, & &1.metadata[:path])
    }

    {:ok, %{ctx | review: review}}
  end

  defp generate_review_suggestions(ctx) do
    suggestions = []

    suggestions =
      if ctx.analysis.total_added > 200 do
        ["Consider breaking this into smaller PRs" | suggestions]
      else
        suggestions
      end

    suggestions =
      if Map.get(ctx.analysis.files_by_extension, ".ex", 0) > 5 do
        ["Many Elixir files changed - ensure tests cover all changes" | suggestions]
      else
        suggestions
      end

    suggestions
  end

  # Refactoring step implementations

  defp analyze_refactor_impact(ctx) do
    graph = ctx.graph
    function_ids = ctx.function_ids

    impact =
      function_ids
      |> Enum.map(fn func_id ->
        {:ok, callers} = CallGraph.transitive_callers(graph, func_id, max_depth: 5)
        {:ok, callees} = CallGraph.transitive_callees(graph, func_id, max_depth: 5)

        {func_id,
         %{
           callers: callers,
           callees: callees,
           caller_count: length(callers),
           callee_count: length(callees),
           risk: if(length(callers) > 5, do: :high, else: :low)
         }}
      end)
      |> Map.new()

    {:ok, %{ctx | impact: impact}}
  end

  defp determine_refactor_order(ctx) do
    graph = ctx.graph
    function_ids = ctx.function_ids

    # Order by dependency - leaf functions first
    ordered =
      function_ids
      |> Enum.map(fn func_id ->
        {:ok, callees} = CallGraph.transitive_callees(graph, func_id, max_depth: 20)
        deps_in_set = Enum.count(callees, &(&1 in function_ids))
        {func_id, deps_in_set}
      end)
      |> Enum.sort_by(fn {_, deps} -> deps end)
      |> Enum.map(fn {func_id, _} -> func_id end)

    {:ok, %{ctx | order: ordered}}
  end

  defp generate_refactor_plan(ctx) do
    plan = %{
      steps:
        Enum.with_index(ctx.order, 1)
        |> Enum.map(fn {func_id, idx} ->
          impact = Map.get(ctx.impact, func_id, %{})

          %{
            order: idx,
            function: func_id,
            risk: impact[:risk] || :unknown,
            affected_callers: impact[:caller_count] || 0
          }
        end),
      total_functions: length(ctx.function_ids),
      high_risk_count: Enum.count(ctx.impact, fn {_, v} -> v.risk == :high end)
    }

    {:ok, %{ctx | plan: plan}}
  end
end
