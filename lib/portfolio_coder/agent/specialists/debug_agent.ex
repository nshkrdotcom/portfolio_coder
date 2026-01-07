defmodule PortfolioCoder.Agent.Specialists.DebugAgent do
  @moduledoc """
  Specialized agent for debugging code issues.

  The DebugAgent helps analyze errors, trace code paths, and suggest fixes.
  It uses a targeted tool selection focused on understanding code flow and
  finding related code that might be causing issues.

  ## Features

  - Error message analysis
  - Stack trace parsing
  - Code path tracing
  - Related code discovery
  - Fix suggestions

  ## Usage

      session = DebugAgent.new_session(index: index, graph: graph)
      {:ok, analysis, session} = DebugAgent.analyze_error(session, error_message)
      {:ok, trace, session} = DebugAgent.trace_code_path(session, "MyModule.failing_func/1")
  """

  alias PortfolioCoder.Agent.CodeAgent
  alias PortfolioCoder.Agent.Session
  alias PortfolioCoder.Graph.CallGraph
  alias PortfolioCoder.Graph.InMemoryGraph

  @doc """
  Create a new debug session with specialized context.
  """
  @spec new_session(keyword()) :: Session.t()
  def new_session(opts \\ []) do
    session = Session.new(opts)
    Session.update_context(session, :agent_type, :debug)
  end

  @doc """
  Analyze an error message and find potentially related code.

  Returns analysis with:
  - Parsed error information
  - Related code snippets
  - Potential causes
  - Suggested investigation paths
  """
  @spec analyze_error(Session.t(), String.t()) :: {:ok, map(), Session.t()}
  def analyze_error(session, error_message) do
    session = Session.add_user_message(session, "Debug: #{error_message}")

    # Parse error to extract useful information
    error_info = parse_error(error_message)

    # Search for related code
    search_results = search_related_code(session, error_info)

    # Build analysis
    analysis = %{
      error_type: error_info.type,
      module: error_info.module,
      function: error_info.function,
      message: error_info.message,
      related_code: search_results,
      suggestions: generate_suggestions(error_info, search_results)
    }

    session = Session.add_assistant_message(session, format_analysis(analysis))

    {:ok, analysis, session}
  end

  @doc """
  Trace the code path to/from a function.

  Shows:
  - What calls this function (callers)
  - What this function calls (callees)
  - Full transitive call chain if requested
  """
  @spec trace_code_path(Session.t(), String.t(), keyword()) :: {:ok, map(), Session.t()}
  def trace_code_path(session, function_id, opts \\ []) do
    include_transitive = Keyword.get(opts, :transitive, false)
    max_depth = Keyword.get(opts, :max_depth, 5)

    session = Session.add_user_message(session, "Trace: #{function_id}")

    case session.context[:graph] do
      nil ->
        {:ok, %{error: "No graph available"}, session}

      graph ->
        # Get callers and callees
        callers_result =
          if include_transitive do
            CallGraph.transitive_callers(graph, function_id, max_depth: max_depth)
          else
            InMemoryGraph.callers(graph, function_id)
          end

        callees_result =
          if include_transitive do
            CallGraph.transitive_callees(graph, function_id, max_depth: max_depth)
          else
            InMemoryGraph.callees(graph, function_id)
          end

        {:ok, callers} = callers_result
        {:ok, callees} = callees_result

        # Check for cycles
        {:ok, cycles} = CallGraph.find_cycles(graph, max_cycles: 5)
        involved_in_cycle = Enum.any?(cycles, &(function_id in &1))

        trace = %{
          function: function_id,
          callers: callers,
          callees: callees,
          caller_count: length(callers),
          callee_count: length(callees),
          transitive: include_transitive,
          involved_in_cycle: involved_in_cycle,
          cycles: if(involved_in_cycle, do: Enum.filter(cycles, &(function_id in &1)), else: [])
        }

        session = Session.add_assistant_message(session, format_trace(trace))

        {:ok, trace, session}
    end
  end

  @doc """
  Find functions that might be related to a bug based on keywords.
  """
  @spec find_suspicious_code(Session.t(), String.t()) :: {:ok, map(), Session.t()}
  def find_suspicious_code(session, description) do
    session = Session.add_user_message(session, "Find suspicious: #{description}")

    # Search for potentially problematic code
    {:ok, search_result, session} =
      CodeAgent.execute_tool(session, :search_code, %{
        query: description,
        limit: 10
      })

    # If we have a graph, find highly connected functions (potential bug magnets)
    hot_paths =
      case session.context[:graph] do
        nil ->
          []

        graph ->
          {:ok, hot} = CallGraph.hot_paths(graph, limit: 5)
          hot
      end

    result = %{
      search_matches: search_result,
      highly_connected:
        Enum.map(hot_paths, fn h ->
          %{id: h.id, name: h.name, connectivity: h.connectivity}
        end),
      investigation_order: prioritize_investigation(search_result, hot_paths)
    }

    session = Session.add_assistant_message(session, format_suspicious(result))

    {:ok, result, session}
  end

  @doc """
  Analyze a specific function for potential issues.
  """
  @spec analyze_function(Session.t(), String.t()) :: {:ok, map(), Session.t()}
  def analyze_function(session, function_id) do
    session = Session.add_user_message(session, "Analyze function: #{function_id}")

    case session.context[:graph] do
      nil ->
        {:ok, %{error: "No graph available"}, session}

      graph ->
        # Get function details
        {:ok, callers} = InMemoryGraph.callers(graph, function_id)
        {:ok, callees} = InMemoryGraph.callees(graph, function_id)

        # Calculate complexity indicators
        depth =
          case CallGraph.call_depth(graph, function_id) do
            {:ok, d} -> d
            {:error, :cycle_detected} -> :cycle
          end

        # Check if it's an entry point or leaf
        is_entry = callers == []
        is_leaf = callees == []

        analysis = %{
          function: function_id,
          callers: callers,
          callees: callees,
          call_depth: depth,
          is_entry_point: is_entry,
          is_leaf: is_leaf,
          complexity_score: calculate_complexity(callers, callees, depth),
          warnings: generate_warnings(callers, callees, depth)
        }

        session = Session.add_assistant_message(session, format_function_analysis(analysis))

        {:ok, analysis, session}
    end
  end

  # Private helpers

  defp parse_error(message) do
    # Try to extract module/function from error
    module = extract_module_from_error(message)
    function = extract_function_from_error(message)
    type = classify_error_type(message)

    %{
      type: type,
      module: module,
      function: function,
      message: message,
      keywords: extract_keywords(message)
    }
  end

  defp extract_module_from_error(message) do
    case Regex.run(~r/([A-Z]\w*(?:\.[A-Z]\w*)*)/, message) do
      [_, module] -> module
      _ -> nil
    end
  end

  defp extract_function_from_error(message) do
    case Regex.run(~r/(\w+\/\d+|:\w+)/, message) do
      [_, func] -> func
      _ -> nil
    end
  end

  defp classify_error_type(message) do
    message_lower = String.downcase(message)

    Enum.find_value(error_matchers(), :unknown, fn {type, matcher} ->
      if matcher.(message_lower), do: type, else: nil
    end)
  end

  defp error_matchers do
    [
      {:undefined_error, &String.contains?(&1, "undefined")},
      {:argument_error, &String.contains?(&1, "argument error")},
      {:function_clause_error, &String.contains?(&1, "function clause")},
      {:match_error, &match_error_message?/1},
      {:key_error, &String.contains?(&1, "key")},
      {:timeout_error, &String.contains?(&1, "timeout")},
      {:nil_error, &String.contains?(&1, "nil")}
    ]
  end

  defp match_error_message?(message) do
    String.contains?(message, "matcherror") or
      (String.contains?(message, "match") and not String.contains?(message, "clause"))
  end

  defp extract_keywords(message) do
    message
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split()
    |> Enum.reject(&(String.length(&1) < 3))
    |> Enum.uniq()
    |> Enum.take(10)
  end

  defp search_related_code(session, error_info) do
    query = build_search_query(error_info)

    case CodeAgent.execute_tool(session, :search_code, %{query: query, limit: 5}) do
      {:ok, results, _} -> results
      _ -> []
    end
  end

  defp build_search_query(error_info) do
    parts = [error_info.module, error_info.function | error_info.keywords]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.take(5)
    |> Enum.join(" ")
  end

  defp generate_suggestions(error_info, search_results) do
    suggestions = []

    suggestions =
      case error_info.type do
        :undefined_error ->
          ["Check if the module/function exists", "Verify imports and aliases" | suggestions]

        :argument_error ->
          ["Check function argument types", "Verify data structures" | suggestions]

        :match_error ->
          ["Check pattern matching clauses", "Verify expected data format" | suggestions]

        :nil_error ->
          ["Add nil checks", "Trace where nil is introduced" | suggestions]

        _ ->
          suggestions
      end

    if search_results == [] do
      suggestions
    else
      ["Review related code in search results" | suggestions]
    end
  end

  defp prioritize_investigation(search_results, hot_paths) when is_list(search_results) do
    # Prioritize hot paths that also appear in search results
    hot_ids = MapSet.new(Enum.map(hot_paths, & &1.id))

    search_results
    |> Enum.sort_by(fn result ->
      path = result[:path] || ""
      is_hot = Enum.any?(hot_ids, &String.contains?(path, &1))
      score = result[:score] || 0
      {not is_hot, -score}
    end)
    |> Enum.take(5)
  end

  defp prioritize_investigation(_, _), do: []

  defp calculate_complexity(callers, callees, depth) do
    caller_weight = length(callers) * 2
    callee_weight = length(callees)
    depth_weight = depth_to_weight(depth)

    caller_weight + callee_weight + depth_weight
  end

  defp depth_to_weight(:cycle), do: 10
  defp depth_to_weight(d) when is_integer(d), do: d

  defp generate_warnings(callers, callees, depth) do
    warnings = []

    warnings =
      if length(callers) > 10 do
        ["High fan-in: #{length(callers)} callers - changes may have wide impact" | warnings]
      else
        warnings
      end

    warnings =
      if length(callees) > 10 do
        ["High fan-out: #{length(callees)} callees - function may be doing too much" | warnings]
      else
        warnings
      end

    add_cycle_warning(warnings, depth)
  end

  defp add_cycle_warning(warnings, :cycle) do
    ["Involved in recursive cycle - potential infinite loop risk" | warnings]
  end

  defp add_cycle_warning(warnings, _), do: warnings

  defp format_analysis(analysis) do
    """
    ## Error Analysis

    **Type:** #{analysis.error_type}
    **Module:** #{analysis.module || "Unknown"}
    **Function:** #{analysis.function || "Unknown"}

    ### Related Code
    #{format_search_results(analysis.related_code)}

    ### Suggestions
    #{Enum.map_join(analysis.suggestions, "\n", &"- #{&1}")}
    """
  end

  defp format_trace(trace) do
    """
    ## Code Path Trace: #{trace.function}

    **Callers (#{trace.caller_count}):** #{Enum.join(trace.callers, ", ")}
    **Callees (#{trace.callee_count}):** #{Enum.join(trace.callees, ", ")}
    **Transitive:** #{trace.transitive}
    **In Cycle:** #{trace.involved_in_cycle}
    #{if trace.involved_in_cycle, do: "\n**Cycles:** #{inspect(trace.cycles)}", else: ""}
    """
  end

  defp format_suspicious(result) do
    """
    ## Suspicious Code Analysis

    ### Search Matches
    #{format_search_results(result.search_matches)}

    ### Highly Connected Functions
    #{Enum.map_join(result.highly_connected, "\n", &"- #{&1.id} (connectivity: #{&1.connectivity})")}

    ### Investigation Priority
    #{format_search_results(result.investigation_order)}
    """
  end

  defp format_function_analysis(analysis) do
    """
    ## Function Analysis: #{analysis.function}

    **Call Depth:** #{analysis.call_depth}
    **Entry Point:** #{analysis.is_entry_point}
    **Leaf Function:** #{analysis.is_leaf}
    **Complexity Score:** #{analysis.complexity_score}

    **Callers:** #{Enum.join(analysis.callers, ", ")}
    **Callees:** #{Enum.join(analysis.callees, ", ")}

    ### Warnings
    #{Enum.map_join(analysis.warnings, "\n", &"- #{&1}")}
    """
  end

  defp format_search_results(results) when is_list(results) do
    results
    |> Enum.take(5)
    |> Enum.map_join("\n", fn r ->
      path = r[:path] || "unknown"
      name = r[:name] || Path.basename(path)
      "- #{name} (#{path})"
    end)
  end

  defp format_search_results(_), do: "No results"
end
