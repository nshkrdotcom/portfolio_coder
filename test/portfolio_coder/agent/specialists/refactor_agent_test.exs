defmodule PortfolioCoder.Agent.Specialists.RefactorAgentTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Agent.Specialists.RefactorAgent
  alias PortfolioCoder.Agent.Session
  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.Graph.InMemoryGraph

  describe "new_session/1" do
    test "creates session with refactor agent type" do
      session = RefactorAgent.new_session()

      assert %Session{} = session
      assert session.context.agent_type == :refactor
    end
  end

  describe "find_opportunities/1" do
    test "finds refactoring opportunities" do
      {:ok, graph} = setup_complex_graph()
      session = RefactorAgent.new_session(graph: graph)

      {:ok, opportunities, _session} = RefactorAgent.find_opportunities(session)

      assert Map.has_key?(opportunities, :high_complexity)
      assert Map.has_key?(opportunities, :low_cohesion)
      assert Map.has_key?(opportunities, :dead_code)
      assert Map.has_key?(opportunities, :circular_deps)
      assert Map.has_key?(opportunities, :god_functions)
      assert Map.has_key?(opportunities, :summary)
    end

    test "returns error when no graph" do
      session = RefactorAgent.new_session()

      {:ok, result, _session} = RefactorAgent.find_opportunities(session)

      assert result.error == "No graph available"
    end
  end

  describe "analyze_module/2" do
    test "analyzes module structure" do
      {:ok, graph} = setup_module_graph()
      session = RefactorAgent.new_session(graph: graph)

      {:ok, analysis, _session} = RefactorAgent.analyze_module(session, "TestModule")

      assert analysis.module == "TestModule"
      assert analysis.function_count == 3
      assert is_list(analysis.imports)
      assert is_list(analysis.functions)
      assert is_list(analysis.suggestions)
    end

    test "calculates cohesion" do
      {:ok, graph} = setup_module_graph()
      session = RefactorAgent.new_session(graph: graph)

      {:ok, analysis, _session} = RefactorAgent.analyze_module(session, "TestModule")

      assert is_float(analysis.cohesion)
    end
  end

  describe "analyze_impact/2" do
    test "analyzes impact of changing a function" do
      {:ok, graph} = setup_call_graph()
      session = RefactorAgent.new_session(graph: graph)

      {:ok, impact, _session} = RefactorAgent.analyze_impact(session, "B.func/0")

      assert impact.function == "B.func/0"
      assert is_list(impact.affected_callers)
      assert is_list(impact.dependencies)
      assert impact.risk_level in [:low, :medium, :high]
    end

    test "identifies affected entry points" do
      {:ok, graph} = setup_call_graph()
      session = RefactorAgent.new_session(graph: graph)

      {:ok, impact, _session} = RefactorAgent.analyze_impact(session, "C.func/0")

      # A is an entry point and transitively calls C through B
      assert is_list(impact.affected_entry_points)
    end
  end

  describe "find_similar_code/2" do
    test "finds similar code patterns" do
      {:ok, index} = InMemorySearch.new()

      InMemorySearch.add(index, %{
        id: "file1:1",
        content: "def process_data(data), do: validate(data) |> transform()",
        metadata: %{path: "lib/processor1.ex", language: :elixir}
      })

      InMemorySearch.add(index, %{
        id: "file2:1",
        content: "def handle_data(data), do: validate(data) |> convert()",
        metadata: %{path: "lib/processor2.ex", language: :elixir}
      })

      session = RefactorAgent.new_session(index: index)

      {:ok, result, _session} =
        RefactorAgent.find_similar_code(session, "validate data transform")

      assert is_list(result.matches)
      assert result.match_count >= 0
    end
  end

  describe "suggest_refactoring_order/2" do
    test "suggests order based on dependencies" do
      {:ok, graph} = setup_call_graph()
      session = RefactorAgent.new_session(graph: graph)

      functions = ["A.func/0", "B.func/0", "C.func/0"]
      {:ok, order, _session} = RefactorAgent.suggest_refactoring_order(session, functions)

      assert order.original == functions
      assert is_list(order.suggested_order)
      assert length(order.suggested_order) == 3
      # C should come first as it has no dependencies in the set
      assert hd(order.suggested_order) == "C.func/0"
    end

    test "returns error when no graph" do
      session = RefactorAgent.new_session()

      {:ok, result, _session} = RefactorAgent.suggest_refactoring_order(session, ["A.func/0"])

      assert result.error == "No graph available"
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

  defp setup_module_graph do
    {:ok, graph} = InMemoryGraph.new()

    # Module with 3 functions
    InMemoryGraph.add_node(graph, %{
      id: "TestModule",
      type: :module,
      name: "TestModule",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "TestModule.func1/0",
      type: :function,
      name: "func1",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "TestModule.func2/0",
      type: :function,
      name: "func2",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "TestModule.func3/0",
      type: :function,
      name: "func3",
      metadata: %{}
    })

    # External module
    InMemoryGraph.add_node(graph, %{
      id: "External",
      type: :external,
      name: "External",
      metadata: %{}
    })

    # Module defines functions
    InMemoryGraph.add_edge(graph, %{
      source: "TestModule",
      target: "TestModule.func1/0",
      type: :defines,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "TestModule",
      target: "TestModule.func2/0",
      type: :defines,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "TestModule",
      target: "TestModule.func3/0",
      type: :defines,
      metadata: %{}
    })

    # Internal calls
    InMemoryGraph.add_edge(graph, %{
      source: "TestModule.func1/0",
      target: "TestModule.func2/0",
      type: :calls,
      metadata: %{}
    })

    # Module imports
    InMemoryGraph.add_edge(graph, %{
      source: "TestModule",
      target: "External",
      type: :imports,
      metadata: %{}
    })

    {:ok, graph}
  end

  defp setup_complex_graph do
    {:ok, graph} = InMemoryGraph.new()

    # Create several modules and functions
    for i <- 1..5 do
      mod_id = "Module#{i}"
      InMemoryGraph.add_node(graph, %{id: mod_id, type: :module, name: mod_id, metadata: %{}})

      for j <- 1..3 do
        func_id = "#{mod_id}.func#{j}/0"

        InMemoryGraph.add_node(graph, %{
          id: func_id,
          type: :function,
          name: "func#{j}",
          metadata: %{}
        })

        InMemoryGraph.add_edge(graph, %{
          source: mod_id,
          target: func_id,
          type: :defines,
          metadata: %{}
        })
      end
    end

    # Add some cross-module calls
    InMemoryGraph.add_edge(graph, %{
      source: "Module1.func1/0",
      target: "Module2.func1/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "Module2.func1/0",
      target: "Module3.func1/0",
      type: :calls,
      metadata: %{}
    })

    {:ok, graph}
  end
end
