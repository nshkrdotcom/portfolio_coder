defmodule PortfolioCoder.Agent.Specialists.DocsAgentTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Agent.Specialists.DocsAgent
  alias PortfolioCoder.Graph.InMemoryGraph
  alias PortfolioCoder.Indexer.InMemorySearch

  @sample_docs [
    %{
      id: "parser.ex:1",
      content: """
      defmodule MyApp.Parser do
        @moduledoc \"\"\"
        Parses source files into AST.

        ## Usage

            {:ok, ast} = Parser.parse("file.ex")

        ## Options

          * `:strict` - Enable strict mode (default: false)
        \"\"\"
        def parse(path), do: {:ok, %{}}
      end
      """,
      metadata: %{path: "lib/my_app/parser.ex", language: :elixir, type: :module}
    },
    %{
      id: "utils.ex:1",
      content: """
      defmodule MyApp.Utils do
        @moduledoc false
        def helper, do: :ok
      end
      """,
      metadata: %{path: "lib/my_app/utils.ex", language: :elixir, type: :module}
    }
  ]

  setup do
    {:ok, index} = InMemorySearch.new()
    :ok = InMemorySearch.add_all(index, @sample_docs)
    {:ok, graph} = InMemoryGraph.new()
    {:ok, index: index, graph: graph}
  end

  describe "new/2" do
    test "creates docs agent", %{index: index, graph: graph} do
      agent = DocsAgent.new(index, graph)

      assert is_struct(agent, DocsAgent)
      assert agent.index == index
      assert agent.graph == graph
    end

    test "accepts options", %{index: index, graph: graph} do
      agent = DocsAgent.new(index, graph, doc_style: :ex_doc)

      assert agent.doc_style == :ex_doc
    end
  end

  describe "find_documented_modules/1" do
    test "finds modules with documentation", %{index: index, graph: graph} do
      agent = DocsAgent.new(index, graph)

      {:ok, modules} = DocsAgent.find_documented_modules(agent)

      assert is_list(modules)
    end
  end

  describe "find_undocumented_modules/1" do
    test "finds modules without documentation", %{index: index, graph: graph} do
      agent = DocsAgent.new(index, graph)

      {:ok, modules} = DocsAgent.find_undocumented_modules(agent)

      assert is_list(modules)
    end
  end

  describe "analyze_documentation/2" do
    test "analyzes module documentation", %{index: index, graph: graph} do
      agent = DocsAgent.new(index, graph)

      {:ok, analysis} = DocsAgent.analyze_documentation(agent, "MyApp.Parser")

      assert is_map(analysis)
      assert Map.has_key?(analysis, :has_moduledoc)
      assert Map.has_key?(analysis, :has_examples)
      assert Map.has_key?(analysis, :completeness_score)
    end

    test "handles missing module", %{index: index, graph: graph} do
      agent = DocsAgent.new(index, graph)

      {:ok, analysis} = DocsAgent.analyze_documentation(agent, "NonExistent")

      assert analysis.has_moduledoc == false
    end
  end

  describe "extract_examples/2" do
    test "extracts code examples from documentation", %{index: index, graph: graph} do
      agent = DocsAgent.new(index, graph)

      {:ok, examples} = DocsAgent.extract_examples(agent, "MyApp.Parser")

      assert is_list(examples)
    end
  end

  describe "suggest_documentation/2" do
    test "suggests documentation for undocumented code", %{index: index, graph: graph} do
      agent = DocsAgent.new(index, graph)

      {:ok, suggestions} = DocsAgent.suggest_documentation(agent, "MyApp.Utils")

      assert is_list(suggestions)
    end
  end

  describe "check_doc_coverage/1" do
    test "calculates documentation coverage", %{index: index, graph: graph} do
      agent = DocsAgent.new(index, graph)

      {:ok, coverage} = DocsAgent.check_doc_coverage(agent)

      assert is_map(coverage)
      assert Map.has_key?(coverage, :total_modules)
      assert Map.has_key?(coverage, :documented_modules)
      assert Map.has_key?(coverage, :coverage_percentage)
    end
  end

  describe "validate_docs/1" do
    test "validates documentation quality", %{index: index, graph: graph} do
      agent = DocsAgent.new(index, graph)

      {:ok, issues} = DocsAgent.validate_docs(agent)

      assert is_list(issues)
    end
  end

  describe "generate_doc_report/1" do
    test "generates documentation report", %{index: index, graph: graph} do
      agent = DocsAgent.new(index, graph)

      {:ok, report} = DocsAgent.generate_doc_report(agent)

      assert is_map(report)
      assert Map.has_key?(report, :summary)
      assert Map.has_key?(report, :modules)
      assert Map.has_key?(report, :issues)
    end
  end

  describe "config/0" do
    test "returns default configuration" do
      config = DocsAgent.config()

      assert is_map(config)
      assert Map.has_key?(config, :doc_style)
    end
  end
end
