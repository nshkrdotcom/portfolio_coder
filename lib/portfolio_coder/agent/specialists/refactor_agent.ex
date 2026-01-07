defmodule PortfolioCoder.Agent.Specialists.RefactorAgent do
  @moduledoc """
  Specialized agent for code refactoring analysis.

  The RefactorAgent helps identify refactoring opportunities, analyze code
  structure, and suggest improvements without changing behavior.

  ## Features

  - Code smell detection
  - Complexity analysis
  - Duplication finding
  - Module cohesion analysis
  - Dependency analysis for safe refactoring

  ## Usage

      session = RefactorAgent.new_session(index: index, graph: graph)
      {:ok, opportunities, session} = RefactorAgent.find_opportunities(session)
      {:ok, analysis, session} = RefactorAgent.analyze_module(session, "MyModule")
  """

  alias PortfolioCoder.Agent.CodeAgent
  alias PortfolioCoder.Agent.Session
  alias PortfolioCoder.Graph.CallGraph
  alias PortfolioCoder.Graph.InMemoryGraph

  @doc """
  Create a new refactor session with specialized context.
  """
  @spec new_session(keyword()) :: Session.t()
  def new_session(opts \\ []) do
    session = Session.new(opts)
    Session.update_context(session, :agent_type, :refactor)
  end

  @doc """
  Find refactoring opportunities in the codebase.

  Analyzes the code graph for:
  - High complexity functions
  - Low cohesion modules
  - Unused code (no callers)
  - Circular dependencies
  """
  @spec find_opportunities(Session.t()) :: {:ok, map(), Session.t()}
  def find_opportunities(session) do
    session = Session.add_user_message(session, "Find refactoring opportunities")

    case session.context[:graph] do
      nil ->
        {:ok, %{error: "No graph available"}, session}

      graph ->
        opportunities = %{
          high_complexity: find_high_complexity_functions(graph),
          low_cohesion: find_low_cohesion_modules(graph),
          dead_code: find_dead_code(graph),
          circular_deps: find_circular_dependencies(graph),
          god_functions: find_god_functions(graph)
        }

        summary = summarize_opportunities(opportunities)

        session =
          Session.add_assistant_message(session, format_opportunities(opportunities, summary))

        {:ok, Map.put(opportunities, :summary, summary), session}
    end
  end

  @doc """
  Analyze a specific module for refactoring opportunities.
  """
  @spec analyze_module(Session.t(), String.t()) :: {:ok, map(), Session.t()}
  def analyze_module(session, module_id) do
    session = Session.add_user_message(session, "Analyze module: #{module_id}")

    case session.context[:graph] do
      nil ->
        {:ok, %{error: "No graph available"}, session}

      graph ->
        # Get module stats
        {:ok, stats} = CallGraph.module_call_stats(graph, module_id)

        # Get functions in module
        {:ok, functions} = InMemoryGraph.functions_of(graph, module_id)

        # Analyze each function
        function_analyses =
          functions
          |> Enum.map(fn func_id ->
            {:ok, callers} = InMemoryGraph.callers(graph, func_id)
            {:ok, callees} = InMemoryGraph.callees(graph, func_id)

            %{
              id: func_id,
              caller_count: length(callers),
              callee_count: length(callees),
              complexity: length(callers) * 2 + length(callees)
            }
          end)
          |> Enum.sort_by(& &1.complexity, :desc)

        # Get imports
        {:ok, imports} = InMemoryGraph.imports_of(graph, module_id)

        analysis = %{
          module: module_id,
          function_count: stats.function_count,
          internal_calls: stats.internal_calls,
          external_dependencies: stats.external_dependencies,
          cohesion: stats.cohesion,
          imports: imports,
          functions: function_analyses,
          suggestions: generate_module_suggestions(stats, function_analyses)
        }

        session = Session.add_assistant_message(session, format_module_analysis(analysis))

        {:ok, analysis, session}
    end
  end

  @doc """
  Analyze impact of refactoring a specific function.

  Shows what would be affected if this function is changed.
  """
  @spec analyze_impact(Session.t(), String.t()) :: {:ok, map(), Session.t()}
  def analyze_impact(session, function_id) do
    session = Session.add_user_message(session, "Impact analysis: #{function_id}")

    case session.context[:graph] do
      nil ->
        {:ok, %{error: "No graph available"}, session}

      graph ->
        # Get all transitive callers (what would break)
        {:ok, affected_callers} = CallGraph.transitive_callers(graph, function_id, max_depth: 10)

        # Get all transitive callees (what this depends on)
        {:ok, dependencies} = CallGraph.transitive_callees(graph, function_id, max_depth: 10)

        # Find entry points that would be affected
        {:ok, entry_points} = CallGraph.entry_points(graph)
        entry_ids = MapSet.new(Enum.map(entry_points, & &1.id))
        affected_entries = Enum.filter(affected_callers, &MapSet.member?(entry_ids, &1))

        impact = %{
          function: function_id,
          affected_callers: affected_callers,
          affected_count: length(affected_callers),
          dependencies: dependencies,
          dependency_count: length(dependencies),
          affected_entry_points: affected_entries,
          risk_level: calculate_risk_level(affected_callers, affected_entries)
        }

        session = Session.add_assistant_message(session, format_impact(impact))

        {:ok, impact, session}
    end
  end

  @doc """
  Find similar code that might be candidates for extraction.
  """
  @spec find_similar_code(Session.t(), String.t()) :: {:ok, map(), Session.t()}
  def find_similar_code(session, code_snippet) do
    session =
      Session.add_user_message(session, "Find similar: #{String.slice(code_snippet, 0, 50)}...")

    # Use search to find similar code
    {:ok, results, session} =
      CodeAgent.execute_tool(session, :search_code, %{
        query: code_snippet,
        limit: 10
      })

    similar = %{
      query: code_snippet,
      matches: results,
      match_count: length(results),
      extraction_candidates: filter_extraction_candidates(results)
    }

    session = Session.add_assistant_message(session, format_similar(similar))

    {:ok, similar, session}
  end

  @doc """
  Suggest a safe refactoring order for a set of functions.
  """
  @spec suggest_refactoring_order(Session.t(), [String.t()]) :: {:ok, map(), Session.t()}
  def suggest_refactoring_order(session, function_ids) do
    session = Session.add_user_message(session, "Order refactoring: #{inspect(function_ids)}")

    case session.context[:graph] do
      nil ->
        {:ok, %{error: "No graph available"}, session}

      graph ->
        # Calculate dependency depth for each function
        ordered =
          function_ids
          |> Enum.map(fn func_id ->
            {:ok, callees} = CallGraph.transitive_callees(graph, func_id, max_depth: 20)
            # Count how many of our target functions this one depends on
            deps_in_set = Enum.count(callees, &(&1 in function_ids))
            {func_id, deps_in_set}
          end)
          # Refactor leaf functions first (fewer dependencies)
          |> Enum.sort_by(fn {_, deps} -> deps end)
          |> Enum.map(fn {func_id, _} -> func_id end)

        order = %{
          original: function_ids,
          suggested_order: ordered,
          reasoning:
            "Leaf functions (with fewer internal dependencies) should be refactored first to minimize ripple effects."
        }

        session = Session.add_assistant_message(session, format_order(order))

        {:ok, order, session}
    end
  end

  # Private helpers

  defp find_high_complexity_functions(graph) do
    {:ok, functions} = InMemoryGraph.nodes_by_type(graph, :function)

    functions
    |> Enum.map(fn func ->
      {:ok, callers} = InMemoryGraph.callers(graph, func.id)
      {:ok, callees} = InMemoryGraph.callees(graph, func.id)
      complexity = length(callers) * 2 + length(callees)
      Map.put(func, :complexity, complexity)
    end)
    |> Enum.filter(&(&1.complexity > 10))
    |> Enum.sort_by(& &1.complexity, :desc)
    |> Enum.take(10)
  end

  defp find_low_cohesion_modules(graph) do
    {:ok, modules} = InMemoryGraph.nodes_by_type(graph, :module)

    modules
    |> Enum.map(fn mod ->
      {:ok, stats} = CallGraph.module_call_stats(graph, mod.id)
      Map.merge(mod, %{cohesion: stats.cohesion, function_count: stats.function_count})
    end)
    |> Enum.filter(&(&1.function_count > 2 and &1.cohesion < 0.3))
    |> Enum.sort_by(& &1.cohesion)
    |> Enum.take(10)
  end

  defp find_dead_code(graph) do
    {:ok, entry_points} = CallGraph.entry_points(graph)

    # Functions with no callers that aren't entry points might be dead
    entry_points
    |> Enum.filter(fn func ->
      # Filter out things that look like callbacks or test functions
      name = func.name || ""

      not String.starts_with?(name, "test") and
        not String.contains?(func.id, "Test") and
        not String.starts_with?(name, "handle_") and
        not String.starts_with?(name, "init") and
        not String.starts_with?(name, "__")
    end)
    |> Enum.take(10)
  end

  defp find_circular_dependencies(graph) do
    {:ok, sccs} = CallGraph.strongly_connected_components(graph)
    sccs |> Enum.take(5)
  end

  defp find_god_functions(graph) do
    {:ok, hot} = CallGraph.hot_paths(graph, limit: 10)

    hot
    |> Enum.filter(&(&1.connectivity > 15))
    |> Enum.map(fn func ->
      Map.put(func, :reason, "High connectivity (#{func.connectivity}) - does too much")
    end)
  end

  defp summarize_opportunities(opportunities) do
    %{
      total_issues:
        length(opportunities.high_complexity) +
          length(opportunities.low_cohesion) +
          length(opportunities.dead_code) +
          length(opportunities.circular_deps) +
          length(opportunities.god_functions),
      priority: determine_priority(opportunities)
    }
  end

  defp determine_priority(opportunities) do
    cond do
      opportunities.circular_deps != [] -> :high
      opportunities.god_functions != [] -> :high
      length(opportunities.high_complexity) > 5 -> :medium
      length(opportunities.low_cohesion) > 3 -> :medium
      true -> :low
    end
  end

  defp generate_module_suggestions(stats, function_analyses) do
    suggestions = []

    suggestions =
      if stats.cohesion < 0.2 and stats.function_count > 3 do
        [
          "Consider splitting module - low internal cohesion (#{Float.round(stats.cohesion, 2)})"
          | suggestions
        ]
      else
        suggestions
      end

    high_complexity = Enum.filter(function_analyses, &(&1.complexity > 10))

    suggestions =
      if high_complexity == [] do
        suggestions
      else
        funcs = Enum.map_join(high_complexity, ", ", & &1.id)
        ["Consider simplifying: #{funcs}" | suggestions]
      end

    suggestions =
      if stats.external_dependencies > 10 do
        [
          "Many external dependencies (#{stats.external_dependencies}) - consider dependency injection"
          | suggestions
        ]
      else
        suggestions
      end

    suggestions
  end

  defp calculate_risk_level(affected_callers, affected_entries) do
    cond do
      length(affected_entries) > 3 -> :high
      length(affected_callers) > 10 -> :high
      length(affected_callers) > 5 -> :medium
      true -> :low
    end
  end

  defp filter_extraction_candidates(results) when is_list(results) do
    results
    |> Enum.filter(fn r -> (r[:score] || 0) > 0.5 end)
    |> Enum.take(5)
  end

  defp format_opportunities(opportunities, summary) do
    """
    ## Refactoring Opportunities

    **Total Issues:** #{summary.total_issues}
    **Priority:** #{summary.priority}

    ### High Complexity Functions (#{length(opportunities.high_complexity)})
    #{format_functions(opportunities.high_complexity)}

    ### Low Cohesion Modules (#{length(opportunities.low_cohesion)})
    #{format_modules(opportunities.low_cohesion)}

    ### Potential Dead Code (#{length(opportunities.dead_code)})
    #{format_functions(opportunities.dead_code)}

    ### Circular Dependencies (#{length(opportunities.circular_deps)})
    #{format_cycles(opportunities.circular_deps)}

    ### God Functions (#{length(opportunities.god_functions)})
    #{format_functions(opportunities.god_functions)}
    """
  end

  defp format_module_analysis(analysis) do
    """
    ## Module Analysis: #{analysis.module}

    **Functions:** #{analysis.function_count}
    **Internal Calls:** #{analysis.internal_calls}
    **External Dependencies:** #{analysis.external_dependencies}
    **Cohesion Score:** #{Float.round(analysis.cohesion, 2)}

    ### Imports
    #{Enum.join(analysis.imports, ", ")}

    ### Functions by Complexity
    #{Enum.map_join(Enum.take(analysis.functions, 5), "\n", &"- #{&1.id} (complexity: #{&1.complexity})")}

    ### Suggestions
    #{Enum.map_join(analysis.suggestions, "\n", &"- #{&1}")}
    """
  end

  defp format_impact(impact) do
    """
    ## Impact Analysis: #{impact.function}

    **Risk Level:** #{impact.risk_level}
    **Affected Callers:** #{impact.affected_count}
    **Dependencies:** #{impact.dependency_count}
    **Affected Entry Points:** #{length(impact.affected_entry_points)}

    ### Would affect:
    #{Enum.join(Enum.take(impact.affected_callers, 10), ", ")}

    ### Depends on:
    #{Enum.join(Enum.take(impact.dependencies, 10), ", ")}
    """
  end

  defp format_similar(similar) do
    """
    ## Similar Code Found

    **Matches:** #{similar.match_count}
    **Extraction Candidates:** #{length(similar.extraction_candidates)}

    ### Matches
    #{format_search_results(similar.matches)}
    """
  end

  defp format_order(order) do
    """
    ## Suggested Refactoring Order

    #{Enum.with_index(order.suggested_order, 1) |> Enum.map_join("\n", fn {f, i} -> "#{i}. #{f}" end)}

    **Reasoning:** #{order.reasoning}
    """
  end

  defp format_functions(functions) do
    functions
    |> Enum.take(5)
    |> Enum.map_join("\n", fn f ->
      complexity = f[:complexity] || f[:connectivity] || "?"
      reason = f[:reason] || "complexity: #{complexity}"
      "- #{f.id || f.name} (#{reason})"
    end)
  end

  defp format_modules(modules) do
    modules
    |> Enum.take(5)
    |> Enum.map_join("\n", fn m ->
      "- #{m.id || m.name} (cohesion: #{Float.round(m.cohesion || 0, 2)}, functions: #{m.function_count})"
    end)
  end

  defp format_cycles(cycles) do
    cycles
    |> Enum.take(3)
    |> Enum.map_join("\n", &"- #{inspect(&1)}")
  end

  defp format_search_results(results) when is_list(results) and results != [] do
    results
    |> Enum.take(5)
    |> Enum.map_join("\n", fn r ->
      path = r[:path] || "unknown"
      score = r[:score] || 0
      "- #{path} (score: #{Float.round(score, 2)})"
    end)
  end

  defp format_search_results(_), do: "No results"
end
