defmodule Mix.Tasks.Portfolio.Scan do
  @shortdoc "Scan directories to discover repositories"
  @moduledoc """
  Scans configured directories to discover repositories.

  ## Usage

      mix portfolio.scan [directories...] [OPTIONS]

  ## Options

    * `--add` - Automatically add discovered repos to registry
    * `--dry-run` - Show what would be discovered without making changes

  ## Examples

      mix portfolio.scan
      mix portfolio.scan ~/p/g/n ~/p/g/North-Shore-AI
      mix portfolio.scan --add
      mix portfolio.scan --dry-run

  """
  use Mix.Task

  alias PortfolioCoder.Portfolio.{Config, Registry, Scanner}

  @switches [add: :boolean, dry_run: :boolean]
  @aliases [n: :dry_run]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:portfolio_coder)

    {opts, dirs, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    directories = resolve_directories(dirs)
    print_directories(directories)

    {:ok, results} = Scanner.scan(directories: directories)
    {new_repos, existing} = split_repos(results)

    print_summary(results, new_repos, existing)
    handle_new_repos(new_repos, opts)
  end

  defp resolve_directories([]), do: Config.scan_directories()
  defp resolve_directories(dirs), do: Enum.map(dirs, &Config.expand_path/1)

  defp print_directories(directories) do
    Mix.shell().info("Scanning directories:")

    for dir <- directories do
      Mix.shell().info("  - #{dir}")
    end

    Mix.shell().info("")
  end

  defp split_repos(results) do
    new_repos = Enum.filter(results, & &1.is_new)
    existing = Enum.reject(results, & &1.is_new)
    {new_repos, existing}
  end

  defp print_summary(results, new_repos, existing) do
    Mix.shell().info("Found #{length(results)} repositories:")
    Mix.shell().info("  New:             #{length(new_repos)}")
    Mix.shell().info("  Already tracked: #{length(existing)}")
    Mix.shell().info("")
  end

  defp handle_new_repos([], _opts), do: :ok

  defp handle_new_repos(new_repos, opts) do
    Mix.shell().info("New repositories:")

    for repo <- new_repos do
      lang = repo.language || "unknown"
      type = repo.type || "unknown"
      Mix.shell().info("  #{repo.name} (#{lang}, #{type})")
      Mix.shell().info("    Path: #{repo.path}")
    end

    Mix.shell().info("")
    handle_add_option(new_repos, opts)
  end

  defp handle_add_option(new_repos, opts) do
    cond do
      Keyword.get(opts, :dry_run, false) ->
        Mix.shell().info("(Dry run - no changes made)")

      Keyword.get(opts, :add, false) ->
        add_repos(new_repos)

      true ->
        Mix.shell().info("Run with --add to add these to the registry")
    end
  end

  defp add_repos(repos) do
    Mix.shell().info("Adding #{length(repos)} repositories to registry...")

    for repo <- repos do
      attrs = %{
        id: repo.name,
        name: repo.name,
        path: repo.path,
        language: repo.language,
        type: repo.type || :unknown,
        status: :active,
        remote_url: get_primary_remote(repo.remotes)
      }

      case Registry.add_repo(attrs) do
        {:ok, _} ->
          Mix.shell().info("  Added: #{repo.name}")

        {:error, reason} ->
          Mix.shell().error("  Failed to add #{repo.name}: #{inspect(reason)}")
      end
    end

    Mix.shell().info("")
    Mix.shell().info("Done!")
  end

  defp get_primary_remote([]), do: nil
  defp get_primary_remote([remote | _]), do: remote.url
end
