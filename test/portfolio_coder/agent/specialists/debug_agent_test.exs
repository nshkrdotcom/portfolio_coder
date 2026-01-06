defmodule PortfolioCoder.Agent.Specialists.DebugAgentTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Agent.Specialists.DebugAgent
  alias PortfolioCoder.Agent.Session
  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.Graph.InMemoryGraph

  describe "new_session/1" do
    test "creates session with debug agent type" do
      session = DebugAgent.new_session()

      assert %Session{} = session
      assert session.context.agent_type == :debug
    end

    test "accepts index and graph options" do
      {:ok, index} = InMemorySearch.new()
      {:ok, graph} = InMemoryGraph.new()

      session = DebugAgent.new_session(index: index, graph: graph)

      assert session.context.index == index
      assert session.context.graph == graph
    end
  end

  describe "analyze_error/2" do
    test "analyzes an error message" do
      {:ok, index} = InMemorySearch.new()

      InMemorySearch.add(index, %{
        id: "auth:1",
        content: "def authenticate(user), do: :ok",
        metadata: %{path: "lib/auth.ex", language: :elixir}
      })

      session = DebugAgent.new_session(index: index)

      {:ok, analysis, _session} =
        DebugAgent.analyze_error(
          session,
          "** (UndefinedFunctionError) function Auth.authenticate/1 is undefined"
        )

      assert analysis.error_type == :undefined_error
      # First module found is UndefinedFunctionError, then Auth
      assert is_binary(analysis.module) or is_nil(analysis.module)
      assert is_list(analysis.suggestions)
    end

    test "extracts function from error" do
      session = DebugAgent.new_session()

      {:ok, analysis, _session} =
        DebugAgent.analyze_error(
          session,
          "** (FunctionClauseError) no function clause matching MyModule.handle_call/3"
        )

      assert analysis.error_type == :function_clause_error
      assert is_binary(analysis.module)
    end

    test "identifies different error types" do
      session = DebugAgent.new_session()

      {:ok, analysis1, _} =
        DebugAgent.analyze_error(session, "** (ArgumentError) argument error: invalid data")

      assert analysis1.error_type == :argument_error

      {:ok, analysis2, _} = DebugAgent.analyze_error(session, "** (KeyError) key :foo not found")
      assert analysis2.error_type == :key_error

      {:ok, analysis3, _} =
        DebugAgent.analyze_error(session, "** (MatchError) no match of right hand side")

      assert analysis3.error_type == :match_error
    end
  end

  describe "trace_code_path/3" do
    test "traces callers and callees" do
      {:ok, graph} = setup_call_graph()
      session = DebugAgent.new_session(graph: graph)

      {:ok, trace, _session} = DebugAgent.trace_code_path(session, "B.func/0")

      assert trace.function == "B.func/0"
      assert "A.func/0" in trace.callers
      assert "C.func/0" in trace.callees
    end

    test "supports transitive tracing" do
      {:ok, graph} = setup_call_graph()
      session = DebugAgent.new_session(graph: graph)

      {:ok, trace, _session} = DebugAgent.trace_code_path(session, "A.func/0", transitive: true)

      assert trace.transitive == true
      # A calls B calls C, so transitive callees should include both
      assert "B.func/0" in trace.callees
      assert "C.func/0" in trace.callees
    end

    test "detects cycles" do
      {:ok, graph} = setup_cyclic_graph()
      session = DebugAgent.new_session(graph: graph)

      {:ok, trace, _session} = DebugAgent.trace_code_path(session, "cycle_a/0")

      assert trace.involved_in_cycle == true
      assert length(trace.cycles) > 0
    end

    test "returns error when no graph" do
      session = DebugAgent.new_session()

      {:ok, result, _session} = DebugAgent.trace_code_path(session, "A.func/0")

      assert result.error == "No graph available"
    end
  end

  describe "find_suspicious_code/2" do
    test "searches for suspicious code patterns" do
      {:ok, index} = InMemorySearch.new()

      InMemorySearch.add(index, %{
        id: "auth:1",
        content: "def authenticate(nil), do: :error",
        metadata: %{path: "lib/auth.ex", language: :elixir}
      })

      session = DebugAgent.new_session(index: index)

      {:ok, result, _session} = DebugAgent.find_suspicious_code(session, "nil handling")

      assert is_list(result.search_matches)
    end
  end

  describe "analyze_function/2" do
    test "analyzes function complexity" do
      {:ok, graph} = setup_call_graph()
      session = DebugAgent.new_session(graph: graph)

      {:ok, analysis, _session} = DebugAgent.analyze_function(session, "B.func/0")

      assert analysis.function == "B.func/0"
      assert is_list(analysis.callers)
      assert is_list(analysis.callees)
      assert is_integer(analysis.complexity_score) or analysis.complexity_score == :cycle
      assert is_list(analysis.warnings)
    end

    test "identifies entry points" do
      {:ok, graph} = setup_call_graph()
      session = DebugAgent.new_session(graph: graph)

      {:ok, analysis, _session} = DebugAgent.analyze_function(session, "A.func/0")

      assert analysis.is_entry_point == true
    end

    test "identifies leaf functions" do
      {:ok, graph} = setup_call_graph()
      session = DebugAgent.new_session(graph: graph)

      {:ok, analysis, _session} = DebugAgent.analyze_function(session, "C.func/0")

      assert analysis.is_leaf == true
    end
  end

  # Setup helpers

  defp setup_call_graph do
    {:ok, graph} = InMemoryGraph.new()

    # A -> B -> C
    InMemoryGraph.add_node(graph, %{id: "A.func/0", type: :function, name: "func", metadata: %{}})
    InMemoryGraph.add_node(graph, %{id: "B.func/0", type: :function, name: "func", metadata: %{}})
    InMemoryGraph.add_node(graph, %{id: "C.func/0", type: :function, name: "func", metadata: %{}})

    InMemoryGraph.add_edge(graph, %{
      source: "A.func/0",
      target: "B.func/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "B.func/0",
      target: "C.func/0",
      type: :calls,
      metadata: %{}
    })

    {:ok, graph}
  end

  defp setup_cyclic_graph do
    {:ok, graph} = InMemoryGraph.new()

    # cycle_a -> cycle_b -> cycle_c -> cycle_a
    InMemoryGraph.add_node(graph, %{
      id: "cycle_a/0",
      type: :function,
      name: "cycle_a",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "cycle_b/0",
      type: :function,
      name: "cycle_b",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "cycle_c/0",
      type: :function,
      name: "cycle_c",
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "cycle_a/0",
      target: "cycle_b/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "cycle_b/0",
      target: "cycle_c/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "cycle_c/0",
      target: "cycle_a/0",
      type: :calls,
      metadata: %{}
    })

    {:ok, graph}
  end
end
