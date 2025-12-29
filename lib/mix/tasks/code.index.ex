defmodule Mix.Tasks.Code.Index do
  @moduledoc """
  Index a code repository for semantic search.

  ## Usage

      mix code.index PATH [OPTIONS]

  ## Options

    * `--index` - Name of the index (default: "default")
    * `--languages` - Comma-separated list of languages to index
    * `--exclude` - Comma-separated patterns to exclude

  ## Examples

      mix code.index ./my_project
      mix code.index ./my_project --index my_project
      mix code.index ./my_project --languages elixir,python
      mix code.index ./my_project --exclude "test/,docs/"

  """
  use Mix.Task

  @shortdoc "Index a code repository"

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:portfolio_coder)

    {opts, paths, _} =
      OptionParser.parse(args,
        strict: [
          index: :string,
          languages: :string,
          exclude: :string,
          help: :boolean
        ],
        aliases: [i: :index, l: :languages, e: :exclude, h: :help]
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

    unless File.dir?(path) do
      shell_error("Error: #{path} is not a directory")
      exit({:shutdown, 1})
    end

    shell_info("Indexing repository: #{path}")

    index_opts =
      []
      |> maybe_add(:index_id, opts[:index])
      |> maybe_add(:languages, parse_languages(opts[:languages]))
      |> maybe_add(:exclude, parse_list(opts[:exclude]))

    case PortfolioCoder.index_repo(path, index_opts) do
      {:ok, result} ->
        shell_info("""

        Indexing complete!
          Files indexed: #{result.files_indexed}
          Index: #{result.index_id}
          Languages: #{inspect(result.languages)}
        """)

      {:error, reason} ->
        shell_error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp shell_info(message), do: IO.puts(message)
  defp shell_error(message), do: IO.puts(:stderr, message)

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_languages(nil), do: nil

  defp parse_languages(languages) do
    languages
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.to_existing_atom/1)
  end

  defp parse_list(nil), do: nil

  defp parse_list(list) do
    list
    |> String.split(",")
    |> Enum.map(&String.trim/1)
  end
end
