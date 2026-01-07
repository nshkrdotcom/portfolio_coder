defmodule PortfolioCoder.Indexer.PipelineTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Indexer.Pipeline

  @test_dir "test/fixtures/pipeline_test"

  setup do
    # Create test directory with sample files
    File.mkdir_p!(@test_dir)

    File.write!(Path.join(@test_dir, "module_a.ex"), """
    defmodule ModuleA do
      def hello, do: "world"
    end
    """)

    File.write!(Path.join(@test_dir, "module_b.ex"), """
    defmodule ModuleB do
      alias ModuleA
      def greet, do: ModuleA.hello()
    end
    """)

    File.write!(Path.join(@test_dir, "script.py"), """
    def add(a, b):
        return a + b

    class Calculator:
        def multiply(self, x, y):
            return x * y
    """)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)

    {:ok, dir: @test_dir}
  end

  describe "new/1" do
    test "creates a new pipeline with default options" do
      pipeline = Pipeline.new()

      assert pipeline.concurrency == System.schedulers_online()
      assert pipeline.chunk_size == 1000
      assert pipeline.chunk_overlap == 200
      assert pipeline.batch_size == 50
    end

    test "creates a pipeline with custom options" do
      pipeline =
        Pipeline.new(
          concurrency: 4,
          chunk_size: 500,
          chunk_overlap: 100,
          batch_size: 25
        )

      assert pipeline.concurrency == 4
      assert pipeline.chunk_size == 500
      assert pipeline.chunk_overlap == 100
      assert pipeline.batch_size == 25
    end
  end

  describe "add_source/3" do
    test "adds a directory source", %{dir: dir} do
      pipeline =
        Pipeline.new()
        |> Pipeline.add_source(:directory, dir)

      assert length(pipeline.sources) == 1
      assert {:directory, ^dir, _opts} = hd(pipeline.sources)
    end

    test "adds a file list source" do
      files = ["file1.ex", "file2.ex"]

      pipeline =
        Pipeline.new()
        |> Pipeline.add_source(:files, files)

      assert length(pipeline.sources) == 1
      assert {:files, ^files, _opts} = hd(pipeline.sources)
    end

    test "adds multiple sources" do
      pipeline =
        Pipeline.new()
        |> Pipeline.add_source(:directory, "/path/a")
        |> Pipeline.add_source(:directory, "/path/b")

      assert length(pipeline.sources) == 2
    end
  end

  describe "add_step/3" do
    test "adds a parse step" do
      pipeline =
        Pipeline.new()
        |> Pipeline.add_step(:parse, [])

      assert :parse in pipeline.steps
    end

    test "adds a chunk step" do
      pipeline =
        Pipeline.new()
        |> Pipeline.add_step(:chunk, [])

      assert :chunk in pipeline.steps
    end

    test "adds a custom step" do
      custom_fn = fn item -> {:ok, item} end

      pipeline =
        Pipeline.new()
        |> Pipeline.add_step(:custom, custom_fn)

      assert length(pipeline.steps) == 1
      assert match?([{:custom, _}], pipeline.steps)
    end

    test "adds multiple steps in order" do
      pipeline =
        Pipeline.new()
        |> Pipeline.add_step(:parse, [])
        |> Pipeline.add_step(:chunk, [])
        |> Pipeline.add_step(:embed, [])

      assert pipeline.steps == [:parse, :chunk, :embed]
    end
  end

  describe "run/1" do
    test "runs pipeline on directory source", %{dir: dir} do
      {:ok, result} =
        Pipeline.new()
        |> Pipeline.add_source(:directory, dir, extensions: [".ex", ".py"])
        |> Pipeline.add_step(:parse, [])
        |> Pipeline.add_step(:chunk, [])
        |> Pipeline.run()

      assert result.files_processed >= 2
      assert result.chunks_created > 0
      assert result.errors == []
    end

    test "collects statistics during run", %{dir: dir} do
      {:ok, result} =
        Pipeline.new()
        |> Pipeline.add_source(:directory, dir, extensions: [".ex"])
        |> Pipeline.add_step(:parse, [])
        |> Pipeline.run()

      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
      assert is_map(result.stats)
    end

    test "handles empty sources gracefully" do
      {:ok, result} =
        Pipeline.new()
        |> Pipeline.add_source(:directory, "/nonexistent/path")
        |> Pipeline.add_step(:parse, [])
        |> Pipeline.run()

      assert result.files_processed == 0
    end

    test "handles errors in steps", %{dir: dir} do
      failing_step = fn _item -> {:error, :intentional_failure} end

      {:ok, result} =
        Pipeline.new()
        |> Pipeline.add_source(:directory, dir, extensions: [".ex"])
        |> Pipeline.add_step(:custom, failing_step)
        |> Pipeline.run()

      assert result.errors != []
    end
  end

  describe "run_async/1" do
    test "runs pipeline asynchronously", %{dir: dir} do
      {:ok, task} =
        Pipeline.new()
        |> Pipeline.add_source(:directory, dir, extensions: [".ex"])
        |> Pipeline.add_step(:parse, [])
        |> Pipeline.run_async()

      assert is_struct(task, Task)

      {:ok, result} = Task.await(task, 5000)
      assert result.files_processed >= 1
    end
  end

  describe "with_callback/2" do
    test "calls callback on each processed item", %{dir: dir} do
      test_pid = self()

      {:ok, _result} =
        Pipeline.new()
        |> Pipeline.add_source(:directory, dir, extensions: [".ex"])
        |> Pipeline.add_step(:parse, [])
        |> Pipeline.with_callback(fn item ->
          send(test_pid, {:processed, item.path})
        end)
        |> Pipeline.run()

      assert_receive {:processed, path}
      assert String.ends_with?(path, ".ex")
    end

    test "calls progress callback", %{dir: dir} do
      test_pid = self()

      {:ok, _result} =
        Pipeline.new()
        |> Pipeline.add_source(:directory, dir, extensions: [".ex"])
        |> Pipeline.add_step(:parse, [])
        |> Pipeline.with_progress(fn current, total ->
          send(test_pid, {:progress, current, total})
        end)
        |> Pipeline.run()

      assert_receive {:progress, _, total}
      assert total >= 1
    end
  end

  describe "standard pipeline configurations" do
    test "indexing pipeline processes files end-to-end", %{dir: dir} do
      {:ok, result} =
        Pipeline.indexing_pipeline()
        |> Pipeline.add_source(:directory, dir, extensions: [".ex", ".py"])
        |> Pipeline.run()

      assert result.files_processed >= 2
      assert result.chunks_created > 0
    end

    test "parsing pipeline extracts code structure", %{dir: dir} do
      {:ok, result} =
        Pipeline.parsing_pipeline()
        |> Pipeline.add_source(:directory, dir, extensions: [".ex"])
        |> Pipeline.run()

      assert result.files_processed >= 1
      # Should have parsed some symbols (stats tracked)
      assert is_map(result.stats)
      assert Map.has_key?(result.stats, :modules_found)
      assert Map.has_key?(result.stats, :functions_found)
    end
  end
end
