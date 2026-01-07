defmodule PortfolioCoder.QA.GraphAwareTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Graph.InMemoryGraph
  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.QA.GraphAware

  @sample_docs [
    %{
      id: "parser.ex:1",
      content: """
      defmodule MyApp.Parser do
        import MyApp.Utils
        alias MyApp.Tokenizer
        def parse(path), do: {:ok, %{}}
      end
      """,
      metadata: %{path: "lib/my_app/parser.ex", language: :elixir}
    },
    %{
      id: "tokenizer.ex:1",
      content: """
      defmodule MyApp.Tokenizer do
        def tokenize(content), do: []
      end
      """,
      metadata: %{path: "lib/my_app/tokenizer.ex", language: :elixir}
    }
  ]

  @sample_parsed %{
    language: :elixir,
    symbols: [
      %{type: :module, name: "MyApp.Parser", line: 1, arity: nil, visibility: :public},
      %{type: :function, name: "parse", line: 4, arity: 1, visibility: :public}
    ],
    references: [
      %{type: :import, module: "MyApp.Utils", line: 2, metadata: %{}},
      %{type: :alias, module: "MyApp.Tokenizer", line: 3, metadata: %{}}
    ]
  }

  setup do
    {:ok, index} = InMemorySearch.new()
    :ok = InMemorySearch.add_all(index, @sample_docs)

    {:ok, graph} = InMemoryGraph.new()
    :ok = InMemoryGraph.add_from_parsed(graph, @sample_parsed, "lib/my_app/parser.ex")

    {:ok, index: index, graph: graph}
  end

  describe "new/2" do
    test "creates graph-aware QA instance", %{index: index, graph: graph} do
      qa = GraphAware.new(index, graph)

      assert is_struct(qa, GraphAware)
      assert qa.index == index
      assert qa.graph == graph
    end

    test "accepts options", %{index: index, graph: graph} do
      qa = GraphAware.new(index, graph, max_graph_depth: 3, include_callees: true)

      assert qa.max_graph_depth == 3
      assert qa.include_callees == true
    end
  end

  describe "build_graph_context/3" do
    test "builds context from search results", %{graph: graph} do
      results = @sample_docs

      context = GraphAware.build_graph_context(graph, results, "parser")

      assert is_binary(context)
    end

    test "returns message for empty results", %{graph: graph} do
      context = GraphAware.build_graph_context(graph, [], "query")

      assert context == "No specific module relationships found."
    end
  end

  describe "extract_modules_from_results/1" do
    test "extracts module names from search results" do
      results = @sample_docs

      modules = GraphAware.extract_modules_from_results(results)

      assert is_list(modules)
      assert "MyApp.Parser" in modules
    end

    test "returns empty for no matches" do
      results = [%{id: "x", content: "no modules here", metadata: %{}}]

      modules = GraphAware.extract_modules_from_results(results)

      assert modules == []
    end
  end

  describe "extract_modules_from_question/2" do
    test "finds modules mentioned in question", %{graph: graph} do
      question = "How does Parser work?"

      modules = GraphAware.extract_modules_from_question(graph, question)

      assert is_list(modules)
    end

    test "returns empty for no matches", %{graph: graph} do
      question = "What is xyz123?"

      modules = GraphAware.extract_modules_from_question(graph, question)

      assert modules == []
    end
  end

  describe "get_module_context/2" do
    test "gets imports and functions for a module", %{graph: graph} do
      context = GraphAware.get_module_context(graph, "MyApp.Parser")

      assert is_map(context)
      assert Map.has_key?(context, :imports)
      assert Map.has_key?(context, :functions)
    end

    test "handles missing module", %{graph: graph} do
      context = GraphAware.get_module_context(graph, "NonExistent")

      assert context.imports == []
      assert context.functions == []
    end
  end

  describe "format_module_context/2" do
    test "formats module context as string" do
      context = %{imports: ["Mod.A", "Mod.B"], functions: ["func1/1", "func2/0"]}

      formatted = GraphAware.format_module_context("MyModule", context)

      assert is_binary(formatted)
      assert String.contains?(formatted, "MyModule")
      assert String.contains?(formatted, "Imports")
      assert String.contains?(formatted, "Functions")
    end
  end

  describe "ask/2 (without LLM)" do
    test "returns result with graph context", %{index: index, graph: graph} do
      qa = GraphAware.new(index, graph, llm_module: nil)

      {:ok, result} = GraphAware.ask(qa, "How does Parser work?")

      assert is_map(result)
      assert Map.has_key?(result, :question)
      assert Map.has_key?(result, :code_context)
      assert Map.has_key?(result, :graph_context)
    end

    test "includes sources", %{index: index, graph: graph} do
      qa = GraphAware.new(index, graph, llm_module: nil)

      {:ok, result} = GraphAware.ask(qa, "parser")

      assert Map.has_key?(result, :sources)
      assert is_list(result.sources)
    end
  end

  describe "with_graph_depth/2" do
    test "sets graph depth", %{index: index, graph: graph} do
      qa =
        GraphAware.new(index, graph)
        |> GraphAware.with_graph_depth(5)

      assert qa.max_graph_depth == 5
    end
  end

  describe "with_callees/2" do
    test "enables callee inclusion", %{index: index, graph: graph} do
      qa =
        GraphAware.new(index, graph)
        |> GraphAware.with_callees(true)

      assert qa.include_callees == true
    end
  end

  describe "config/0" do
    test "returns default configuration" do
      config = GraphAware.config()

      assert is_map(config)
      assert Map.has_key?(config, :max_graph_depth)
      assert Map.has_key?(config, :include_callees)
    end
  end
end
