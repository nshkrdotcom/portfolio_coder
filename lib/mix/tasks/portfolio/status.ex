defmodule Mix.Tasks.Portfolio.Status do
  @shortdoc "Show portfolio status summary"
  @moduledoc """
  Shows a summary of the portfolio status.

  ## Usage

      mix portfolio.status

  ## Examples

      mix portfolio.status

  """
  use Mix.Task

  alias PortfolioCoder.Portfolio.{Config, Registry, Relationships}

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:portfolio_coder)

    Mix.shell().info("Portfolio Status")
    Mix.shell().info(String.duplicate("=", 70))
    Mix.shell().info("")

    show_portfolio_info()
    show_repo_stats()
    show_relationship_stats()
    show_health()
  end

  defp show_portfolio_info do
    path = Config.portfolio_path()
    dirs = Config.scan_directories()

    Mix.shell().info("Portfolio:    #{path}")
    Mix.shell().info("Scan dirs:    #{length(dirs)}")

    for dir <- dirs do
      Mix.shell().info("              - #{dir}")
    end

    Mix.shell().info("")
  end

  defp show_repo_stats do
    case Registry.list_repos() do
      {:ok, repos} ->
        total = length(repos)

        by_status =
          repos
          |> Enum.group_by(& &1.status)
          |> Enum.map(fn {k, v} -> {k, length(v)} end)
          |> Enum.into(%{})

        by_type =
          repos
          |> Enum.group_by(& &1.type)
          |> Enum.map(fn {k, v} -> {k, length(v)} end)
          |> Enum.into(%{})

        by_language =
          repos
          |> Enum.group_by(& &1.language)
          |> Enum.map(fn {k, v} -> {k, length(v)} end)
          |> Enum.into(%{})

        Mix.shell().info("Repos:        #{total} total")

        Mix.shell().info("")
        Mix.shell().info("By Status:")

        for {status, count} <- by_status do
          Mix.shell().info("  #{status}: #{count}")
        end

        Mix.shell().info("")
        Mix.shell().info("By Type:")

        for {type, count} <- by_type do
          Mix.shell().info("  #{type}: #{count}")
        end

        Mix.shell().info("")
        Mix.shell().info("By Language:")

        for {language, count} <- by_language do
          Mix.shell().info("  #{language}: #{count}")
        end

        Mix.shell().info("")

      {:error, _} ->
        Mix.shell().info("Repos:        (error loading)")
    end
  end

  defp show_relationship_stats do
    case Relationships.list() do
      {:ok, rels} ->
        total = length(rels)

        by_type =
          rels
          |> Enum.group_by(& &1.type)
          |> Enum.map(fn {k, v} -> {k, length(v)} end)
          |> Enum.into(%{})

        Mix.shell().info("Relationships: #{total} total")

        unless Enum.empty?(by_type) do
          for {type, count} <- by_type do
            Mix.shell().info("  #{type}: #{count}")
          end
        end

        Mix.shell().info("")

      {:error, _} ->
        Mix.shell().info("Relationships: (error loading)")
    end
  end

  defp show_health do
    case Registry.list_repos() do
      {:ok, repos} ->
        stale = Enum.count(repos, &(&1.status == :stale))
        blocked = Enum.count(repos, &(&1.status == :blocked))
        active = Enum.count(repos, &(&1.status == :active))

        Mix.shell().info("Health:")

        if active > 0 do
          Mix.shell().info("  Active:  #{active}")
        end

        if stale > 0 do
          Mix.shell().info("  Stale:   #{stale} (need attention)")
        end

        if blocked > 0 do
          Mix.shell().info("  Blocked: #{blocked}")
        end

      {:error, _} ->
        :ok
    end
  end
end
