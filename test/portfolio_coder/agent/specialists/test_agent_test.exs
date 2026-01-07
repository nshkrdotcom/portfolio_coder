defmodule PortfolioCoder.Agent.Specialists.TestAgentTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Agent.Specialists.TestAgent
  alias PortfolioCoder.Graph.InMemoryGraph
  alias PortfolioCoder.Indexer.InMemorySearch

  @sample_docs [
    %{
      id: "parser.ex:1",
      content: """
      defmodule MyApp.Parser do
        def parse(path), do: {:ok, %{}}
        def validate(ast), do: :ok
      end
      """,
      metadata: %{path: "lib/my_app/parser.ex", language: :elixir, type: :module}
    },
    %{
      id: "parser_test.exs:1",
      content: """
      defmodule MyApp.ParserTest do
        use ExUnit.Case, async: true
        alias MyApp.Parser

        test "parses valid file" do
          assert {:ok, _} = Parser.parse("test.ex")
        end

        describe "validate/1" do
          test "validates ast" do
            assert :ok = Parser.validate(%{})
          end
        end
      end
      """,
      metadata: %{path: "test/my_app/parser_test.exs", language: :elixir, type: :test}
    },
    %{
      id: "utils.ex:1",
      content: """
      defmodule MyApp.Utils do
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
    test "creates test agent", %{index: index, graph: graph} do
      agent = TestAgent.new(index, graph)

      assert is_struct(agent, TestAgent)
      assert agent.index == index
    end

    test "accepts options", %{index: index, graph: graph} do
      agent = TestAgent.new(index, graph, test_framework: :ex_unit)

      assert agent.test_framework == :ex_unit
    end
  end

  describe "find_tests/1" do
    test "finds test files", %{index: index, graph: graph} do
      agent = TestAgent.new(index, graph)

      {:ok, tests} = TestAgent.find_tests(agent)

      assert is_list(tests)
      assert tests != []
    end
  end

  describe "find_untested_modules/1" do
    test "finds modules without tests", %{index: index, graph: graph} do
      agent = TestAgent.new(index, graph)

      {:ok, untested} = TestAgent.find_untested_modules(agent)

      assert is_list(untested)
      # Utils has no test
      names = Enum.map(untested, & &1.name)
      assert "MyApp.Utils" in names
    end
  end

  describe "analyze_test_coverage/2" do
    test "analyzes test coverage for module", %{index: index, graph: graph} do
      agent = TestAgent.new(index, graph)

      {:ok, coverage} = TestAgent.analyze_test_coverage(agent, "MyApp.Parser")

      assert is_map(coverage)
      assert Map.has_key?(coverage, :module)
      assert Map.has_key?(coverage, :test_count)
      assert Map.has_key?(coverage, :covered_functions)
    end
  end

  describe "extract_test_cases/2" do
    test "extracts test cases from test file", %{index: index, graph: graph} do
      agent = TestAgent.new(index, graph)

      {:ok, cases} = TestAgent.extract_test_cases(agent, "MyApp.ParserTest")

      assert is_list(cases)
      assert cases != []
    end
  end

  describe "find_related_tests/2" do
    test "finds tests related to a module", %{index: index, graph: graph} do
      agent = TestAgent.new(index, graph)

      {:ok, tests} = TestAgent.find_related_tests(agent, "MyApp.Parser")

      assert is_list(tests)
    end
  end

  describe "suggest_tests/2" do
    test "suggests tests for untested code", %{index: index, graph: graph} do
      agent = TestAgent.new(index, graph)

      {:ok, suggestions} = TestAgent.suggest_tests(agent, "MyApp.Utils")

      assert is_list(suggestions)
    end
  end

  describe "check_test_quality/1" do
    test "evaluates test quality metrics", %{index: index, graph: graph} do
      agent = TestAgent.new(index, graph)

      {:ok, quality} = TestAgent.check_test_quality(agent)

      assert is_map(quality)
      assert Map.has_key?(quality, :total_tests)
      assert Map.has_key?(quality, :describe_blocks)
    end
  end

  describe "generate_test_report/1" do
    test "generates test coverage report", %{index: index, graph: graph} do
      agent = TestAgent.new(index, graph)

      {:ok, report} = TestAgent.generate_test_report(agent)

      assert is_map(report)
      assert Map.has_key?(report, :summary)
      assert Map.has_key?(report, :untested)
    end
  end

  describe "config/0" do
    test "returns default configuration" do
      config = TestAgent.config()

      assert is_map(config)
      assert Map.has_key?(config, :test_framework)
    end
  end
end
