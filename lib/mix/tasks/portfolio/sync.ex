defmodule Mix.Tasks.Portfolio.Sync do
  @shortdoc "Sync portfolio with actual repository state"
  @moduledoc """
  Syncs the portfolio with the actual state of tracked repositories.

  Updates computed fields like last commit, dependencies, etc.

  ## Usage

      mix portfolio.sync [repo-id] [OPTIONS]

  ## Options

    * `--all` - Sync all repositories (default if no repo-id given)
    * `--status` - Only sync repos with this status

  ## Examples

      mix portfolio.sync
      mix portfolio.sync flowstone
      mix portfolio.sync --status=active

  """
  use Mix.Task

  alias PortfolioCoder.Portfolio.Syncer

  @switches [all: :boolean, status: :string]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:portfolio_coder)

    {opts, args, _} = OptionParser.parse(args, switches: @switches)

    case args do
      [repo_id | _] ->
        sync_one(repo_id)

      [] ->
        sync_all(opts)
    end
  end

  defp sync_one(repo_id) do
    Mix.shell().info("Syncing #{repo_id}...")

    case Syncer.sync_repo(repo_id) do
      {:ok, result} ->
        Mix.shell().info("Synced successfully!")

        if last_commit = result.computed.last_commit do
          Mix.shell().info("  Last commit: #{last_commit.sha} - #{last_commit.message}")
        end

        if count = result.computed.commit_count_30d do
          Mix.shell().info("  Commits (30d): #{count}")
        end

      {:error, :not_found} ->
        Mix.shell().error("Repository '#{repo_id}' not found")
        exit({:shutdown, 1})
    end
  end

  defp sync_all(opts) do
    status = if opts[:status], do: String.to_atom(opts[:status]), else: nil
    sync_opts = if status, do: [status: status], else: []

    Mix.shell().info("Syncing all repositories...")
    Mix.shell().info("")

    case Syncer.sync_all(sync_opts) do
      {:ok, result} ->
        Mix.shell().info("Sync complete!")
        Mix.shell().info("  Total:   #{result.total}")
        Mix.shell().info("  Synced:  #{result.synced}")
        Mix.shell().info("  Failed:  #{result.failed}")

        unless Enum.empty?(result.errors) do
          Mix.shell().info("")
          Mix.shell().info("Errors:")

          for {:error, id, reason} <- result.errors do
            Mix.shell().error("  #{id}: #{inspect(reason)}")
          end
        end

      {:error, reason} ->
        Mix.shell().error("Error syncing: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end
end
