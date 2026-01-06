defmodule Mix.Tasks.Portfolio.Remove do
  @shortdoc "Remove a repository from tracking"
  @moduledoc """
  Removes a repository from the portfolio registry.

  ## Usage

      mix portfolio.remove <repo-id> [OPTIONS]

  ## Options

    * `--force`, `-f` - Don't prompt for confirmation
    * `--keep-context` - Keep the context directory

  ## Examples

      mix portfolio.remove old-project
      mix portfolio.remove old-project --force

  """
  use Mix.Task

  alias PortfolioCoder.Portfolio.{Config, Registry}

  @switches [force: :boolean, keep_context: :boolean]
  @aliases [f: :force]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:portfolio_coder)

    {opts, args, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    case args do
      [repo_id | _] ->
        remove_repo(repo_id, opts)

      [] ->
        Mix.shell().error("Usage: mix portfolio.remove <repo-id> [OPTIONS]")
        exit({:shutdown, 1})
    end
  end

  defp remove_repo(repo_id, opts) do
    case Registry.get_repo(repo_id) do
      {:ok, repo} ->
        if opts[:force] or confirm_removal(repo) do
          do_remove(repo_id, opts)
        else
          Mix.shell().info("Cancelled.")
        end

      {:error, :not_found} ->
        Mix.shell().error("Repository '#{repo_id}' not found")
        exit({:shutdown, 1})
    end
  end

  defp confirm_removal(repo) do
    Mix.shell().info("About to remove: #{repo.id}")
    Mix.shell().info("  Path: #{repo.path}")
    Mix.shell().info("")

    Mix.shell().yes?("Are you sure?")
  end

  defp do_remove(repo_id, opts) do
    case Registry.remove_repo(repo_id) do
      :ok ->
        unless opts[:keep_context] do
          remove_context_dir(repo_id)
        end

        Mix.shell().info("Removed: #{repo_id}")

      {:error, reason} ->
        Mix.shell().error("Error removing: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp remove_context_dir(repo_id) do
    context_dir = Path.join([Config.repos_path(), repo_id])

    if File.dir?(context_dir) do
      File.rm_rf!(context_dir)
    end
  end
end
