defmodule Mix.Tasks.Portfolio.Show do
  @shortdoc "Show detailed information about a repository"
  @moduledoc """
  Shows detailed information about a tracked repository.

  ## Usage

      mix portfolio.show <repo-id> [OPTIONS]

  ## Options

    * `--section` - Show specific section (context, notes, deps)
    * `--json` - Output as JSON

  ## Examples

      mix portfolio.show flowstone
      mix portfolio.show flowstone --section=notes
      mix portfolio.show flowstone --json

  """
  use Mix.Task

  alias PortfolioCoder.Portfolio.{Context, Registry, Relationships}

  @switches [section: :string, json: :boolean]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:portfolio_coder)

    {opts, args, _} = OptionParser.parse(args, switches: @switches)

    case args do
      [repo_id | _] ->
        show_repo(repo_id, opts)

      [] ->
        Mix.shell().error("Usage: mix portfolio.show <repo-id>")
        exit({:shutdown, 1})
    end
  end

  defp show_repo(repo_id, opts) do
    with {:ok, repo} <- Registry.get_repo(repo_id),
         {:ok, context} <- load_context(repo_id),
         {:ok, relationships} <- Relationships.get_for_repo(repo_id) do
      data = %{
        repo: repo,
        context: context,
        relationships: relationships
      }

      if opts[:json] do
        output_json(data)
      else
        output_formatted(data, opts[:section])
      end
    else
      {:error, :not_found} ->
        Mix.shell().error("Repository '#{repo_id}' not found")
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp load_context(repo_id) do
    case Context.load(repo_id) do
      {:ok, ctx} -> {:ok, ctx}
      {:error, :not_found} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp output_json(data) do
    json = Jason.encode!(data, pretty: true)
    Mix.shell().info(json)
  end

  defp output_formatted(data, section) do
    repo = data.repo
    context = data.context
    relationships = data.relationships

    case section do
      "notes" ->
        show_notes(repo.id)

      "deps" ->
        show_dependencies(relationships)

      "context" ->
        show_context(context)

      _ ->
        show_full(repo, context, relationships)
    end
  end

  defp show_full(repo, context, relationships) do
    print_header(repo.id)
    print_repo_details(repo)
    print_remote(repo.remote_url)
    print_purpose(context["purpose"])
    maybe_show_computed(context["computed"])
    print_relationships(repo.id, relationships)
    print_todos(context["todos"])
  end

  defp print_header(repo_id) do
    Mix.shell().info(repo_id)
    Mix.shell().info(String.duplicate("=", 70))
    Mix.shell().info("")
  end

  defp print_repo_details(repo) do
    Mix.shell().info("Type:        #{repo.type} (#{repo.language})")
    Mix.shell().info("Status:      #{repo.status}")
    Mix.shell().info("Path:        #{repo.path}")
    Mix.shell().info("")
  end

  defp print_remote(nil), do: :ok

  defp print_remote(remote_url) do
    Mix.shell().info("Remote:      #{remote_url}")
    Mix.shell().info("")
  end

  defp print_purpose(nil), do: :ok

  defp print_purpose(purpose) do
    Mix.shell().info("Purpose:")
    Mix.shell().info("  #{String.trim(purpose)}")
    Mix.shell().info("")
  end

  defp maybe_show_computed(nil), do: :ok
  defp maybe_show_computed(computed), do: show_computed(computed)

  defp print_relationships(_repo_id, []), do: :ok

  defp print_relationships(repo_id, relationships) do
    Mix.shell().info("Relationships:")

    for rel <- relationships do
      direction = if rel.from == repo_id, do: "->", else: "<-"
      other = if rel.from == repo_id, do: rel.to, else: rel.from
      Mix.shell().info("  #{direction} #{other} (#{rel.type})")
    end

    Mix.shell().info("")
  end

  defp print_todos(nil), do: :ok

  defp print_todos(todos) do
    Mix.shell().info("Todos:")

    for todo <- List.wrap(todos) do
      Mix.shell().info("  - #{todo}")
    end

    Mix.shell().info("")
  end

  defp show_notes(repo_id) do
    case Context.get_notes(repo_id) do
      {:ok, notes} ->
        Mix.shell().info(notes)

      {:error, :not_found} ->
        Mix.shell().info("No notes found for #{repo_id}")

      {:error, reason} ->
        Mix.shell().error("Error loading notes: #{inspect(reason)}")
    end
  end

  defp show_dependencies(relationships) do
    deps = Enum.filter(relationships, &(&1.type == :depends_on))

    if Enum.empty?(deps) do
      Mix.shell().info("No dependencies found")
    else
      Mix.shell().info("Dependencies:")

      for dep <- deps do
        Mix.shell().info("  - #{dep.to}")
      end
    end
  end

  defp show_context(context) do
    yaml = Jason.encode!(context, pretty: true)
    Mix.shell().info(yaml)
  end

  defp show_computed(computed) do
    Mix.shell().info("Stats:")

    if last_commit = computed["last_commit"] do
      Mix.shell().info("  Last commit:      #{last_commit["sha"]} - #{last_commit["message"]}")
    end

    if count = computed["commit_count_30d"] do
      Mix.shell().info("  Commits (30d):    #{count}")
    end

    if deps = computed["dependencies"] do
      runtime = deps["runtime"] || []
      Mix.shell().info("  Dependencies:     #{length(runtime)} runtime")
    end

    Mix.shell().info("")
  end
end
