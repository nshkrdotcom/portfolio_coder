defmodule PortfolioCoder.Indexer.Pipeline do
  @moduledoc """
  Concurrent indexing pipeline for processing code repositories.

  Provides a fluent API for building and running indexing pipelines with
  configurable concurrency, chunking, and processing steps.

  ## Example

      Pipeline.new(concurrency: 4)
      |> Pipeline.add_source(:directory, "./lib")
      |> Pipeline.add_step(:parse, [])
      |> Pipeline.add_step(:chunk, [])
      |> Pipeline.run()

  ## Pre-built Pipelines

      # Full indexing pipeline
      Pipeline.indexing_pipeline()
      |> Pipeline.add_source(:directory, repo_path)
      |> Pipeline.run()

      # Parsing-only pipeline
      Pipeline.parsing_pipeline()
      |> Pipeline.add_source(:directory, repo_path)
      |> Pipeline.run()
  """

  alias PortfolioCoder.Indexer.{CodeChunker, Parser}

  defstruct [
    :concurrency,
    :chunk_size,
    :chunk_overlap,
    :batch_size,
    :on_item_callback,
    :on_progress_callback,
    sources: [],
    steps: []
  ]

  @type t :: %__MODULE__{
          concurrency: pos_integer(),
          chunk_size: pos_integer(),
          chunk_overlap: non_neg_integer(),
          batch_size: pos_integer(),
          on_item_callback: (map() -> any()) | nil,
          on_progress_callback: (integer(), integer() -> any()) | nil,
          sources: [{atom(), term(), keyword()}],
          steps: [atom() | {atom(), function()}]
        }

  @type result :: %{
          files_processed: non_neg_integer(),
          chunks_created: non_neg_integer(),
          duration_ms: non_neg_integer(),
          errors: [term()],
          stats: map()
        }

  @doc """
  Create a new pipeline with the given options.

  ## Options

    * `:concurrency` - Number of parallel workers (default: schedulers_online)
    * `:chunk_size` - Size of text chunks in characters (default: 1000)
    * `:chunk_overlap` - Overlap between chunks (default: 200)
    * `:batch_size` - Number of items to batch together (default: 50)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      concurrency: Keyword.get(opts, :concurrency, System.schedulers_online()),
      chunk_size: Keyword.get(opts, :chunk_size, 1000),
      chunk_overlap: Keyword.get(opts, :chunk_overlap, 200),
      batch_size: Keyword.get(opts, :batch_size, 50),
      sources: [],
      steps: []
    }
  end

  @doc """
  Add a source to the pipeline.

  ## Source Types

    * `:directory` - Scan a directory for files
    * `:files` - Process a list of file paths

  ## Options (for :directory)

    * `:extensions` - List of file extensions to include
    * `:exclude` - Patterns to exclude
  """
  @spec add_source(t(), atom(), term(), keyword()) :: t()
  def add_source(%__MODULE__{} = pipeline, type, source, opts \\ []) do
    %{pipeline | sources: pipeline.sources ++ [{type, source, opts}]}
  end

  @doc """
  Add a processing step to the pipeline.

  ## Built-in Steps

    * `:parse` - Parse code to extract structure
    * `:chunk` - Split content into chunks
    * `:embed` - Generate embeddings (requires LLM adapter)

  ## Custom Steps

  You can pass a function as the opts to create a custom step:

      Pipeline.add_step(pipeline, :custom, fn item -> transform(item) end)
  """
  @spec add_step(t(), atom(), keyword() | function()) :: t()
  def add_step(pipeline, step, opts \\ [])

  def add_step(%__MODULE__{} = pipeline, step, opts) when is_function(opts) do
    %{pipeline | steps: pipeline.steps ++ [{step, opts}]}
  end

  def add_step(%__MODULE__{} = pipeline, step, _opts) when is_atom(step) do
    %{pipeline | steps: pipeline.steps ++ [step]}
  end

  @doc """
  Set a callback to be called for each processed item.
  """
  @spec with_callback(t(), (map() -> any())) :: t()
  def with_callback(%__MODULE__{} = pipeline, callback) when is_function(callback, 1) do
    %{pipeline | on_item_callback: callback}
  end

  @doc """
  Set a progress callback to track pipeline progress.
  """
  @spec with_progress(t(), (integer(), integer() -> any())) :: t()
  def with_progress(%__MODULE__{} = pipeline, callback) when is_function(callback, 2) do
    %{pipeline | on_progress_callback: callback}
  end

  @doc """
  Run the pipeline synchronously.
  """
  @spec run(t()) :: {:ok, result()} | {:error, term()}
  def run(%__MODULE__{} = pipeline) do
    start_time = System.monotonic_time(:millisecond)

    # Collect files from all sources
    files = collect_files(pipeline.sources)
    total = length(files)

    # Initialize stats
    stats = %{
      modules_found: 0,
      functions_found: 0,
      classes_found: 0
    }

    # Process files with concurrency
    {results, errors, final_stats} =
      process_files(files, pipeline, total, stats)

    # Count chunks
    chunks_created =
      results
      |> Enum.flat_map(fn item -> Map.get(item, :chunks, [item]) end)
      |> length()

    duration = System.monotonic_time(:millisecond) - start_time

    {:ok,
     %{
       files_processed: length(results),
       chunks_created: chunks_created,
       duration_ms: duration,
       errors: errors,
       stats: final_stats
     }}
  end

  @doc """
  Run the pipeline asynchronously, returning a Task.
  """
  @spec run_async(t()) :: {:ok, Task.t()}
  def run_async(%__MODULE__{} = pipeline) do
    task = Task.async(fn -> run(pipeline) end)
    {:ok, task}
  end

  @doc """
  Create a standard indexing pipeline with parse and chunk steps.
  """
  @spec indexing_pipeline(keyword()) :: t()
  def indexing_pipeline(opts \\ []) do
    new(opts)
    |> add_step(:parse, [])
    |> add_step(:chunk, [])
  end

  @doc """
  Create a parsing-only pipeline for code structure extraction.
  """
  @spec parsing_pipeline(keyword()) :: t()
  def parsing_pipeline(opts \\ []) do
    new(opts)
    |> add_step(:parse, [])
  end

  # Private functions

  defp collect_files(sources) do
    Enum.flat_map(sources, fn
      {:directory, path, opts} ->
        scan_directory(path, opts)

      {:files, files, _opts} ->
        files
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(fn path ->
          %{
            path: Path.expand(path),
            content: nil,
            type: detect_type(path)
          }
        end)
    end)
  end

  defp scan_directory(path, opts) do
    extensions = Keyword.get(opts, :extensions, [".ex", ".exs", ".py", ".js", ".ts"])
    exclude = Keyword.get(opts, :exclude, ["deps/", "_build/", "node_modules/"])

    if File.dir?(path) do
      path
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(fn file_path ->
        File.regular?(file_path) and
          has_extension?(file_path, extensions) and
          not excluded?(file_path, exclude)
      end)
      |> Enum.map(fn file_path ->
        %{
          path: file_path,
          content: nil,
          type: detect_type(file_path)
        }
      end)
    else
      []
    end
  end

  defp has_extension?(path, extensions) do
    ext = Path.extname(path) |> String.downcase()
    ext in extensions
  end

  defp excluded?(path, exclude_patterns) do
    Enum.any?(exclude_patterns, fn pattern ->
      String.contains?(path, pattern)
    end)
  end

  defp detect_type(path) do
    case Path.extname(path) |> String.downcase() do
      ext when ext in [".ex", ".exs"] -> :elixir
      ext when ext in [".py", ".pyw"] -> :python
      ext when ext in [".js", ".jsx", ".mjs"] -> :javascript
      ext when ext in [".ts", ".tsx"] -> :typescript
      ".md" -> :markdown
      _ -> :unknown
    end
  end

  defp process_files(files, pipeline, total, initial_stats) do
    counter = :atomics.new(1, signed: false)
    errors_agent = Agent.start_link(fn -> [] end) |> elem(1)
    stats_agent = Agent.start_link(fn -> initial_stats end) |> elem(1)

    results =
      files
      |> Task.async_stream(
        fn file ->
          process_single_file(file, pipeline, counter, total, errors_agent, stats_agent)
        end,
        max_concurrency: pipeline.concurrency,
        timeout: 30_000,
        on_timeout: :kill_task
      )
      |> Enum.flat_map(fn
        {:ok, {:ok, result}} -> [result]
        {:ok, {:error, _}} -> []
        {:exit, _} -> []
      end)

    errors = Agent.get(errors_agent, & &1)
    final_stats = Agent.get(stats_agent, & &1)

    Agent.stop(errors_agent)
    Agent.stop(stats_agent)

    {results, errors, final_stats}
  end

  defp process_single_file(file, pipeline, counter, total, errors_agent, stats_agent) do
    file = ensure_content(file)
    result = run_pipeline_steps(file, pipeline, errors_agent, stats_agent)

    current = :atomics.add_get(counter, 1, 1)
    maybe_report_progress(pipeline, current, total)

    finalize_result(pipeline, result)
  end

  defp ensure_content(file) do
    case file.content do
      nil -> %{file | content: File.read!(file.path)}
      _ -> file
    end
  end

  defp run_pipeline_steps(file, pipeline, errors_agent, stats_agent) do
    Enum.reduce_while(pipeline.steps, {:ok, file}, fn step, {:ok, item} ->
      case apply_step(step, item, pipeline) do
        {:ok, new_item} ->
          maybe_update_stats(step, new_item, stats_agent)
          {:cont, {:ok, new_item}}

        {:error, reason} ->
          record_error(errors_agent, item.path, reason)
          {:halt, {:error, reason}}
      end
    end)
  end

  defp maybe_update_stats(:parse, item, stats_agent), do: update_stats(stats_agent, item)
  defp maybe_update_stats(_step, _item, _stats_agent), do: :ok

  defp record_error(errors_agent, path, reason) do
    Agent.update(errors_agent, fn errors -> [{path, reason} | errors] end)
  end

  defp maybe_report_progress(pipeline, current, total) do
    if pipeline.on_progress_callback do
      pipeline.on_progress_callback.(current, total)
    end
  end

  defp finalize_result(pipeline, {:ok, item}) do
    if pipeline.on_item_callback do
      pipeline.on_item_callback.(item)
    end

    {:ok, item}
  end

  defp finalize_result(_pipeline, error), do: error

  defp apply_step(:parse, item, _pipeline) do
    case Parser.parse(item.content, item.type) do
      {:ok, parsed} ->
        {:ok, Map.put(item, :parsed, parsed)}

      {:error, reason} ->
        # Continue with unparsed content
        {:ok, Map.put(item, :parsed, nil) |> Map.put(:parse_error, reason)}
    end
  end

  defp apply_step(:chunk, item, pipeline) do
    case CodeChunker.chunk_content(item.content,
           language: item.type,
           chunk_size: pipeline.chunk_size,
           chunk_overlap: pipeline.chunk_overlap
         ) do
      {:ok, chunks} ->
        {:ok, Map.put(item, :chunks, chunks)}

      {:error, _reason} ->
        # Fallback to simple chunking on parse error
        simple_chunks = simple_chunk(item.content, pipeline.chunk_size, pipeline.chunk_overlap)
        {:ok, Map.put(item, :chunks, simple_chunks)}
    end
  end

  defp apply_step(:embed, item, _pipeline) do
    # Embedding step - would integrate with portfolio_index embedder
    # For now, just mark as ready for embedding
    {:ok, Map.put(item, :ready_for_embedding, true)}
  end

  defp apply_step({:custom, func}, item, _pipeline) when is_function(func, 1) do
    case func.(item) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      result when is_map(result) -> {:ok, result}
      _ -> {:error, :invalid_step_result}
    end
  end

  defp apply_step(_unknown, item, _pipeline) do
    {:ok, item}
  end

  defp update_stats(stats_agent, item) do
    parsed = Map.get(item, :parsed)

    if parsed do
      Agent.update(stats_agent, fn stats ->
        symbols = Map.get(parsed, :symbols, [])

        modules =
          symbols
          |> Enum.filter(&(&1.type == :module))
          |> length()

        functions =
          symbols
          |> Enum.filter(&(&1.type in [:function, :method]))
          |> length()

        classes =
          symbols
          |> Enum.filter(&(&1.type == :class))
          |> length()

        %{
          stats
          | modules_found: stats.modules_found + modules,
            functions_found: stats.functions_found + functions,
            classes_found: stats.classes_found + classes
        }
      end)
    end
  end

  defp simple_chunk(content, chunk_size, overlap) do
    content
    |> String.codepoints()
    |> Enum.chunk_every(chunk_size, max(1, chunk_size - overlap), [])
    |> Enum.with_index()
    |> Enum.map(fn {chars, idx} ->
      %{
        content: Enum.join(chars),
        start_line: idx * max(1, chunk_size - overlap) + 1,
        end_line: (idx + 1) * chunk_size,
        type: :section,
        name: nil,
        metadata: %{}
      }
    end)
  end
end
