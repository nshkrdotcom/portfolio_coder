defmodule PortfolioCoder.Graph.CallGraphTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Graph.CallGraph
  alias PortfolioCoder.Graph.InMemoryGraph

  describe "transitive_callees/3" do
    test "returns empty list for function with no callees" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, callees} = CallGraph.transitive_callees(graph, "func_c/0")
      assert callees == []
    end

    test "returns direct callees" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, callees} = CallGraph.transitive_callees(graph, "func_b/0")
      assert "func_c/0" in callees
    end

    test "returns transitive callees" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, callees} = CallGraph.transitive_callees(graph, "func_a/0")
      assert "func_b/0" in callees
      assert "func_c/0" in callees
    end

    test "handles branching call graph" do
      {:ok, graph} = setup_branching_call_graph()

      {:ok, callees} = CallGraph.transitive_callees(graph, "root/0")
      assert length(callees) >= 4
      assert "branch_a/0" in callees
      assert "branch_b/0" in callees
      assert "leaf_a/0" in callees
      assert "leaf_b/0" in callees
    end

    test "respects max_depth option" do
      {:ok, graph} = setup_linear_call_graph()

      # max_depth: 1 means traverse 1 level, which includes direct callees and their direct callees
      {:ok, callees} = CallGraph.transitive_callees(graph, "func_a/0", max_depth: 1)
      assert "func_b/0" in callees
      assert "func_c/0" in callees

      # max_depth: 0 means only get immediate direct callees (no traversal)
      {:ok, callees_0} = CallGraph.transitive_callees(graph, "func_a/0", max_depth: 0)
      assert "func_b/0" in callees_0
      # func_c should not be included since we don't traverse into func_b
      refute "func_c/0" in callees_0
    end
  end

  describe "transitive_callers/3" do
    test "returns empty list for function with no callers" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, callers} = CallGraph.transitive_callers(graph, "func_a/0")
      assert callers == []
    end

    test "returns transitive callers" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, callers} = CallGraph.transitive_callers(graph, "func_c/0")
      assert "func_b/0" in callers
      assert "func_a/0" in callers
    end
  end

  describe "find_cycles/2" do
    test "returns empty list when no cycles exist" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, cycles} = CallGraph.find_cycles(graph)
      assert cycles == []
    end

    test "detects simple cycle" do
      {:ok, graph} = setup_cyclic_call_graph()

      {:ok, cycles} = CallGraph.find_cycles(graph)
      assert length(cycles) > 0

      # Should find the cycle a -> b -> c -> a
      cycle_nodes = List.first(cycles) |> MapSet.new()
      assert MapSet.member?(cycle_nodes, "cycle_a/0")
      assert MapSet.member?(cycle_nodes, "cycle_b/0")
      assert MapSet.member?(cycle_nodes, "cycle_c/0")
    end

    test "respects max_cycles option" do
      {:ok, graph} = setup_multiple_cycles_graph()

      {:ok, cycles} = CallGraph.find_cycles(graph, max_cycles: 1)
      assert length(cycles) <= 1
    end
  end

  describe "entry_points/1" do
    test "finds functions with no callers" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, entries} = CallGraph.entry_points(graph)
      entry_ids = Enum.map(entries, & &1.id)

      assert "func_a/0" in entry_ids
      refute "func_b/0" in entry_ids
      refute "func_c/0" in entry_ids
    end

    test "returns multiple entry points" do
      {:ok, graph} = setup_branching_call_graph()

      {:ok, entries} = CallGraph.entry_points(graph)
      entry_ids = Enum.map(entries, & &1.id)

      assert "root/0" in entry_ids
    end
  end

  describe "leaf_functions/1" do
    test "finds functions with no callees" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, leaves} = CallGraph.leaf_functions(graph)
      leaf_ids = Enum.map(leaves, & &1.id)

      assert "func_c/0" in leaf_ids
      refute "func_a/0" in leaf_ids
      refute "func_b/0" in leaf_ids
    end

    test "returns multiple leaf functions" do
      {:ok, graph} = setup_branching_call_graph()

      {:ok, leaves} = CallGraph.leaf_functions(graph)
      leaf_ids = Enum.map(leaves, & &1.id)

      assert "leaf_a/0" in leaf_ids
      assert "leaf_b/0" in leaf_ids
    end
  end

  describe "call_depth/2" do
    test "returns 0 for leaf function" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, depth} = CallGraph.call_depth(graph, "func_c/0")
      assert depth == 0
    end

    test "returns correct depth for chain" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, depth_b} = CallGraph.call_depth(graph, "func_b/0")
      assert depth_b == 1

      {:ok, depth_a} = CallGraph.call_depth(graph, "func_a/0")
      assert depth_a == 2
    end

    test "returns error for cyclic function" do
      {:ok, graph} = setup_cyclic_call_graph()

      result = CallGraph.call_depth(graph, "cycle_a/0")
      assert result == {:error, :cycle_detected}
    end
  end

  describe "all_call_depths/1" do
    test "returns depths for all functions" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, depths} = CallGraph.all_call_depths(graph)

      assert depths["func_c/0"] == 0
      assert depths["func_b/0"] == 1
      assert depths["func_a/0"] == 2
    end

    test "marks cyclic functions" do
      {:ok, graph} = setup_cyclic_call_graph()

      {:ok, depths} = CallGraph.all_call_depths(graph)

      assert depths["cycle_a/0"] == :cycle
      assert depths["cycle_b/0"] == :cycle
      assert depths["cycle_c/0"] == :cycle
    end
  end

  describe "hot_paths/2" do
    test "returns most connected functions" do
      {:ok, graph} = setup_hub_call_graph()

      {:ok, hot} = CallGraph.hot_paths(graph, limit: 1)

      # The hub function should be most connected
      assert length(hot) == 1
      hub = List.first(hot)
      assert hub.id == "hub/0"
      assert hub.connectivity > 0
    end

    test "respects limit option" do
      {:ok, graph} = setup_branching_call_graph()

      {:ok, hot} = CallGraph.hot_paths(graph, limit: 2)
      assert length(hot) <= 2
    end
  end

  describe "call_chain/4" do
    test "finds direct call chain" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, chain} = CallGraph.call_chain(graph, "func_a/0", "func_b/0")
      assert chain == ["func_a/0", "func_b/0"]
    end

    test "finds transitive call chain" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, chain} = CallGraph.call_chain(graph, "func_a/0", "func_c/0")
      assert chain == ["func_a/0", "func_b/0", "func_c/0"]
    end

    test "returns error when no path exists" do
      {:ok, graph} = setup_linear_call_graph()

      result = CallGraph.call_chain(graph, "func_c/0", "func_a/0")
      assert result == {:error, :no_path}
    end
  end

  describe "module_call_stats/2" do
    test "returns call statistics for module" do
      {:ok, graph} = setup_module_call_graph()

      {:ok, stats} = CallGraph.module_call_stats(graph, "TestModule")

      assert stats.module == "TestModule"
      assert stats.function_count == 3
      assert stats.internal_calls >= 0
      assert stats.external_dependencies >= 0
      assert is_float(stats.cohesion)
    end
  end

  describe "strongly_connected_components/1" do
    test "returns empty list for acyclic graph" do
      {:ok, graph} = setup_linear_call_graph()

      {:ok, sccs} = CallGraph.strongly_connected_components(graph)
      assert sccs == []
    end

    test "finds strongly connected components" do
      {:ok, graph} = setup_cyclic_call_graph()

      {:ok, sccs} = CallGraph.strongly_connected_components(graph)
      assert length(sccs) > 0

      # The cycle should form an SCC
      scc = List.first(sccs)
      assert length(scc) >= 3
    end
  end

  # Setup helpers

  defp setup_linear_call_graph do
    # func_a -> func_b -> func_c
    {:ok, graph} = InMemoryGraph.new()

    InMemoryGraph.add_node(graph, %{
      id: "func_a/0",
      type: :function,
      name: "func_a",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "func_b/0",
      type: :function,
      name: "func_b",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "func_c/0",
      type: :function,
      name: "func_c",
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "func_a/0",
      target: "func_b/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "func_b/0",
      target: "func_c/0",
      type: :calls,
      metadata: %{}
    })

    {:ok, graph}
  end

  defp setup_branching_call_graph do
    # root -> branch_a -> leaf_a
    #      -> branch_b -> leaf_b
    {:ok, graph} = InMemoryGraph.new()

    InMemoryGraph.add_node(graph, %{id: "root/0", type: :function, name: "root", metadata: %{}})

    InMemoryGraph.add_node(graph, %{
      id: "branch_a/0",
      type: :function,
      name: "branch_a",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "branch_b/0",
      type: :function,
      name: "branch_b",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "leaf_a/0",
      type: :function,
      name: "leaf_a",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "leaf_b/0",
      type: :function,
      name: "leaf_b",
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "root/0",
      target: "branch_a/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "root/0",
      target: "branch_b/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "branch_a/0",
      target: "leaf_a/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "branch_b/0",
      target: "leaf_b/0",
      type: :calls,
      metadata: %{}
    })

    {:ok, graph}
  end

  defp setup_cyclic_call_graph do
    # cycle_a -> cycle_b -> cycle_c -> cycle_a
    {:ok, graph} = InMemoryGraph.new()

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

  defp setup_multiple_cycles_graph do
    # Two separate cycles
    {:ok, graph} = InMemoryGraph.new()

    # Cycle 1: a -> b -> a
    InMemoryGraph.add_node(graph, %{id: "a/0", type: :function, name: "a", metadata: %{}})
    InMemoryGraph.add_node(graph, %{id: "b/0", type: :function, name: "b", metadata: %{}})
    InMemoryGraph.add_edge(graph, %{source: "a/0", target: "b/0", type: :calls, metadata: %{}})
    InMemoryGraph.add_edge(graph, %{source: "b/0", target: "a/0", type: :calls, metadata: %{}})

    # Cycle 2: x -> y -> x
    InMemoryGraph.add_node(graph, %{id: "x/0", type: :function, name: "x", metadata: %{}})
    InMemoryGraph.add_node(graph, %{id: "y/0", type: :function, name: "y", metadata: %{}})
    InMemoryGraph.add_edge(graph, %{source: "x/0", target: "y/0", type: :calls, metadata: %{}})
    InMemoryGraph.add_edge(graph, %{source: "y/0", target: "x/0", type: :calls, metadata: %{}})

    {:ok, graph}
  end

  defp setup_hub_call_graph do
    # Multiple functions calling a hub function
    # caller1, caller2, caller3 -> hub -> callee1, callee2
    {:ok, graph} = InMemoryGraph.new()

    InMemoryGraph.add_node(graph, %{id: "hub/0", type: :function, name: "hub", metadata: %{}})

    InMemoryGraph.add_node(graph, %{
      id: "caller1/0",
      type: :function,
      name: "caller1",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "caller2/0",
      type: :function,
      name: "caller2",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "caller3/0",
      type: :function,
      name: "caller3",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "callee1/0",
      type: :function,
      name: "callee1",
      metadata: %{}
    })

    InMemoryGraph.add_node(graph, %{
      id: "callee2/0",
      type: :function,
      name: "callee2",
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "caller1/0",
      target: "hub/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "caller2/0",
      target: "hub/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "caller3/0",
      target: "hub/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "hub/0",
      target: "callee1/0",
      type: :calls,
      metadata: %{}
    })

    InMemoryGraph.add_edge(graph, %{
      source: "hub/0",
      target: "callee2/0",
      type: :calls,
      metadata: %{}
    })

    {:ok, graph}
  end

  defp setup_module_call_graph do
    # Module with internal and external calls
    {:ok, graph} = InMemoryGraph.new()

    # Module node
    InMemoryGraph.add_node(graph, %{
      id: "TestModule",
      type: :module,
      name: "TestModule",
      metadata: %{}
    })

    # Functions in module
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

    # External function
    InMemoryGraph.add_node(graph, %{
      id: "External.helper/1",
      type: :function,
      name: "helper",
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

    InMemoryGraph.add_edge(graph, %{
      source: "TestModule.func2/0",
      target: "TestModule.func3/0",
      type: :calls,
      metadata: %{}
    })

    # External call
    InMemoryGraph.add_edge(graph, %{
      source: "TestModule.func3/0",
      target: "External.helper/1",
      type: :calls,
      metadata: %{}
    })

    {:ok, graph}
  end
end
