defmodule PortfolioCoder.Workflow.PipelineTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Workflow.Pipeline

  describe "new/1" do
    test "creates an empty pipeline" do
      pipeline = Pipeline.new(:test_pipeline)

      assert pipeline.name == :test_pipeline
      assert pipeline.steps == []
      assert pipeline.context == %{}
    end

    test "accepts initial context" do
      pipeline = Pipeline.new(:test_pipeline, context: %{path: "/tmp"})

      assert pipeline.context == %{path: "/tmp"}
    end
  end

  describe "add_step/3" do
    test "adds a step to the pipeline" do
      pipeline =
        Pipeline.new(:test)
        |> Pipeline.add_step(:step1, fn ctx -> {:ok, Map.put(ctx, :step1_done, true)} end)

      assert length(pipeline.steps) == 1
      assert hd(pipeline.steps).name == :step1
    end

    test "adds step with dependencies" do
      pipeline =
        Pipeline.new(:test)
        |> Pipeline.add_step(:step1, fn ctx -> {:ok, ctx} end)
        |> Pipeline.add_step(:step2, fn ctx -> {:ok, ctx} end, depends_on: [:step1])

      step2 = Enum.find(pipeline.steps, &(&1.name == :step2))
      assert step2.depends_on == [:step1]
    end

    test "adds step marked as parallel" do
      pipeline =
        Pipeline.new(:test)
        |> Pipeline.add_step(:step1, fn ctx -> {:ok, ctx} end, parallel: true)

      step = hd(pipeline.steps)
      assert step.parallel == true
    end
  end

  describe "run/1" do
    test "executes a single step pipeline" do
      pipeline =
        Pipeline.new(:test, context: %{value: 1})
        |> Pipeline.add_step(:double, fn ctx -> {:ok, Map.put(ctx, :value, ctx.value * 2)} end)

      {:ok, result} = Pipeline.run(pipeline)

      assert result.context.value == 2
      assert result.status == :completed
      assert length(result.completed_steps) == 1
    end

    test "executes steps in dependency order" do
      pipeline =
        Pipeline.new(:test, context: %{log: []})
        |> Pipeline.add_step(:first, fn ctx ->
          {:ok, Map.update!(ctx, :log, &(&1 ++ [:first]))}
        end)
        |> Pipeline.add_step(
          :second,
          fn ctx -> {:ok, Map.update!(ctx, :log, &(&1 ++ [:second]))} end, depends_on: [:first])
        |> Pipeline.add_step(
          :third,
          fn ctx -> {:ok, Map.update!(ctx, :log, &(&1 ++ [:third]))} end, depends_on: [:second])

      {:ok, result} = Pipeline.run(pipeline)

      assert result.context.log == [:first, :second, :third]
      assert result.status == :completed
    end

    test "handles diamond dependency pattern" do
      # A -> B, A -> C, B -> D, C -> D
      pipeline =
        Pipeline.new(:test, context: %{log: []})
        |> Pipeline.add_step(:a, fn ctx -> {:ok, Map.update!(ctx, :log, &(&1 ++ [:a]))} end)
        |> Pipeline.add_step(:b, fn ctx -> {:ok, Map.update!(ctx, :log, &(&1 ++ [:b]))} end,
          depends_on: [:a]
        )
        |> Pipeline.add_step(:c, fn ctx -> {:ok, Map.update!(ctx, :log, &(&1 ++ [:c]))} end,
          depends_on: [:a]
        )
        |> Pipeline.add_step(:d, fn ctx -> {:ok, Map.update!(ctx, :log, &(&1 ++ [:d]))} end,
          depends_on: [:b, :c]
        )

      {:ok, result} = Pipeline.run(pipeline)

      # A must be first, D must be last
      assert hd(result.context.log) == :a
      assert List.last(result.context.log) == :d
      # B and C can be in any order but both must appear
      assert :b in result.context.log
      assert :c in result.context.log
    end

    test "handles step failure" do
      pipeline =
        Pipeline.new(:test)
        |> Pipeline.add_step(:good, fn ctx -> {:ok, ctx} end)
        |> Pipeline.add_step(:bad, fn _ctx -> {:error, "something went wrong"} end,
          depends_on: [:good]
        )
        |> Pipeline.add_step(:unreached, fn ctx -> {:ok, ctx} end, depends_on: [:bad])

      {:error, result} = Pipeline.run(pipeline)

      assert result.status == :failed
      assert result.failed_step == :bad
      assert result.error == "something went wrong"
      assert :good in result.completed_steps
      refute :unreached in result.completed_steps
    end

    test "handles step that raises exception" do
      pipeline =
        Pipeline.new(:test)
        |> Pipeline.add_step(:raise_step, fn _ctx -> raise "unexpected error" end)

      {:error, result} = Pipeline.run(pipeline)

      assert result.status == :failed
      assert result.failed_step == :raise_step
      assert result.error =~ "unexpected error"
    end

    test "tracks step timing" do
      pipeline =
        Pipeline.new(:test)
        |> Pipeline.add_step(:slow, fn ctx ->
          Process.sleep(10)
          {:ok, ctx}
        end)

      {:ok, result} = Pipeline.run(pipeline)

      assert result.timing[:slow] >= 10
    end
  end

  describe "validate/1" do
    test "validates empty pipeline" do
      pipeline = Pipeline.new(:empty)
      assert Pipeline.validate(pipeline) == :ok
    end

    test "detects missing dependency" do
      pipeline =
        Pipeline.new(:test)
        |> Pipeline.add_step(:step1, fn ctx -> {:ok, ctx} end, depends_on: [:nonexistent])

      assert {:error, message} = Pipeline.validate(pipeline)
      assert message =~ "nonexistent"
    end

    test "detects circular dependency" do
      # Manually construct circular dependency
      pipeline = %Pipeline{
        name: :circular,
        steps: [
          %{name: :a, fun: &Function.identity/1, depends_on: [:b], parallel: false},
          %{name: :b, fun: &Function.identity/1, depends_on: [:a], parallel: false}
        ],
        context: %{}
      }

      assert {:error, message} = Pipeline.validate(pipeline)
      assert message =~ "Circular"
    end
  end

  describe "topological_sort/1" do
    test "sorts steps by dependencies" do
      pipeline =
        Pipeline.new(:test)
        |> Pipeline.add_step(:c, fn ctx -> {:ok, ctx} end, depends_on: [:b])
        |> Pipeline.add_step(:a, fn ctx -> {:ok, ctx} end)
        |> Pipeline.add_step(:b, fn ctx -> {:ok, ctx} end, depends_on: [:a])

      {:ok, sorted} = Pipeline.topological_sort(pipeline)
      names = Enum.map(sorted, & &1.name)

      assert names == [:a, :b, :c]
    end
  end

  describe "pipeline macro usage" do
    test "can be composed from multiple steps" do
      pipeline =
        Pipeline.new(:compose_test, context: %{numbers: []})
        |> Pipeline.add_step(:add_one, fn ctx ->
          {:ok, Map.update!(ctx, :numbers, &(&1 ++ [1]))}
        end)
        |> Pipeline.add_step(
          :add_two,
          fn ctx -> {:ok, Map.update!(ctx, :numbers, &(&1 ++ [2]))} end, depends_on: [:add_one])
        |> Pipeline.add_step(
          :add_three,
          fn ctx -> {:ok, Map.update!(ctx, :numbers, &(&1 ++ [3]))} end, depends_on: [:add_two])

      {:ok, result} = Pipeline.run(pipeline)

      assert result.context.numbers == [1, 2, 3]
    end
  end

  describe "parallel execution" do
    test "marks steps for parallel execution" do
      pipeline =
        Pipeline.new(:test, context: %{results: []})
        |> Pipeline.add_step(:a, fn ctx -> {:ok, ctx} end)
        |> Pipeline.add_step(:b, fn ctx -> {:ok, Map.update!(ctx, :results, &(&1 ++ [:b]))} end,
          depends_on: [:a],
          parallel: true
        )
        |> Pipeline.add_step(:c, fn ctx -> {:ok, Map.update!(ctx, :results, &(&1 ++ [:c]))} end,
          depends_on: [:a],
          parallel: true
        )
        |> Pipeline.add_step(:d, fn ctx -> {:ok, Map.update!(ctx, :results, &(&1 ++ [:d]))} end,
          depends_on: [:b, :c]
        )

      {:ok, result} = Pipeline.run(pipeline)

      # D should be last
      assert List.last(result.context.results) == :d
      # B and C should both run (order may vary)
      assert :b in result.context.results
      assert :c in result.context.results
    end
  end
end
