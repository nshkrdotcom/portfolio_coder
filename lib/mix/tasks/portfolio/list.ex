defmodule Mix.Tasks.Portfolio.List do
  @shortdoc "List tracked repositories"
  @moduledoc """
  Lists repositories tracked in the portfolio.

  ## Usage

      mix portfolio.list [OPTIONS]

  ## Options

    * `--status`, `-s` - Filter by status (active, stale, archived)
    * `--type`, `-t` - Filter by type (library, application, port)
    * `--language`, `-l` - Filter by language (elixir, python, javascript)
    * `--json` - Output as JSON
    * `--limit`, `-n` - Limit number of results

  ## Examples

      mix portfolio.list
      mix portfolio.list --status=active
      mix portfolio.list --type=library --language=elixir
      mix portfolio.list --json

  """
  use Mix.Task

  alias PortfolioCoder.Portfolio.Registry

  @switches [
    status: :string,
    type: :string,
    language: :string,
    json: :boolean,
    limit: :integer
  ]

  @aliases [s: :status, t: :type, l: :language, n: :limit]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:portfolio_coder)

    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    case Registry.list_repos() do
      {:ok, repos} ->
        repos
        |> apply_filters(opts)
        |> apply_limit(opts[:limit])
        |> output(opts)

      {:error, reason} ->
        Mix.shell().error("Error listing repos: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp apply_filters(repos, opts) do
    repos
    |> filter_by_opt(:status, opts[:status])
    |> filter_by_opt(:type, opts[:type])
    |> filter_by_opt(:language, opts[:language])
  end

  defp filter_by_opt(repos, _field, nil), do: repos

  defp filter_by_opt(repos, field, value) do
    atom_value = String.to_atom(value)
    Enum.filter(repos, &(Map.get(&1, field) == atom_value))
  end

  defp apply_limit(repos, nil), do: repos
  defp apply_limit(repos, limit), do: Enum.take(repos, limit)

  defp output(repos, opts) do
    if opts[:json] do
      output_json(repos)
    else
      output_table(repos)
    end
  end

  defp output_json(repos) do
    json =
      repos
      |> Enum.map(&stringify_repo/1)
      |> Jason.encode!(pretty: true)

    Mix.shell().info(json)
  end

  defp output_table(repos) do
    if Enum.empty?(repos) do
      Mix.shell().info("No repositories found.")
    else
      header = "ID                    TYPE          STATUS      LANGUAGE"
      separator = String.duplicate("-", 70)

      Mix.shell().info(header)
      Mix.shell().info(separator)

      for repo <- repos do
        id = String.pad_trailing(repo.id, 21)
        type = repo.type |> to_string() |> String.pad_trailing(13)
        status = repo.status |> to_string() |> String.pad_trailing(11)
        language = repo.language |> to_string()

        Mix.shell().info("#{id} #{type} #{status} #{language}")
      end

      Mix.shell().info("")
      Mix.shell().info("Total: #{length(repos)} repositories")
    end
  end

  defp stringify_repo(repo) do
    repo
    |> Map.from_struct()
    |> Map.new(fn {k, v} ->
      {to_string(k), stringify_value(v)}
    end)
  rescue
    _ -> Map.new(repo, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp stringify_value(v) when is_atom(v), do: to_string(v)
  defp stringify_value(v), do: v
end
