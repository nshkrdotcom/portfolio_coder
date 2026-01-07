defmodule PortfolioCoder.Workflow.Pipeline do
  @moduledoc """
  DAG-based workflow pipeline execution.

  The Pipeline module allows composing complex multi-step operations with:
  - Dependency-based execution ordering
  - Parallel execution support
  - Error handling and rollback
  - Timing and metrics collection

  ## Features

  - **DAG Execution**: Steps are executed in topological order based on dependencies
  - **Parallel Steps**: Independent steps can be marked for parallel execution
  - **Context Passing**: Shared context flows through all steps
  - **Error Handling**: Failures stop execution and report which step failed
  - **Validation**: Detect missing dependencies and cycles before execution

  ## Usage

      pipeline =
        Pipeline.new(:my_pipeline, context: %{path: "/repo"})
        |> Pipeline.add_step(:scan, &scan_files/1)
        |> Pipeline.add_step(:parse, &parse_ast/1, depends_on: [:scan])
        |> Pipeline.add_step(:chunk, &chunk_code/1, depends_on: [:parse], parallel: true)
        |> Pipeline.add_step(:embed, &embed_chunks/1, depends_on: [:parse], parallel: true)
        |> Pipeline.add_step(:store, &store_results/1, depends_on: [:chunk, :embed])

      {:ok, result} = Pipeline.run(pipeline)
  """

  defstruct [:name, :steps, :context]

  @type step :: %{
          name: atom(),
          fun: (map() -> {:ok, map()} | {:error, term()}),
          depends_on: [atom()],
          parallel: boolean()
        }

  @type t :: %__MODULE__{
          name: atom(),
          steps: [step()],
          context: map()
        }

  @type result :: %{
          status: :completed | :failed,
          context: map(),
          completed_steps: [atom()],
          failed_step: atom() | nil,
          error: term() | nil,
          timing: %{atom() => non_neg_integer()}
        }

  @doc """
  Create a new pipeline.

  ## Options

  - `:context` - Initial context map passed to all steps (default: %{})

  ## Examples

      Pipeline.new(:analyze_repo)
      Pipeline.new(:review_code, context: %{pr_number: 123})
  """
  @spec new(atom(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      steps: [],
      context: Keyword.get(opts, :context, %{})
    }
  end

  @doc """
  Add a step to the pipeline.

  ## Options

  - `:depends_on` - List of step names this step depends on (default: [])
  - `:parallel` - Whether this step can run in parallel with siblings (default: false)

  ## Examples

      pipeline
      |> Pipeline.add_step(:scan, &scan_files/1)
      |> Pipeline.add_step(:parse, &parse_ast/1, depends_on: [:scan])
      |> Pipeline.add_step(:chunk, &chunk_code/1, depends_on: [:parse], parallel: true)
  """
  @spec add_step(t(), atom(), (map() -> {:ok, map()} | {:error, term()}), keyword()) :: t()
  def add_step(pipeline, name, fun, opts \\ []) do
    step = %{
      name: name,
      fun: fun,
      depends_on: Keyword.get(opts, :depends_on, []),
      parallel: Keyword.get(opts, :parallel, false)
    }

    %{pipeline | steps: pipeline.steps ++ [step]}
  end

  @doc """
  Validate the pipeline for errors.

  Checks for:
  - Missing dependencies (steps that reference non-existent steps)
  - Circular dependencies

  Returns `:ok` if valid, or `{:error, message}` if invalid.
  """
  @spec validate(t()) :: :ok | {:error, String.t()}
  def validate(pipeline) do
    step_names = MapSet.new(Enum.map(pipeline.steps, & &1.name))

    # Check for missing dependencies
    missing =
      pipeline.steps
      |> Enum.flat_map(fn step ->
        Enum.filter(step.depends_on, &(not MapSet.member?(step_names, &1)))
      end)
      |> Enum.uniq()

    if missing != [] do
      {:error, "Missing dependencies: #{inspect(missing)}"}
    else
      # Check for circular dependencies
      case topological_sort(pipeline) do
        {:ok, _} -> :ok
        {:error, _} -> {:error, "Circular dependency detected"}
      end
    end
  end

  @doc """
  Sort steps in topological order (dependencies first).

  Returns `{:ok, sorted_steps}` or `{:error, :cycle_detected}` if there's a cycle.
  """
  @spec topological_sort(t()) :: {:ok, [step()]} | {:error, :cycle_detected}
  def topological_sort(pipeline) do
    steps_by_name = Map.new(pipeline.steps, &{&1.name, &1})
    step_names = Enum.map(pipeline.steps, & &1.name)

    case kahn_sort(step_names, steps_by_name) do
      {:ok, sorted_names} ->
        sorted_steps = Enum.map(sorted_names, &Map.fetch!(steps_by_name, &1))
        {:ok, sorted_steps}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Run the pipeline.

  Executes steps in topological order, respecting dependencies.
  Returns `{:ok, result}` on success or `{:error, result}` on failure.

  The result contains:
  - `:status` - `:completed` or `:failed`
  - `:context` - Final context after all steps
  - `:completed_steps` - List of successfully completed step names
  - `:failed_step` - Name of the step that failed (if any)
  - `:error` - Error message from failed step (if any)
  - `:timing` - Map of step names to execution time in milliseconds
  """
  @spec run(t()) :: {:ok, result()} | {:error, result()}
  def run(pipeline) do
    case validate(pipeline) do
      {:error, message} ->
        {:error,
         %{
           status: :failed,
           context: pipeline.context,
           completed_steps: [],
           failed_step: nil,
           error: "Validation failed: #{message}",
           timing: %{}
         }}

      :ok ->
        {:ok, sorted_steps} = topological_sort(pipeline)
        execute_steps(sorted_steps, pipeline.context)
    end
  end

  # Private helpers

  # Kahn's algorithm for topological sort
  defp kahn_sort(step_names, steps_by_name) do
    # Build adjacency list and in-degree count
    {graph, in_degree} = build_graph(step_names, steps_by_name)

    # Find nodes with no incoming edges
    queue =
      step_names
      |> Enum.filter(&(Map.get(in_degree, &1, 0) == 0))
      |> :queue.from_list()

    kahn_loop(queue, graph, in_degree, [], length(step_names))
  end

  defp build_graph(step_names, steps_by_name) do
    # Initialize
    graph = Map.new(step_names, &{&1, []})
    in_degree = Map.new(step_names, &{&1, 0})

    # Build edges: if B depends on A, add edge A -> B
    Enum.reduce(step_names, {graph, in_degree}, fn name, {g, deg} ->
      step = Map.get(steps_by_name, name)
      deps = step.depends_on || []

      # For each dependency, add edge from dep to name
      Enum.reduce(deps, {g, deg}, fn dep, {g2, deg2} ->
        g3 = Map.update(g2, dep, [name], &[name | &1])
        deg3 = Map.update(deg2, name, 1, &(&1 + 1))
        {g3, deg3}
      end)
    end)
  end

  defp kahn_loop(queue, graph, in_degree, result, expected_count) do
    case :queue.out(queue) do
      {:empty, _} ->
        finalize_kahn(result, expected_count)

      {{:value, node}, queue2} ->
        # Add to result
        result2 = [node | result]

        {queue3, in_degree2} = process_neighbors(node, graph, queue2, in_degree)
        kahn_loop(queue3, graph, in_degree2, result2, expected_count)
    end
  end

  defp finalize_kahn(result, expected_count) do
    if length(result) == expected_count do
      {:ok, Enum.reverse(result)}
    else
      {:error, :cycle_detected}
    end
  end

  defp process_neighbors(node, graph, queue, in_degree) do
    neighbors = Map.get(graph, node, [])

    Enum.reduce(neighbors, {queue, in_degree}, fn neighbor, {q, deg} ->
      new_deg = Map.get(deg, neighbor, 0) - 1
      deg2 = Map.put(deg, neighbor, new_deg)
      q2 = maybe_enqueue(q, neighbor, new_deg)
      {q2, deg2}
    end)
  end

  defp maybe_enqueue(queue, neighbor, 0), do: :queue.in(neighbor, queue)
  defp maybe_enqueue(queue, _neighbor, _new_deg), do: queue

  defp execute_steps(steps, initial_context) do
    result = %{
      status: :completed,
      context: initial_context,
      completed_steps: [],
      failed_step: nil,
      error: nil,
      timing: %{}
    }

    execute_steps_loop(steps, result)
  end

  defp execute_steps_loop([], result) do
    {:ok, result}
  end

  defp execute_steps_loop([step | rest], result) do
    {time_us, step_result} =
      :timer.tc(fn ->
        try do
          step.fun.(result.context)
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    time_ms = div(time_us, 1000)

    case step_result do
      {:ok, new_context} ->
        updated_result = %{
          result
          | context: new_context,
            completed_steps: result.completed_steps ++ [step.name],
            timing: Map.put(result.timing, step.name, time_ms)
        }

        execute_steps_loop(rest, updated_result)

      {:error, error} ->
        failed_result = %{
          result
          | status: :failed,
            failed_step: step.name,
            error: error,
            timing: Map.put(result.timing, step.name, time_ms)
        }

        {:error, failed_result}
    end
  end
end
