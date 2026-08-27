defmodule PortfolioCoder.Indexer do
  @moduledoc """
  Repository indexing for code intelligence.

  Scans repositories for source files, parses them using language-specific
  parsers, chunks the content, and stores embeddings via portfolio_manager.
  """

  alias PortfolioIndex.Pipelines.Ingestion
  alias PortfolioManager.RAG

  require Logger

  @default_exclude [
    "deps/",
    "_build/",
    "node_modules/",
    ".git/",
    ".elixir_ls/",
    "cover/",
    "doc/",
    "priv/plts/",
    "__pycache__/",
    ".pytest_cache/",
    "*.min.js",
    "*.map",
    "*.beam"
  ]

  @doc """
  Index a code repository.

  ## Options

    - `:index_id` - Name of the index (default: "default")
    - `:languages` - List of languages to index (default: all supported)
    - `:exclude` - Patterns to exclude
    - `:chunk_size` - Size of text chunks (default: 1000)
    - `:chunk_overlap` - Overlap between chunks (default: 200)
  """
  @spec index_repo(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def index_repo(repo_path, opts \\ []) do
    repo_path = Path.expand(repo_path)

    if File.dir?(repo_path) do
      do_index_repo(repo_path, opts)
    else
      {:error, {:not_a_directory, repo_path}}
    end
  end

  defp do_index_repo(repo_path, opts) do
    index_id = Keyword.get(opts, :index_id, default_index())
    languages = Keyword.get(opts, :languages, supported_languages())
    exclude = Keyword.get(opts, :exclude, @default_exclude)

    Logger.info("Indexing repository: #{repo_path}")
    Logger.info("Languages: #{inspect(languages)}, Index: #{index_id}")

    files = scan_files(repo_path, languages, exclude)
    Logger.info("Found #{length(files)} files to index")

    case RAG.index_repo(repo_path, Keyword.merge(opts, index_id: index_id)) do
      {:ok, _} ->
        {:ok,
         %{
           files_indexed: length(files),
           index_id: index_id,
           repo_path: repo_path,
           languages: languages
         }}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Index specific files.

  Uses `PortfolioIndex.Pipelines.Ingestion.enqueue/2` for each file and
  ensures the vector index exists via `PortfolioManager.RAG.index_repo/2`.
  """
  @spec index_files([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def index_files(file_paths, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, default_index())

    files =
      file_paths
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(fn path ->
        %{
          path: Path.expand(path),
          type: detect_language(path)
        }
      end)

    enqueue_files(files, index_id, opts)
  end

  @doc """
  Scan a repository for source files.
  """
  @spec scan_files(String.t(), [atom()], [String.t()]) :: [map()]
  def scan_files(repo_path, languages, exclude) do
    extensions = languages_to_extensions(languages)

    repo_path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(fn path ->
      File.regular?(path) and
        has_extension?(path, extensions) and
        not excluded?(path, exclude)
    end)
    |> Enum.map(fn path ->
      language = detect_language(path)

      %{
        path: path,
        type: language,
        relative_path: Path.relative_to(path, repo_path)
      }
    end)
  end

  @extension_to_language %{
    ".ex" => :elixir,
    ".exs" => :elixir,
    ".py" => :python,
    ".pyw" => :python,
    ".js" => :javascript,
    ".jsx" => :javascript,
    ".mjs" => :javascript,
    ".ts" => :typescript,
    ".tsx" => :typescript,
    ".md" => :markdown,
    ".txt" => :text,
    ".json" => :json,
    ".yml" => :yaml,
    ".yaml" => :yaml
  }

  @doc """
  Detect the programming language from a file path.
  """
  @spec detect_language(String.t()) :: atom()
  def detect_language(path) do
    ext = Path.extname(path) |> String.downcase()
    Map.get(@extension_to_language, ext, :unknown)
  end

  # Private functions

  defp enqueue_files(files, index_id, opts) do
    files = Enum.filter(files, &(&1.type != :unknown))

    case files do
      [] ->
        {:error, :no_indexable_files}

      [first | _] ->
        repo_root = Path.dirname(first.path)

        # Ensure the vector index exists without enqueueing repo-wide files.
        _ =
          RAG.index_repo(
            repo_root,
            Keyword.merge(opts,
              index_id: index_id,
              extensions: []
            )
          )

        counts =
          Enum.map(files, fn file ->
            Ingestion.enqueue(file,
              index_id: index_id,
              chunk_size: Keyword.get(opts, :chunk_size, 1000),
              chunk_overlap: Keyword.get(opts, :chunk_overlap, 200)
            )
          end)

        {:ok, %{files_indexed: length(files), index_id: index_id, queued: counts}}
    end
  end

  # Parsing helpers removed: explicit file indexing relies on ingestion pipeline.

  defp has_extension?(path, extensions) do
    ext = Path.extname(path) |> String.downcase()
    ext in extensions
  end

  defp excluded?(path, exclude_patterns) do
    Enum.any?(exclude_patterns, fn pattern ->
      String.contains?(path, pattern) or
        Path.basename(path) == pattern or
        match_glob?(path, pattern)
    end)
  end

  defp match_glob?(path, pattern) do
    if String.contains?(pattern, "*") do
      regex =
        pattern
        |> Regex.escape()
        |> String.replace("\\*", ".*")

      Regex.match?(~r/#{regex}/, Path.basename(path))
    else
      false
    end
  end

  defp languages_to_extensions(languages) do
    Enum.flat_map(languages, fn lang ->
      case lang do
        :elixir -> [".ex", ".exs"]
        :python -> [".py", ".pyw"]
        :javascript -> [".js", ".jsx", ".mjs"]
        :typescript -> [".ts", ".tsx"]
        :markdown -> [".md"]
        _ -> []
      end
    end)
  end

  defp supported_languages do
    Application.get_env(:portfolio_coder, :supported_languages, [:elixir, :python, :javascript])
  end

  defp default_index do
    Application.get_env(:portfolio_coder, :default_index, "default")
  end
end
