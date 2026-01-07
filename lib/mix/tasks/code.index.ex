defmodule Mix.Tasks.Code.Index do
  @moduledoc """
  Index a code repository for code search.

  Uses in-memory indexing with TF-IDF scoring for fast code search.
  The index persists for the duration of the application.

  ## Usage

      mix code.index PATH [OPTIONS]

  ## Options

    * `--index` - Name of the index (default: "default")
    * `--languages` - Comma-separated list of languages to index
    * `--exclude` - Comma-separated patterns to exclude
    * `--chunk-size` - Size of code chunks (default: 800)

  ## Examples

      mix code.index ./my_project
      mix code.index ./my_project --index my_project
      mix code.index ./my_project --languages elixir,python
      mix code.index ./my_project --exclude "test/,docs/"

  """
  use Mix.Task

  alias PortfolioCoder.Indexer.CodeChunker
  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.Indexer.Parser

  @shortdoc "Index a code repository"

  @default_exclude [
    "deps/",
    "_build/",
    "node_modules/",
    ".git/",
    ".elixir_ls/",
    "cover/",
    "priv/plts/"
  ]

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:portfolio_coder)

    {opts, paths, _} =
      OptionParser.parse(args,
        strict: [
          index: :string,
          languages: :string,
          exclude: :string,
          chunk_size: :integer,
          help: :boolean
        ],
        aliases: [i: :index, l: :languages, e: :exclude, c: :chunk_size, h: :help]
      )

    if opts[:help] do
      shell_info(@moduledoc)
    else
      path = List.first(paths) || "."
      index_repo(path, opts)
    end
  end

  defp index_repo(path, opts) do
    path = Path.expand(path)
    validate_repo_path!(path)
    shell_info("Indexing repository: #{path}")

    index_name = opts[:index] || "default"
    languages = parse_languages(opts[:languages]) || [:elixir, :python, :javascript]
    exclude = parse_list(opts[:exclude]) || @default_exclude
    chunk_size = opts[:chunk_size] || 800

    extensions = languages_to_extensions(languages)
    files = find_source_files(path, extensions, exclude)

    shell_info("Found #{length(files)} files to index")

    {:ok, index} = get_or_create_index(index_name)
    {files_indexed, chunks_created} = index_files(files, index, path, chunk_size)
    stats = InMemorySearch.stats(index)

    shell_info("""

    Indexing complete!
      Files indexed: #{files_indexed}
      Chunks created: #{chunks_created}
      Documents in index: #{stats.document_count}
      Unique terms: #{stats.term_count}
      Index name: #{index_name}
      Languages: #{inspect(languages)}
    """)
  end

  defp validate_repo_path!(path) do
    unless File.dir?(path) do
      shell_error("Error: #{path} is not a directory")
      exit({:shutdown, 1})
    end
  end

  defp find_source_files(path, extensions, exclude) do
    path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(fn file ->
      File.regular?(file) and
        has_extension?(file, extensions) and
        not excluded?(file, exclude)
    end)
    |> Enum.sort()
  end

  defp index_files(files, index, root_path, chunk_size) do
    Enum.reduce(files, {0, 0}, fn file, {file_count, chunk_count} ->
      case index_file(file, index, root_path, chunk_size) do
        {:ok, chunks_added} ->
          {file_count + 1, chunk_count + chunks_added}

        :skip ->
          {file_count, chunk_count}
      end
    end)
  end

  defp index_file(file, index, root_path, chunk_size) do
    case Parser.parse(file) do
      {:ok, parsed} ->
        {:ok, maybe_index_chunks(file, parsed, index, root_path, chunk_size)}

      {:error, _} ->
        :skip
    end
  end

  defp maybe_index_chunks(file, parsed, index, root_path, chunk_size) do
    case CodeChunker.chunk_file(file, strategy: :hybrid, chunk_size: chunk_size) do
      {:ok, chunks} ->
        docs = build_docs(file, root_path, parsed, chunks)
        InMemorySearch.add_all(index, docs)
        length(chunks)

      {:error, _} ->
        0
    end
  end

  defp build_docs(file, root_path, parsed, chunks) do
    relative_path = Path.relative_to(file, root_path)

    Enum.with_index(chunks)
    |> Enum.map(fn {chunk, idx} ->
      %{
        id: "#{relative_path}:#{idx}",
        content: chunk.content,
        metadata: %{
          path: file,
          relative_path: relative_path,
          language: parsed.language,
          type: chunk.type,
          name: chunk.name
        }
      }
    end)
  end

  defp get_or_create_index(name) do
    # Store index in persistent_term for cross-process access
    key = {:code_index, name}

    case :persistent_term.get(key, nil) do
      nil ->
        {:ok, index} = InMemorySearch.new()
        :persistent_term.put(key, index)
        {:ok, index}

      index ->
        {:ok, index}
    end
  end

  defp languages_to_extensions(languages) do
    Enum.flat_map(languages, fn lang ->
      case lang do
        :elixir -> [".ex", ".exs"]
        :python -> [".py"]
        :javascript -> [".js", ".jsx", ".mjs"]
        :typescript -> [".ts", ".tsx"]
        _ -> []
      end
    end)
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

  defp shell_info(message), do: IO.puts(message)
  defp shell_error(message), do: IO.puts(:stderr, message)

  defp parse_languages(nil), do: nil

  defp parse_languages(languages) do
    languages
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_atom/1)
  end

  defp parse_list(nil), do: nil

  defp parse_list(list) do
    list
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end
end
