defmodule PortfolioCoder.Agent.CodeAgentTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Agent.CodeAgent
  alias PortfolioCoder.Agent.Session
  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.Graph.InMemoryGraph

  describe "new_session/1" do
    test "creates a session with provided context" do
      {:ok, index} = InMemorySearch.new()
      {:ok, graph} = InMemoryGraph.new()

      session = CodeAgent.new_session(index: index, graph: graph)

      assert %Session{} = session
      assert session.context.index == index
      assert session.context.graph == graph
    end
  end

  describe "available_tools/0" do
    test "returns list of tool modules" do
      tools = CodeAgent.available_tools()

      assert is_list(tools)
      assert length(tools) >= 5
      assert PortfolioCoder.Agent.Tools.SearchCode in tools
    end
  end

  describe "tool_specs/0" do
    test "returns tool specifications for LLM" do
      specs = CodeAgent.tool_specs()

      assert is_list(specs)

      search_spec = Enum.find(specs, &(&1.name == :search_code))
      assert search_spec != nil
      assert search_spec.description != nil
      assert search_spec.parameters.type == "object"
    end
  end

  describe "tools_summary/0" do
    test "returns human-readable tool summary" do
      summary = CodeAgent.tools_summary()

      assert is_binary(summary)
      assert String.contains?(summary, "search_code")
      assert String.contains?(summary, "get_callers")
    end
  end

  describe "execute_tool/3" do
    test "executes search_code tool with index" do
      {:ok, index} = InMemorySearch.new()

      # Add a document to search
      InMemorySearch.add(index, %{
        id: "test:1",
        content: "defmodule Auth do def login(user), do: :ok end",
        metadata: %{path: "lib/auth.ex", language: :elixir}
      })

      session = CodeAgent.new_session(index: index)

      {:ok, result, _session} =
        CodeAgent.execute_tool(session, :search_code, %{query: "login", limit: 5})

      assert is_list(result)
    end

    test "returns error when index not available" do
      session = CodeAgent.new_session()

      {:error, reason, _session} =
        CodeAgent.execute_tool(session, :search_code, %{query: "test"})

      assert String.contains?(reason, "No index available")
    end

    test "executes graph_stats tool with graph" do
      {:ok, graph} = InMemoryGraph.new()

      InMemoryGraph.add_node(graph, %{
        id: "TestModule",
        type: :module,
        name: "TestModule",
        metadata: %{}
      })

      session = CodeAgent.new_session(graph: graph)

      {:ok, result, _session} =
        CodeAgent.execute_tool(session, :graph_stats, %{})

      assert is_map(result)
      assert Map.has_key?(result, :node_count)
    end

    test "returns error for unknown tool" do
      session = CodeAgent.new_session()

      {:error, reason, _session} =
        CodeAgent.execute_tool(session, :unknown_tool, %{})

      assert String.contains?(reason, "Unknown tool")
    end
  end

  describe "run/2" do
    test "runs a search task" do
      {:ok, index} = InMemorySearch.new()

      InMemorySearch.add(index, %{
        id: "test:1",
        content: "defmodule Auth do def authenticate(user, password), do: :ok end",
        metadata: %{path: "lib/auth.ex", language: :elixir, name: "authenticate"}
      })

      session = CodeAgent.new_session(index: index)

      {:ok, result, session} = CodeAgent.run(session, "Search for authentication code")

      assert is_map(result)
      assert Map.has_key?(result, :response)
      assert length(session.messages) >= 2
    end

    test "runs a graph stats task" do
      {:ok, graph} = InMemoryGraph.new()

      InMemoryGraph.add_node(graph, %{
        id: "TestModule",
        type: :module,
        name: "TestModule",
        metadata: %{}
      })

      session = CodeAgent.new_session(graph: graph)

      {:ok, result, _session} = CodeAgent.run(session, "Show me the stats and overview")

      assert is_map(result)
      assert Map.has_key?(result, :response)
    end

    test "maintains conversation history" do
      {:ok, index} = InMemorySearch.new()
      session = CodeAgent.new_session(index: index)

      {:ok, _, session} = CodeAgent.run(session, "First question")
      {:ok, _, session} = CodeAgent.run(session, "Second question")

      # Should have user + assistant messages for each run
      assert length(session.messages) >= 4
    end
  end
end
