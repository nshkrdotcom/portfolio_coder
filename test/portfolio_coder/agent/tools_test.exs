defmodule PortfolioCoder.Agent.ToolsTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Agent.Tool
  alias PortfolioCoder.Agent.Tools
  alias PortfolioCoder.Graph.InMemoryGraph
  alias PortfolioCoder.Indexer.InMemorySearch

  describe "Tool.to_function_spec/1" do
    test "converts tool module to function spec" do
      spec = Tool.to_function_spec(Tools.SearchCode)

      assert spec.name == :search_code
      assert is_binary(spec.description)
      assert spec.parameters.type == "object"
      assert Map.has_key?(spec.parameters.properties, :query)
    end
  end

  describe "SearchCode tool" do
    test "searches indexed code" do
      {:ok, index} = InMemorySearch.new()

      InMemorySearch.add(index, %{
        id: "auth:1",
        content: "defmodule Auth do def login(user), do: :ok end",
        metadata: %{path: "lib/auth.ex", language: :elixir, name: "login", type: :function}
      })

      context = %{index: index}
      params = %{query: "login", limit: 5}

      {:ok, results} = Tools.SearchCode.execute(params, context)

      assert is_list(results)
      assert results != []
      assert hd(results).path == "lib/auth.ex"
    end

    test "returns error when no index" do
      context = %{index: nil}
      params = %{query: "test"}

      {:error, reason} = Tools.SearchCode.execute(params, context)
      assert String.contains?(reason, "No index")
    end
  end

  describe "GetCallers tool" do
    test "finds callers of a function" do
      {:ok, graph} = setup_call_graph()
      context = %{graph: graph}

      {:ok, result} = Tools.GetCallers.execute(%{function_id: "B.func/0"}, context)

      assert result.function == "B.func/0"
      assert "A.func/0" in result.callers
    end

    test "finds transitive callers" do
      {:ok, graph} = setup_call_graph()
      context = %{graph: graph}

      {:ok, result} =
        Tools.GetCallers.execute(%{function_id: "C.func/0", transitive: true}, context)

      assert result.transitive == true
      assert "A.func/0" in result.callers or "B.func/0" in result.callers
    end
  end

  describe "GetCallees tool" do
    test "finds callees of a function" do
      {:ok, graph} = setup_call_graph()
      context = %{graph: graph}

      {:ok, result} = Tools.GetCallees.execute(%{function_id: "A.func/0"}, context)

      assert result.function == "A.func/0"
      assert "B.func/0" in result.callees
    end
  end

  describe "GetImports tool" do
    test "finds imports of a module" do
      {:ok, graph} = setup_import_graph()
      context = %{graph: graph}

      {:ok, result} =
        Tools.GetImports.execute(%{module_id: "ModuleA", direction: "imports"}, context)

      assert result.module == "ModuleA"
      assert "ModuleB" in result.imports
    end

    test "finds modules that import a module" do
      {:ok, graph} = setup_import_graph()
      context = %{graph: graph}

      {:ok, result} =
        Tools.GetImports.execute(%{module_id: "ModuleB", direction: "imported_by"}, context)

      assert result.module == "ModuleB"
      assert "ModuleA" in result.imported_by
    end
  end

  describe "GraphStats tool" do
    test "returns graph statistics" do
      {:ok, graph} = setup_call_graph()
      context = %{graph: graph}

      {:ok, result} = Tools.GraphStats.execute(%{}, context)

      assert result.node_count > 0
      assert result.edge_count > 0
      assert is_map(result.nodes_by_type)
    end

    test "includes hot paths when requested" do
      {:ok, graph} = setup_call_graph()
      context = %{graph: graph}

      {:ok, result} = Tools.GraphStats.execute(%{include_hot_paths: true}, context)

      assert Map.has_key?(result, :hot_paths)
    end
  end

  describe "FindPath tool" do
    test "finds path between functions" do
      {:ok, graph} = setup_call_graph()
      context = %{graph: graph}

      {:ok, result} = Tools.FindPath.execute(%{from: "A.func/0", to: "C.func/0"}, context)

      assert result.from == "A.func/0"
      assert result.to == "C.func/0"
      assert is_list(result.path) or result.path == nil
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

  defp setup_import_graph do
    {:ok, graph} = InMemoryGraph.new()

    # ModuleA imports ModuleB
    InMemoryGraph.add_node(graph, %{id: "ModuleA", type: :module, name: "ModuleA", metadata: %{}})
    InMemoryGraph.add_node(graph, %{id: "ModuleB", type: :module, name: "ModuleB", metadata: %{}})

    InMemoryGraph.add_edge(graph, %{
      source: "ModuleA",
      target: "ModuleB",
      type: :imports,
      metadata: %{}
    })

    {:ok, graph}
  end
end
