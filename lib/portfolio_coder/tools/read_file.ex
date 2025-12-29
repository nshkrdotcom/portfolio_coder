defmodule PortfolioCoder.Tools.ReadFile do
  @moduledoc """
  File reading tool for agents.

  Provides safe file reading with content limits and line range support.
  """

  @max_file_size 1_000_000
  @max_lines 1000

  @doc """
  Get the tool definition for agent registration.
  """
  @spec definition() :: map()
  def definition do
    %{
      name: "read_file",
      description: """
      Read the contents of a file. Supports reading specific line ranges
      and provides syntax information based on file extension.
      """,
      parameters: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "The file path to read"
          },
          start_line: %{
            type: "integer",
            description: "Starting line number (1-based, default: 1)"
          },
          end_line: %{
            type: "integer",
            description: "Ending line number (default: end of file)"
          },
          include_line_numbers: %{
            type: "boolean",
            description: "Include line numbers in output (default: true)",
            default: true
          }
        },
        required: ["path"]
      },
      handler: &__MODULE__.execute/1
    }
  end

  @doc """
  Execute the read_file tool.
  """
  @spec execute(map()) :: {:ok, map()} | {:error, term()}
  def execute(args) do
    path = Map.fetch!(args, "path")
    start_line = Map.get(args, "start_line", 1)
    end_line = Map.get(args, "end_line")
    include_numbers = Map.get(args, "include_line_numbers", true)

    with :ok <- validate_path(path),
         {:ok, stat} <- File.stat(path),
         :ok <- validate_size(stat.size),
         {:ok, content} <- File.read(path) do
      lines = String.split(content, "\n")
      total_lines = length(lines)

      end_line = end_line || total_lines
      end_line = min(end_line, start_line + @max_lines - 1)

      selected =
        lines
        |> Enum.slice((start_line - 1)..(end_line - 1))

      output =
        if include_numbers do
          selected
          |> Enum.with_index(start_line)
          |> Enum.map_join("\n", fn {line, num} ->
            num_str = String.pad_leading(Integer.to_string(num), 4)
            "#{num_str} | #{line}"
          end)
        else
          Enum.join(selected, "\n")
        end

      language = detect_language(path)

      {:ok,
       %{
         path: path,
         content: output,
         language: language,
         total_lines: total_lines,
         start_line: start_line,
         end_line: end_line,
         truncated: end_line < total_lines
       }}
    end
  end

  defp validate_path(path) do
    expanded = Path.expand(path)

    cond do
      String.contains?(expanded, "..") ->
        {:error, :path_traversal_not_allowed}

      not File.exists?(path) ->
        {:error, :file_not_found}

      File.dir?(path) ->
        {:error, :is_directory}

      true ->
        :ok
    end
  end

  defp validate_size(size) when size > @max_file_size do
    {:error, {:file_too_large, size, @max_file_size}}
  end

  defp validate_size(_size), do: :ok

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
    ".yaml" => "yaml",
    ".html" => "html",
    ".css" => "css",
    ".sql" => "sql",
    ".sh" => "bash"
  }

  defp detect_language(path) do
    ext = Path.extname(path) |> String.downcase()
    Map.get(@extension_to_language, ext, "text")
  end
end
