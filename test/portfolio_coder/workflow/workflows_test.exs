defmodule PortfolioCoder.Workflow.WorkflowsTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Workflow.Workflows
  alias PortfolioCoder.Graph.InMemoryGraph

  @test_repo_path Path.join(System.tmp_dir!(), "workflow_test_repo_#{:rand.uniform(10000)}")

  setup_all do
    # Create a test repo structure
    File.mkdir_p!(@test_repo_path)
    File.mkdir_p!(Path.join(@test_repo_path, "lib"))
    File.mkdir_p!(Path.join(@test_repo_path, "test"))

    # Create some test files
    File.write!(Path.join(@test_repo_path, "lib/module_a.ex"), """
    defmodule ModuleA do
      def func_a do
        ModuleB.func_b()
      end
    end
    """)

    File.write!(Path.join(@test_repo_path, "lib/module_b.ex"), """
    defmodule ModuleB do
      def func_b do
        :ok
      end
    end
    """)

    File.write!(Path.join(@test_repo_path, "test/module_a_test.exs"), """
    defmodule ModuleATest do
      use ExUnit.Case
      test "it works" do
        assert ModuleA.func_a() == :ok
      end
    end
    """)

    on_exit(fn -> File.rm_rf!(@test_repo_path) end)

    :ok
  end

  describe "analyze_repo/2" do
    test "analyzes a repository" do
      {:ok, result} = Workflows.analyze_repo(@test_repo_path)

      assert result.status == :completed
      assert length(result.context.files) >= 2
      assert length(result.context.parsed) >= 2
      assert result.context.graph != nil
      assert result.context.index != nil
    end

    test "scans files matching patterns" do
      {:ok, result} = Workflows.analyze_repo(@test_repo_path, patterns: ["**/*.ex"])

      # Should find .ex files but not .exs
      assert Enum.all?(result.context.files, &String.ends_with?(&1, ".ex"))
    end

    test "excludes specified patterns" do
      {:ok, result} = Workflows.analyze_repo(@test_repo_path, exclude: ["**/test/**"])

      # Should not include test files
      refute Enum.any?(result.context.files, &String.contains?(&1, "/test/"))
    end

    test "builds searchable index" do
      {:ok, result} = Workflows.analyze_repo(@test_repo_path)

      # Search the index
      {:ok, search_results} =
        PortfolioCoder.Indexer.InMemorySearch.search(
          result.context.index,
          "ModuleA",
          limit: 5
        )

      assert length(search_results) > 0
    end

    test "builds code graph" do
      {:ok, result} = Workflows.analyze_repo(@test_repo_path)

      # Check graph has nodes
      {:ok, nodes} = PortfolioCoder.Graph.InMemoryGraph.nodes_by_type(result.context.graph, :file)
      assert length(nodes) >= 2
    end

    test "tracks timing for each step" do
      {:ok, result} = Workflows.analyze_repo(@test_repo_path)

      assert Map.has_key?(result.timing, :scan_files)
      assert Map.has_key?(result.timing, :parse_files)
      assert Map.has_key?(result.timing, :build_graph)
      assert Map.has_key?(result.timing, :build_index)
    end
  end

  describe "review_code/2" do
    test "reviews a simple diff" do
      diff = """
      diff --git a/lib/module_a.ex b/lib/module_a.ex
      --- a/lib/module_a.ex
      +++ b/lib/module_a.ex
      @@ -1,5 +1,6 @@
       defmodule ModuleA do
         def func_a do
      +    IO.puts("debug")
           ModuleB.func_b()
         end
       end
      """

      {:ok, result} = Workflows.review_code(diff)

      assert result.status == :completed
      assert length(result.context.changes) == 1
      assert result.context.analysis.total_added == 1
      assert result.context.review != nil
    end

    test "parses multiple file changes" do
      diff = """
      diff --git a/lib/module_a.ex b/lib/module_a.ex
      --- a/lib/module_a.ex
      +++ b/lib/module_a.ex
      @@ -1,3 +1,4 @@
      +# new line
       defmodule ModuleA do
       end
      diff --git a/lib/module_b.ex b/lib/module_b.ex
      --- a/lib/module_b.ex
      +++ b/lib/module_b.ex
      @@ -1,3 +1,4 @@
      +# another new line
       defmodule ModuleB do
       end
      """

      {:ok, result} = Workflows.review_code(diff)

      assert result.context.analysis.total_files == 2
    end

    test "calculates risk level based on change size" do
      # Small change
      small_diff = """
      diff --git a/lib/a.ex b/lib/a.ex
      +line1
      """

      {:ok, small_result} = Workflows.review_code(small_diff)
      assert small_result.context.impact.risk_level == :low

      # Medium change (build a diff with 100+ lines)
      medium_diff =
        """
        diff --git a/lib/a.ex b/lib/a.ex
        """ <> (1..150 |> Enum.map(fn _ -> "+new line\n" end) |> Enum.join())

      {:ok, medium_result} = Workflows.review_code(medium_diff)
      assert medium_result.context.impact.risk_level == :medium
    end

    test "uses index for context gathering when provided" do
      # First analyze the repo to get an index
      {:ok, analysis} = Workflows.analyze_repo(@test_repo_path)

      diff = """
      diff --git a/lib/module_a.ex b/lib/module_a.ex
      +new line
      """

      {:ok, result} = Workflows.review_code(diff, index: analysis.context.index)

      # Should have found related context
      assert is_list(result.context.related_context)
    end
  end

  describe "plan_refactoring/2" do
    test "plans refactoring for a set of functions" do
      {:ok, graph} = setup_refactor_graph()

      {:ok, result} = Workflows.plan_refactoring(graph, ["A.func/0", "B.func/0", "C.func/0"])

      assert result.status == :completed
      assert length(result.context.order) == 3
      assert result.context.plan != nil
    end

    test "orders functions by dependencies (leaves first)" do
      {:ok, graph} = setup_refactor_graph()

      # A -> B -> C (C is leaf)
      {:ok, result} = Workflows.plan_refactoring(graph, ["A.func/0", "B.func/0", "C.func/0"])

      # C should be first (no dependencies in the set)
      assert hd(result.context.order) == "C.func/0"
    end

    test "calculates impact for each function" do
      {:ok, graph} = setup_refactor_graph()

      {:ok, result} = Workflows.plan_refactoring(graph, ["A.func/0", "B.func/0"])

      assert Map.has_key?(result.context.impact, "A.func/0")
      assert Map.has_key?(result.context.impact, "B.func/0")

      # B has one caller (A)
      assert result.context.impact["B.func/0"].caller_count >= 1
    end

    test "generates refactoring plan" do
      {:ok, graph} = setup_refactor_graph()

      {:ok, result} = Workflows.plan_refactoring(graph, ["A.func/0", "B.func/0"])

      assert result.context.plan.total_functions == 2
      assert is_list(result.context.plan.steps)
    end
  end

  # Helper to create a test graph
  defp setup_refactor_graph do
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
end
