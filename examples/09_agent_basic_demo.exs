# examples/09_agent_basic_demo.exs
#
# Demonstrates: Basic Code Agent with Tools
# Modules Used: LLM, various portfolio_coder tools
# Prerequisites: GEMINI_API_KEY or other LLM API key
#
# Usage: mix run examples/09_agent_basic_demo.exs
#
# This demo shows a simple code agent pattern:
# 1. Parse user request
# 2. Decide which tool to use
# 3. Execute the tool
# 4. Return results with explanation

defmodule BasicAgentDemo do
  @moduledoc """
  A simple code agent that can answer questions about code by using tools.
  """

  @system_prompt """
  You are a code analysis assistant. You have access to these tools:

  1. search_code(query) - Search for code matching a query
  2. list_modules(path) - List all modules in a directory
  3. analyze_file(path) - Get detailed analysis of a file
  4. show_dependencies(module) - Show module dependencies

  When a user asks a question, decide which tool to use and respond with JSON:
  {"tool": "tool_name", "args": {"arg1": "value1"}}

  If no tool is needed (e.g., general programming question), respond with:
  {"tool": "none", "response": "your answer"}
  """

  alias PortfolioCoder.Indexer.Parser
  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.Graph.InMemoryGraph

  def run do
    print_header("Basic Code Agent Demo")

    check_api_key()

    # Initialize tools
    IO.puts("Initializing agent tools...")
    {:ok, search_index} = InMemorySearch.new()
    {:ok, graph} = InMemoryGraph.new()

    # Index the codebase
    path = Path.expand("lib/portfolio_coder")
    index_codebase(search_index, graph, path)

    tools = %{
      search_index: search_index,
      graph: graph,
      base_path: path
    }

    IO.puts("Agent ready!\n")

    # Demo interactions
    print_section("Agent Demo")

    queries = [
      "What modules exist in this codebase?",
      "Search for code related to parsing",
      "What does the InMemorySearch module depend on?"
    ]

    for query <- queries do
      IO.puts("User: #{query}")
      response = agent_respond(query, tools)
      IO.puts("Agent: #{response}")
      IO.puts("")
    end

    # Interactive mode
    print_section("Interactive Mode")
    IO.puts("Ask the agent questions (type 'quit' to exit):\n")
    interactive_loop(tools)
  end

  defp index_codebase(index, graph, path) do
    files =
      path
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.take(30)

    for file <- files do
      case Parser.parse(file) do
        {:ok, parsed} ->
          InMemoryGraph.add_from_parsed(graph, parsed, file)

          docs = [
            %{
              id: file,
              content: File.read!(file),
              metadata: %{path: file, language: parsed.language}
            }
          ]

          InMemorySearch.add_all(index, docs)

        {:error, _} ->
          :ok
      end
    end

    stats = InMemorySearch.stats(index)
    IO.puts("  Indexed #{stats.document_count} files")
  end

  defp agent_respond(query, tools) do
    # Step 1: Ask LLM to decide on tool
    decision_prompt = """
    #{@system_prompt}

    User query: #{query}

    Decide which tool to use. Respond with JSON only.
    """

    messages = [%{role: :user, content: decision_prompt}]

    case PortfolioIndex.Adapters.LLM.Gemini.complete(messages, max_tokens: 200) do
      {:ok, %{content: response}} ->
        case parse_tool_decision(response) do
          {:tool, "none", direct_response} ->
            direct_response

          {:tool, tool_name, args} ->
            result = execute_tool(tool_name, args, tools)
            format_result(query, tool_name, result)

          :error ->
            "I couldn't understand how to help with that. Could you rephrase?"
        end

      {:error, _reason} ->
        "Sorry, I encountered an error processing your request."
    end
  end

  defp parse_tool_decision(response) do
    # Extract JSON from response
    case Regex.run(~r/\{[^}]+\}/, response) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, %{"tool" => "none", "response" => resp}} ->
            {:tool, "none", resp}

          {:ok, %{"tool" => tool, "args" => args}} ->
            {:tool, tool, args}

          {:ok, %{"tool" => tool}} ->
            {:tool, tool, %{}}

          _ ->
            :error
        end

      nil ->
        :error
    end
  end

  defp execute_tool("search_code", args, tools) do
    query = args["query"] || args["q"] || ""
    {:ok, results} = InMemorySearch.search(tools.search_index, query, limit: 5)

    results
    |> Enum.map(fn r ->
      "#{Path.basename(r.metadata[:path])}: #{String.slice(r.content, 0, 100)}..."
    end)
    |> Enum.join("\n")
  end

  defp execute_tool("list_modules", _args, tools) do
    {:ok, modules} = InMemoryGraph.nodes_by_type(tools.graph, :module)

    modules
    |> Enum.map(& &1.name)
    |> Enum.sort()
    |> Enum.join("\n")
  end

  defp execute_tool("analyze_file", args, _tools) do
    path = args["path"] || args["file"] || ""

    if File.exists?(path) do
      case Parser.parse(path) do
        {:ok, parsed} ->
          functions = length(Enum.filter(parsed.symbols, &(&1.type == :function)))
          modules = length(Enum.filter(parsed.symbols, &(&1.type == :module)))

          "File: #{path}\nLanguage: #{parsed.language}\nModules: #{modules}\nFunctions: #{functions}"

        {:error, reason} ->
          "Error analyzing file: #{inspect(reason)}"
      end
    else
      "File not found: #{path}"
    end
  end

  defp execute_tool("show_dependencies", args, tools) do
    module = args["module"] || args["name"] || ""

    {:ok, imports} = InMemoryGraph.imports_of(tools.graph, module)

    if Enum.empty?(imports) do
      "Module '#{module}' has no tracked dependencies (or was not found)"
    else
      "Dependencies of #{module}:\n" <> Enum.join(imports, "\n")
    end
  end

  defp execute_tool(unknown, _args, _tools) do
    "Unknown tool: #{unknown}"
  end

  defp format_result(query, tool_name, result) do
    # Generate a natural language response with the results
    summary_prompt = """
    The user asked: "#{query}"

    I used the #{tool_name} tool and got these results:
    #{result}

    Provide a brief, helpful summary of the results in 1-3 sentences.
    """

    messages = [%{role: :user, content: summary_prompt}]

    case PortfolioIndex.Adapters.LLM.Gemini.complete(messages, max_tokens: 200) do
      {:ok, %{content: summary}} ->
        String.trim(summary)

      {:error, _} ->
        "Results:\n#{result}"
    end
  end

  defp interactive_loop(tools) do
    case IO.gets("> ") do
      :eof ->
        IO.puts("\nGoodbye!")

      {:error, _} ->
        IO.puts("\nGoodbye!")

      input ->
        query = String.trim(input)

        cond do
          query in ["quit", "exit", "q"] ->
            IO.puts("Goodbye!")

          query == "" ->
            interactive_loop(tools)

          true ->
            response = agent_respond(query, tools)
            IO.puts("\n#{response}\n")
            interactive_loop(tools)
        end
    end
  end

  defp check_api_key do
    if System.get_env("GEMINI_API_KEY") do
      IO.puts("Using Gemini API\n")
    else
      IO.puts(:stderr, "Warning: GEMINI_API_KEY not set\n")
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

BasicAgentDemo.run()
