defmodule Mix.Tasks.Code.Search do
  @moduledoc """
  Search indexed code repositories.

  Uses TF-IDF keyword scoring against the in-memory index.
  Run `mix code.index PATH` first to build the index.

  ## Usage

      mix code.search QUERY [OPTIONS]

  ## Options

    * `--index` - Name of the index to search (default: "default")
    * `--language` - Filter by programming language
    * `--limit` - Maximum number of results (default: 10)
    * `--file` - Filter by file pattern
    * `--min-score` - Minimum score threshold (default: 0.0)

  ## Examples

      mix code.search "authentication logic"
      mix code.search "database connection" --language elixir
      mix code.search "error handling" --limit 5
      mix code.search "API endpoint" --file "controllers/"

  """
  use Mix.Task

  alias PortfolioCoder.Indexer.InMemorySearch

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
          min_score: :float,
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

    index_name = opts[:index] || "default"

    case get_index(index_name) do
      {:ok, index} ->
        search_opts =
          [limit: opts[:limit] || 10]
          |> maybe_add(:language, parse_language(opts[:language]))
          |> maybe_add(:path_pattern, opts[:file])
          |> maybe_add(:min_score, opts[:min_score])

        {:ok, results} = InMemorySearch.search(index, query, search_opts)

        if results == [] do
          shell_info("No results found.")
        else
          Enum.each(results, &print_result/1)
          shell_info("\nFound #{length(results)} results.")
        end

      {:error, :not_found} ->
        shell_error("""
        Error: Index '#{index_name}' not found.

        Run `mix code.index PATH` first to build the index.
        """)

        exit({:shutdown, 1})
    end
  end

  defp get_index(name) do
    key = {:code_index, name}

    case :persistent_term.get(key, nil) do
      nil -> {:error, :not_found}
      index -> {:ok, index}
    end
  end

  defp print_result(result) do
    path = result.metadata[:relative_path] || result.metadata[:path] || "unknown"
    language = result.metadata[:language] || :unknown
    name = result.metadata[:name]
    type = result.metadata[:type]

    header =
      if name do
        "#{type}: #{name}"
      else
        Path.basename(path)
      end

    shell_info("""
    -----------------------------------------
    #{header}
    File: #{path}
    Language: #{language} | Score: #{Float.round(result.score, 3)}

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
  defp parse_language(lang), do: String.to_atom(lang)
end
