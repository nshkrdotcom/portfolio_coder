defmodule PortfolioCoder.Indexer do
  @moduledoc """
  Repository indexing for code intelligence.

  Scans repositories for source files, parses them using language-specific
  parsers, chunks the content, and stores embeddings via portfolio_manager.
  """

  alias PortfolioCoder.Parsers
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

    # Use portfolio_manager's RAG.index_repo with our file list
    case index_files_via_rag(files, index_id, opts) do
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
          type: detect_language(path),
          content: File.read!(path)
        }
      end)

    case index_files_via_rag(files, index_id, opts) do
      {:ok, _} ->
        {:ok, %{files_indexed: length(files), index_id: index_id}}

      {:error, _} = err ->
        err
    end
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

  defp index_files_via_rag(files, index_id, opts) do
    # Process files and prepare for indexing
    processed =
      files
      |> Enum.filter(&(&1.type != :unknown))
      |> Enum.map(fn file ->
        content =
          case Map.get(file, :content) do
            nil -> File.read!(file.path)
            c -> c
          end

        # Parse and extract structure if possible
        parsed = parse_file(content, file.type)

        %{
          path: file.path,
          content: content,
          type: file.type,
          metadata: %{
            language: file.type,
            path: file.path,
            relative_path: Map.get(file, :relative_path, file.path),
            parsed: parsed
          }
        }
      end)

    # Delegate to portfolio_manager for actual indexing
    # Use the generic ingestion interface
    extensions = Keyword.get(opts, :extensions, language_extensions())

    RAG.index_repo(
      List.first(processed)[:path] |> Path.dirname(),
      Keyword.merge(opts,
        index_id: index_id,
        extensions: extensions
      )
    )
  end

  defp parse_file(content, :elixir) do
    case Parsers.Elixir.parse(content) do
      {:ok, result} -> result
      {:error, _} -> nil
    end
  end

  defp parse_file(content, :python) do
    case Parsers.Python.parse(content) do
      {:ok, result} -> result
      {:error, _} -> nil
    end
  end

  defp parse_file(content, :javascript) do
    case Parsers.JavaScript.parse(content) do
      {:ok, result} -> result
      {:error, _} -> nil
    end
  end

  defp parse_file(content, :typescript) do
    case Parsers.JavaScript.parse(content) do
      {:ok, result} -> result
      {:error, _} -> nil
    end
  end

  defp parse_file(_content, _type), do: nil

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

  defp language_extensions do
    [".ex", ".exs", ".py", ".js", ".ts", ".md", ".txt"]
  end

  defp supported_languages do
    Application.get_env(:portfolio_coder, :supported_languages, [:elixir, :python, :javascript])
  end

  defp default_index do
    Application.get_env(:portfolio_coder, :default_index, "default")
  end
end
