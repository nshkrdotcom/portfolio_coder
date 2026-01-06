defmodule PortfolioCoder.Agent.CodeAgent do
  @moduledoc """
  Code intelligence agent with tool use capabilities.

  The CodeAgent can:
  - Search code using semantic search
  - Query the code graph for relationships
  - Analyze dependencies and call chains
  - Answer questions about codebases

  ## Usage

      # Create a session with index and graph
      session = CodeAgent.new_session(index: my_index, graph: my_graph)

      # Run a task
      {:ok, result, session} = CodeAgent.run(session, "Find all functions that handle authentication")

      # Continue the conversation
      {:ok, result, session} = CodeAgent.run(session, "Show me the callers of the main auth function")

  ## Tools

  The agent has access to these tools:
  - `search_code` - Semantic code search
  - `get_callers` - Find functions that call a given function
  - `get_callees` - Find functions called by a given function
  - `get_imports` - Find module imports/dependencies
  - `graph_stats` - Get graph statistics
  - `find_path` - Find call chain between functions
  """

  alias PortfolioCoder.Agent.Session
  alias PortfolioCoder.Agent.Tool
  alias PortfolioCoder.Agent.Tools

  @tools [
    Tools.SearchCode,
    Tools.GetCallers,
    Tools.GetCallees,
    Tools.GetImports,
    Tools.GraphStats,
    Tools.FindPath
  ]

  @doc """
  Create a new agent session.

  Options:
    - `:index` - The search index to use (from InMemorySearch)
    - `:graph` - The code graph to use (from InMemoryGraph)
    - `:cwd` - Current working directory
  """
  @spec new_session(keyword()) :: Session.t()
  def new_session(opts \\ []) do
    Session.new(opts)
  end

  @doc """
  Get available tools.
  """
  @spec available_tools() :: [module()]
  def available_tools, do: @tools

  @doc """
  Get tool specs for LLM function calling.
  """
  @spec tool_specs() :: [map()]
  def tool_specs do
    Enum.map(@tools, &Tool.to_function_spec/1)
  end

  @doc """
  Run a task with the agent.

  This is a simpler interface that automatically decides which tools to use.
  Returns the result and updated session.
  """
  @spec run(Session.t(), String.t()) :: {:ok, term(), Session.t()} | {:error, term()}
  def run(session, task) do
    session = Session.add_user_message(session, task)

    # Analyze the task to decide which tools to use
    tools_to_use = analyze_task(task)

    # Execute tools and gather results
    {results, session} = execute_tools(session, tools_to_use, task)

    # Format response
    response = format_response(task, results)
    session = Session.add_assistant_message(session, response)

    {:ok, %{response: response, tool_results: results}, session}
  end

  @doc """
  Execute a specific tool.
  """
  @spec execute_tool(Session.t(), atom(), map()) ::
          {:ok, term(), Session.t()} | {:error, term(), Session.t()}
  def execute_tool(session, tool_name, params) do
    tool_module = find_tool(tool_name)

    if tool_module do
      session = Session.add_tool_call(session, tool_name, params)
      context = Session.get_tool_context(session)

      case tool_module.execute(params, context) do
        {:ok, result} ->
          session = Session.add_tool_result(session, tool_name, result)
          {:ok, result, session}

        {:error, reason} ->
          session = Session.add_tool_result(session, tool_name, {:error, reason})
          {:error, reason, session}
      end
    else
      {:error, "Unknown tool: #{tool_name}", session}
    end
  end

  @doc """
  Get a summary of available tools.
  """
  @spec tools_summary() :: String.t()
  def tools_summary do
    @tools
    |> Enum.map(fn tool ->
      "- #{tool.name()}: #{tool.description()}"
    end)
    |> Enum.join("\n")
  end

  # Private helpers

  defp analyze_task(task) do
    task_lower = String.downcase(task)

    tools =
      []
      |> maybe_add_tool(task_lower, :search_code, [
        "search",
        "find",
        "look for",
        "where is",
        "show me"
      ])
      |> maybe_add_tool(task_lower, :get_callers, ["who calls", "callers", "called by", "uses"])
      |> maybe_add_tool(task_lower, :get_callees, [
        "what does",
        "callees",
        "calls",
        "dependencies of"
      ])
      |> maybe_add_tool(task_lower, :get_imports, ["imports", "uses module", "depends on"])
      |> maybe_add_tool(task_lower, :graph_stats, ["stats", "overview", "summary", "structure"])
      |> maybe_add_tool(task_lower, :find_path, [
        "path between",
        "how does",
        "connection",
        "chain"
      ])

    # Default to search if no specific tools matched
    if tools == [], do: [:search_code], else: tools
  end

  defp maybe_add_tool(tools, task, tool_name, keywords) do
    if Enum.any?(keywords, &String.contains?(task, &1)) do
      [tool_name | tools]
    else
      tools
    end
  end

  defp execute_tools(session, tools, task) do
    Enum.reduce(tools, {[], session}, fn tool_name, {results, sess} ->
      params = extract_params(tool_name, task)

      case execute_tool(sess, tool_name, params) do
        {:ok, result, new_sess} ->
          {[{tool_name, result} | results], new_sess}

        {:error, _reason, new_sess} ->
          {results, new_sess}
      end
    end)
  end

  defp extract_params(:search_code, task) do
    # Extract the main query from the task
    %{query: extract_query(task), limit: 5}
  end

  defp extract_params(:get_callers, task) do
    %{function_id: extract_function_id(task), transitive: String.contains?(task, "all")}
  end

  defp extract_params(:get_callees, task) do
    %{function_id: extract_function_id(task), transitive: String.contains?(task, "all")}
  end

  defp extract_params(:get_imports, task) do
    direction = if String.contains?(task, "imported by"), do: "imported_by", else: "imports"
    %{module_id: extract_module_id(task), direction: direction}
  end

  defp extract_params(:graph_stats, _task) do
    %{include_hot_paths: true, include_entry_points: true}
  end

  defp extract_params(:find_path, task) do
    # Try to extract from/to from the task
    %{from: extract_function_id(task), to: extract_function_id(task), max_depth: 10}
  end

  defp extract_query(task) do
    # Remove common filler words
    task
    |> String.replace(~r/^(find|search|look for|show me|where is)\s+/i, "")
    |> String.replace(~r/\s+(in the codebase|in the code|in the project)$/i, "")
    |> String.trim()
  end

  defp extract_function_id(task) do
    # Try to find function-like patterns (Module.func/arity or func/arity)
    case Regex.run(~r/([A-Z]\w*(?:\.[A-Z]\w*)*\.\w+\/\d+|\w+\/\d+)/, task) do
      [_, match] -> match
      _ -> extract_query(task)
    end
  end

  defp extract_module_id(task) do
    # Try to find module-like patterns (Module or Module.SubModule)
    case Regex.run(~r/([A-Z]\w*(?:\.[A-Z]\w*)*)/, task) do
      [_, match] -> match
      _ -> extract_query(task)
    end
  end

  defp find_tool(tool_name) do
    Enum.find(@tools, fn t -> t.name() == tool_name end)
  end

  defp format_response(task, results) do
    if results == [] do
      "I couldn't find relevant information for: #{task}"
    else
      results
      |> Enum.map(fn {tool, result} ->
        "## #{format_tool_name(tool)}\n#{format_result(result)}"
      end)
      |> Enum.join("\n\n")
    end
  end

  defp format_tool_name(:search_code), do: "Code Search Results"
  defp format_tool_name(:get_callers), do: "Function Callers"
  defp format_tool_name(:get_callees), do: "Function Callees"
  defp format_tool_name(:get_imports), do: "Module Imports"
  defp format_tool_name(:graph_stats), do: "Graph Statistics"
  defp format_tool_name(:find_path), do: "Call Chain"
  defp format_tool_name(other), do: to_string(other)

  defp format_result(result) when is_list(result) do
    result
    |> Enum.take(10)
    |> Enum.map(&inspect/1)
    |> Enum.join("\n")
  end

  defp format_result(result) when is_map(result) do
    Jason.encode!(result, pretty: true)
  rescue
    _ -> inspect(result, pretty: true)
  end

  defp format_result(result), do: inspect(result)
end
