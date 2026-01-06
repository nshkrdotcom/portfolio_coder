defmodule PortfolioCoder.Graph.InMemoryGraphTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Graph.InMemoryGraph

  setup do
    {:ok, graph} = InMemoryGraph.new()
    %{graph: graph}
  end

  describe "add_node/2 and get_node/2" do
    test "adds and retrieves a node", %{graph: graph} do
      node = %{id: "MyModule", type: :module, name: "MyModule", metadata: %{}}
      :ok = InMemoryGraph.add_node(graph, node)

      {:ok, retrieved} = InMemoryGraph.get_node(graph, "MyModule")
      assert retrieved.id == "MyModule"
      assert retrieved.type == :module
    end

    test "returns error for non-existent node", %{graph: graph} do
      assert {:error, :not_found} = InMemoryGraph.get_node(graph, "NonExistent")
    end
  end

  describe "add_edge/2" do
    test "adds an edge between nodes", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "A", type: :module, name: "A", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "B", type: :module, name: "B", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "A", target: "B", type: :imports, metadata: %{}})

      {:ok, edges} = InMemoryGraph.edges(graph)
      assert length(edges) == 1
      assert hd(edges).source == "A"
      assert hd(edges).target == "B"
    end
  end

  describe "outgoing/2 and incoming/2" do
    test "returns outgoing edges", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "A", type: :module, name: "A", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "B", type: :module, name: "B", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "C", type: :module, name: "C", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "A", target: "B", type: :imports, metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "A", target: "C", type: :imports, metadata: %{}})

      {:ok, outgoing} = InMemoryGraph.outgoing(graph, "A")
      assert length(outgoing) == 2
      targets = Enum.map(outgoing, & &1.target)
      assert "B" in targets
      assert "C" in targets
    end

    test "returns incoming edges", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "A", type: :module, name: "A", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "B", type: :module, name: "B", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "A", target: "B", type: :imports, metadata: %{}})

      {:ok, incoming} = InMemoryGraph.incoming(graph, "B")
      assert length(incoming) == 1
      assert hd(incoming).source == "A"
    end
  end

  describe "nodes_by_type/2" do
    test "returns nodes filtered by type", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "M1", type: :module, name: "M1", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "M2", type: :module, name: "M2", metadata: %{}})

      :ok =
        InMemoryGraph.add_node(graph, %{id: "F1", type: :function, name: "func", metadata: %{}})

      {:ok, modules} = InMemoryGraph.nodes_by_type(graph, :module)
      assert length(modules) == 2

      {:ok, functions} = InMemoryGraph.nodes_by_type(graph, :function)
      assert length(functions) == 1
    end
  end

  describe "callees/2 and callers/2" do
    test "returns callees of a function", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "f1", type: :function, name: "f1", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "f2", type: :function, name: "f2", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "f3", type: :function, name: "f3", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "f1", target: "f2", type: :calls, metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "f1", target: "f3", type: :calls, metadata: %{}})

      {:ok, callees} = InMemoryGraph.callees(graph, "f1")
      assert length(callees) == 2
      assert "f2" in callees
      assert "f3" in callees
    end

    test "returns callers of a function", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "f1", type: :function, name: "f1", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "f2", type: :function, name: "f2", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "f1", target: "f2", type: :calls, metadata: %{}})

      {:ok, callers} = InMemoryGraph.callers(graph, "f2")
      assert length(callers) == 1
      assert "f1" in callers
    end
  end

  describe "imports_of/2 and imported_by/2" do
    test "returns imports of a module", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "A", type: :module, name: "A", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "B", type: :external, name: "B", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "C", type: :external, name: "C", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "A", target: "B", type: :imports, metadata: %{}})

      :ok = InMemoryGraph.add_edge(graph, %{source: "A", target: "C", type: :uses, metadata: %{}})

      {:ok, imports} = InMemoryGraph.imports_of(graph, "A")
      assert length(imports) == 2
      assert "B" in imports
      assert "C" in imports
    end

    test "returns modules that import a given module", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "A", type: :module, name: "A", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "B", type: :module, name: "B", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "C", type: :external, name: "C", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "A", target: "C", type: :imports, metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "B", target: "C", type: :imports, metadata: %{}})

      {:ok, importers} = InMemoryGraph.imported_by(graph, "C")
      assert length(importers) == 2
      assert "A" in importers
      assert "B" in importers
    end
  end

  describe "functions_of/2" do
    test "returns functions defined by a module", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "M", type: :module, name: "M", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "f1", type: :function, name: "f1", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "f2", type: :function, name: "f2", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "M", target: "f1", type: :defines, metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "M", target: "f2", type: :defines, metadata: %{}})

      {:ok, functions} = InMemoryGraph.functions_of(graph, "M")
      assert length(functions) == 2
      assert "f1" in functions
      assert "f2" in functions
    end
  end

  describe "find_path/3" do
    test "finds path between connected nodes", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "A", type: :module, name: "A", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "B", type: :module, name: "B", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "C", type: :module, name: "C", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "A", target: "B", type: :imports, metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "B", target: "C", type: :imports, metadata: %{}})

      {:ok, path} = InMemoryGraph.find_path(graph, "A", "C")
      assert path == ["A", "B", "C"]
    end

    test "returns error when no path exists", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "A", type: :module, name: "A", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "B", type: :module, name: "B", metadata: %{}})
      # No edge between A and B

      assert {:error, :no_path} = InMemoryGraph.find_path(graph, "A", "B")
    end

    test "finds direct path", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "A", type: :module, name: "A", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "B", type: :module, name: "B", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "A", target: "B", type: :imports, metadata: %{}})

      {:ok, path} = InMemoryGraph.find_path(graph, "A", "B")
      assert path == ["A", "B"]
    end
  end

  describe "stats/1" do
    test "returns correct statistics", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "M", type: :module, name: "M", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "f1", type: :function, name: "f1", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "f2", type: :function, name: "f2", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "M", target: "f1", type: :defines, metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "M", target: "f2", type: :defines, metadata: %{}})

      stats = InMemoryGraph.stats(graph)
      assert stats.node_count == 3
      assert stats.edge_count == 2
      assert stats.nodes_by_type[:module] == 1
      assert stats.nodes_by_type[:function] == 2
      assert stats.edges_by_type[:defines] == 2
    end
  end

  describe "clear/1" do
    test "removes all nodes and edges", %{graph: graph} do
      :ok = InMemoryGraph.add_node(graph, %{id: "A", type: :module, name: "A", metadata: %{}})
      :ok = InMemoryGraph.add_node(graph, %{id: "B", type: :module, name: "B", metadata: %{}})

      :ok =
        InMemoryGraph.add_edge(graph, %{source: "A", target: "B", type: :imports, metadata: %{}})

      :ok = InMemoryGraph.clear(graph)

      stats = InMemoryGraph.stats(graph)
      assert stats.node_count == 0
      assert stats.edge_count == 0
    end
  end

  describe "add_from_parsed/3" do
    test "builds graph from parsed result", %{graph: graph} do
      # Simulate a parsed result from the Parser module
      parsed = %{
        language: :elixir,
        symbols: [
          %{type: :module, name: "MyApp.User", line: 1, arity: nil, visibility: :public},
          %{type: :function, name: "get", line: 5, arity: 1, visibility: :public},
          %{type: :function, name: "create", line: 10, arity: 1, visibility: :public}
        ],
        references: [
          %{type: :import, module: "Ecto.Query", line: 2, metadata: %{}},
          %{type: :alias, module: "MyApp.Repo", line: 3, metadata: %{}}
        ]
      }

      :ok = InMemoryGraph.add_from_parsed(graph, parsed, "lib/my_app/user.ex")

      stats = InMemoryGraph.stats(graph)
      assert stats.node_count > 0

      # Should have file node
      {:ok, file_nodes} = InMemoryGraph.nodes_by_type(graph, :file)
      assert length(file_nodes) == 1

      # Should have module node
      {:ok, module_nodes} = InMemoryGraph.nodes_by_type(graph, :module)
      assert length(module_nodes) == 1
      assert hd(module_nodes).name == "MyApp.User"

      # Should have function nodes
      {:ok, function_nodes} = InMemoryGraph.nodes_by_type(graph, :function)
      assert length(function_nodes) == 2

      # Should have external nodes for imports
      {:ok, external_nodes} = InMemoryGraph.nodes_by_type(graph, :external)
      assert length(external_nodes) >= 1

      # Module should have imports
      {:ok, imports} = InMemoryGraph.imports_of(graph, "MyApp.User")
      assert length(imports) >= 1
    end
  end
end
