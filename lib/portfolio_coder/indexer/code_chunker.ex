defmodule PortfolioCoder.Indexer.CodeChunker do
  @moduledoc """
  Code-aware chunking that preserves semantic boundaries.

  This module provides intelligent chunking of source code that respects
  code structure (functions, classes, modules) rather than arbitrary
  character boundaries.

  ## Chunking Strategies

  - `:function` - Chunk at function/method boundaries
  - `:class` - Chunk at class/module boundaries
  - `:module` - Chunk at module level (Elixir)
  - `:hybrid` - Combine structure-aware and size-based chunking

  ## Usage

      # Chunk a file by function boundaries
      {:ok, chunks} = CodeChunker.chunk_file("lib/my_module.ex", strategy: :function)

      # Chunk with custom size limits
      {:ok, chunks} = CodeChunker.chunk_file("lib/my_module.ex",
        strategy: :hybrid,
        chunk_size: 1500,
        chunk_overlap: 200
      )
  """

  alias PortfolioCoder.Indexer.Parser

  @type chunk :: %{
          content: String.t(),
          start_line: non_neg_integer(),
          end_line: non_neg_integer(),
          type: :function | :class | :module | :section,
          name: String.t() | nil,
          metadata: map()
        }

  @type chunk_strategy :: :function | :class | :module | :hybrid | :lines

  @default_chunk_size 1500
  @default_chunk_overlap 200

  @doc """
  Chunk a source file using the specified strategy.

  ## Options

    - `:strategy` - Chunking strategy (default: `:hybrid`)
    - `:chunk_size` - Target chunk size in characters (default: 1500)
    - `:chunk_overlap` - Overlap between chunks (default: 200)
    - `:language` - Force language detection

  ## Returns

    - `{:ok, [chunk()]}` on success
    - `{:error, reason}` on failure
  """
  @spec chunk_file(String.t(), keyword()) :: {:ok, [chunk()]} | {:error, term()}
  def chunk_file(path, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :hybrid)
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    chunk_overlap = Keyword.get(opts, :chunk_overlap, @default_chunk_overlap)

    with {:ok, content} <- File.read(path),
         {:ok, parsed} <- Parser.parse(path, opts[:language]) do
      chunks =
        case strategy do
          :function ->
            chunk_by_functions(content, parsed)

          :class ->
            chunk_by_classes(content, parsed)

          :module ->
            chunk_by_modules(content, parsed)

          :hybrid ->
            chunk_hybrid(content, parsed, chunk_size, chunk_overlap)

          :lines ->
            chunk_by_lines(content, chunk_size, chunk_overlap)
        end

      {:ok, chunks}
    end
  end

  @doc """
  Chunk source content directly.

  ## Options

    Same as `chunk_file/2` plus:
    - `:language` - Required. The language of the content.
  """
  @spec chunk_content(String.t(), keyword()) :: {:ok, [chunk()]} | {:error, term()}
  def chunk_content(content, opts) do
    language = Keyword.fetch!(opts, :language)
    strategy = Keyword.get(opts, :strategy, :hybrid)
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    chunk_overlap = Keyword.get(opts, :chunk_overlap, @default_chunk_overlap)

    case Parser.parse_string(content, language) do
      {:ok, parsed} ->
        chunks =
          case strategy do
            :function ->
              chunk_by_functions(content, parsed)

            :class ->
              chunk_by_classes(content, parsed)

            :module ->
              chunk_by_modules(content, parsed)

            :hybrid ->
              chunk_hybrid(content, parsed, chunk_size, chunk_overlap)

            :lines ->
              chunk_by_lines(content, chunk_size, chunk_overlap)
          end

        {:ok, chunks}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Chunk content by symbols extracted from parsing.

  Creates one chunk per symbol (function, class, etc.).
  """
  @spec chunk_by_symbol(String.t(), [map()]) :: [chunk()]
  def chunk_by_symbol(content, symbols) do
    lines = String.split(content, "\n")
    sorted_symbols = Enum.sort_by(symbols, & &1.line)

    # Create chunks for each symbol
    sorted_symbols
    |> Enum.with_index()
    |> Enum.map(fn {symbol, idx} ->
      start_line = symbol.line
      # End line is either the next symbol's line - 1 or the end of file
      end_line =
        case Enum.at(sorted_symbols, idx + 1) do
          nil -> length(lines)
          next -> next.line - 1
        end

      chunk_content =
        lines
        |> Enum.slice((start_line - 1)..(end_line - 1))
        |> Enum.join("\n")

      %{
        content: chunk_content,
        start_line: start_line,
        end_line: end_line,
        type: symbol.type,
        name: symbol.name,
        metadata: %{
          visibility: symbol.visibility,
          arity: symbol.arity
        }
      }
    end)
  end

  # Private implementation functions

  defp chunk_by_functions(content, parsed) do
    functions =
      parsed.symbols
      |> Enum.filter(&(&1.type in [:function, :method]))

    if Enum.empty?(functions) do
      # Fall back to simple chunking if no functions found
      [create_full_chunk(content)]
    else
      chunk_by_symbol(content, functions)
    end
  end

  defp chunk_by_classes(content, parsed) do
    classes =
      parsed.symbols
      |> Enum.filter(&(&1.type in [:class, :module]))

    if Enum.empty?(classes) do
      [create_full_chunk(content)]
    else
      chunk_by_symbol(content, classes)
    end
  end

  defp chunk_by_modules(content, parsed) do
    modules =
      parsed.symbols
      |> Enum.filter(&(&1.type == :module))

    if Enum.empty?(modules) do
      [create_full_chunk(content)]
    else
      chunk_by_symbol(content, modules)
    end
  end

  defp chunk_hybrid(content, parsed, chunk_size, chunk_overlap) do
    # First, try to chunk by semantic boundaries (functions/classes)
    semantic_chunks =
      parsed.symbols
      |> Enum.filter(&(&1.type in [:function, :method, :class, :module]))
      |> then(&chunk_by_symbol(content, &1))

    # Then, split any chunks that are too large
    semantic_chunks
    |> Enum.flat_map(fn chunk ->
      if String.length(chunk.content) > chunk_size * 2 do
        # Split large chunks
        split_chunk(chunk, chunk_size, chunk_overlap)
      else
        [chunk]
      end
    end)
    |> case do
      [] -> chunk_by_lines(content, chunk_size, chunk_overlap)
      chunks -> chunks
    end
  end

  defp chunk_by_lines(content, chunk_size, chunk_overlap) do
    lines = String.split(content, "\n")
    total_lines = length(lines)

    if total_lines == 0 do
      []
    else
      create_line_chunks(lines, chunk_size, chunk_overlap)
    end
  end

  defp create_line_chunks(lines, chunk_size, overlap) do
    total_lines = length(lines)
    chunk_line_count = div(chunk_size, 60)
    overlap_lines = div(overlap, 60)

    create_line_chunks(lines, 1, chunk_line_count, overlap_lines, total_lines, [])
  end

  defp create_line_chunks(_lines, start, _chunk_lines, _overlap, total, acc)
       when start > total do
    Enum.reverse(acc)
  end

  defp create_line_chunks(lines, start, chunk_lines, overlap, total, acc) do
    end_line = min(start + chunk_lines - 1, total)

    chunk_content =
      lines
      |> Enum.slice((start - 1)..(end_line - 1))
      |> Enum.join("\n")

    chunk = %{
      content: chunk_content,
      start_line: start,
      end_line: end_line,
      type: :section,
      name: nil,
      metadata: %{}
    }

    next_start = max(start + 1, end_line - overlap + 1)
    create_line_chunks(lines, next_start, chunk_lines, overlap, total, [chunk | acc])
  end

  defp split_chunk(chunk, chunk_size, overlap) do
    lines = String.split(chunk.content, "\n")
    line_chunks = create_line_chunks(lines, chunk_size, overlap)

    Enum.map(line_chunks, fn lc ->
      %{lc | type: chunk.type, name: chunk.name}
    end)
  end

  defp create_full_chunk(content) do
    lines = String.split(content, "\n")

    %{
      content: content,
      start_line: 1,
      end_line: length(lines),
      type: :section,
      name: nil,
      metadata: %{}
    }
  end
end
