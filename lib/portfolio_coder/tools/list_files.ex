defmodule PortfolioCoder.Tools.ListFiles do
  @moduledoc """
  File listing tool for agents.

  Lists files in a directory with filtering and metadata.
  """

  @max_results 500

  @default_exclude [
    "deps/",
    "_build/",
    "node_modules/",
    ".git/",
    ".elixir_ls/",
    "__pycache__/"
  ]

  @doc """
  Get the tool definition for agent registration.
  """
  @spec definition() :: map()
  def definition do
    %{
      name: "list_files",
      description: """
      List files in a directory. Supports filtering by extension,
      pattern matching, and recursive listing.
      """,
      parameters: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "The directory path to list"
          },
          pattern: %{
            type: "string",
            description: "Glob pattern to filter files (e.g., '*.ex', '**/*.py')"
          },
          extensions: %{
            type: "array",
            items: %{type: "string"},
            description: "Filter by file extensions (e.g., ['.ex', '.exs'])"
          },
          recursive: %{
            type: "boolean",
            description: "Recursively list subdirectories (default: true)",
            default: true
          },
          include_hidden: %{
            type: "boolean",
            description: "Include hidden files (default: false)",
            default: false
          },
          exclude: %{
            type: "array",
            items: %{type: "string"},
            description: "Patterns to exclude"
          }
        },
        required: ["path"]
      },
      handler: &__MODULE__.execute/1
    }
  end

  @doc """
  Execute the list_files tool.
  """
  @spec execute(map()) :: {:ok, map()} | {:error, term()}
  def execute(args) do
    path = Map.fetch!(args, "path")
    pattern = Map.get(args, "pattern")
    extensions = Map.get(args, "extensions", [])
    recursive = Map.get(args, "recursive", true)
    include_hidden = Map.get(args, "include_hidden", false)
    exclude = Map.get(args, "exclude", @default_exclude)

    with :ok <- validate_path(path) do
      files = list_directory(path, recursive, pattern, include_hidden)

      filtered =
        files
        |> filter_by_extensions(extensions)
        |> filter_hidden(include_hidden)
        |> filter_excluded(exclude)
        |> Enum.take(@max_results)
        |> Enum.map(&build_file_info(&1, path))

      {:ok,
       %{
         path: path,
         files: filtered,
         count: length(filtered),
         truncated: length(files) > @max_results
       }}
    end
  end

  defp validate_path(path) do
    expanded = Path.expand(path)

    cond do
      String.contains?(expanded, "..") and not File.exists?(expanded) ->
        {:error, :path_traversal_not_allowed}

      not File.exists?(path) ->
        {:error, :path_not_found}

      not File.dir?(path) ->
        {:error, :not_a_directory}

      true ->
        :ok
    end
  end

  defp list_directory(path, recursive, pattern, include_hidden) do
    glob_pattern =
      cond do
        pattern -> Path.join(path, pattern)
        recursive -> Path.join(path, "**/*")
        true -> Path.join(path, "*")
      end

    opts = if include_hidden, do: [match_dot: true], else: []

    glob_pattern
    |> Path.wildcard(opts)
    |> Enum.filter(&File.regular?/1)
  end

  defp filter_by_extensions(files, []), do: files

  defp filter_by_extensions(files, extensions) do
    Enum.filter(files, fn file ->
      ext = Path.extname(file) |> String.downcase()
      ext in extensions
    end)
  end

  defp filter_hidden(files, true), do: files

  defp filter_hidden(files, false) do
    Enum.reject(files, fn file ->
      file
      |> Path.split()
      |> Enum.any?(&String.starts_with?(&1, "."))
    end)
  end

  defp filter_excluded(files, exclude) do
    Enum.reject(files, fn file ->
      Enum.any?(exclude, fn pattern ->
        String.contains?(file, pattern)
      end)
    end)
  end

  defp build_file_info(file_path, base_path) do
    stat = File.stat!(file_path)

    %{
      path: file_path,
      relative_path: Path.relative_to(file_path, base_path),
      name: Path.basename(file_path),
      extension: Path.extname(file_path),
      size: stat.size,
      modified: stat.mtime,
      language: detect_language(file_path)
    }
  end

  @extension_to_language %{
    ".ex" => "elixir",
    ".exs" => "elixir",
    ".py" => "python",
    ".pyw" => "python",
    ".js" => "javascript",
    ".jsx" => "javascript",
    ".mjs" => "javascript",
    ".ts" => "typescript",
    ".tsx" => "typescript",
    ".md" => "markdown",
    ".json" => "json",
    ".yml" => "yaml",
    ".yaml" => "yaml"
  }

  defp detect_language(path) do
    ext = Path.extname(path) |> String.downcase()
    Map.get(@extension_to_language, ext, "unknown")
  end
end
