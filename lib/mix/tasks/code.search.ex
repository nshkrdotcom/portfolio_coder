defmodule Mix.Tasks.Code.Search do
  @moduledoc """
  Search indexed code repositories.

  ## Usage

      mix code.search QUERY [OPTIONS]

  ## Options

    * `--index` - Name of the index to search (default: "default")
    * `--language` - Filter by programming language
    * `--limit` - Maximum number of results (default: 10)
    * `--file` - Filter by file pattern

  ## Examples

      mix code.search "authentication logic"
      mix code.search "database connection" --language elixir
      mix code.search "error handling" --limit 5
      mix code.search "API endpoint" --file "controllers/"

  """
  use Mix.Task

  @shortdoc "Search indexed code"

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:portfolio_coder)

    {opts, query_parts, _} =
      OptionParser.parse(args,
        strict: [
          index: :string,
          language: :string,
          limit: :integer,
          file: :string,
          help: :boolean
        ],
        aliases: [i: :index, l: :language, n: :limit, f: :file, h: :help]
      )

    if opts[:help] do
      shell_info(@moduledoc)
    else
      query = Enum.join(query_parts, " ")

      if query == "" do
        shell_error("Error: Please provide a search query")
        exit({:shutdown, 1})
      end

      search_code(query, opts)
    end
  end

  defp search_code(query, opts) do
    shell_info("Searching for: #{query}\n")

    search_opts =
      []
      |> maybe_add(:index_id, opts[:index])
      |> maybe_add(:language, parse_language(opts[:language]))
      |> maybe_add(:limit, opts[:limit])
      |> maybe_add(:file_pattern, opts[:file])

    case PortfolioCoder.search_code(query, search_opts) do
      {:ok, results} ->
        if results == [] do
          shell_info("No results found.")
        else
          Enum.each(results, &print_result/1)
          shell_info("\nFound #{length(results)} results.")
        end

      {:error, reason} ->
        shell_error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp print_result(result) do
    shell_info("""
    -----------------------------------------
    File: #{result.path}
    Language: #{result.language} | Score: #{Float.round(result.score, 3)}

    #{truncate(result.content, 300)}
    """)
  end

  defp truncate(text, max) when byte_size(text) > max do
    String.slice(text, 0, max) <> "..."
  end

  defp truncate(text, _max), do: text

  defp shell_info(message), do: IO.puts(message)
  defp shell_error(message), do: IO.puts(:stderr, message)

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_language(nil), do: nil
  defp parse_language(lang), do: String.to_existing_atom(lang)
end
