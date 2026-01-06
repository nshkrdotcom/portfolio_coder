defmodule Mix.Tasks.Portfolio.Add do
  @shortdoc "Add a repository to tracking"
  @moduledoc """
  Adds a repository to the portfolio registry.

  ## Usage

      mix portfolio.add <path> [OPTIONS]

  ## Options

    * `--id` - Override the auto-generated ID
    * `--type` - Set the type (library, application, port)
    * `--status` - Set the status (active, stale, archived)

  ## Examples

      mix portfolio.add .
      mix portfolio.add ~/p/g/n/my-project
      mix portfolio.add . --type=library --id=my-lib

  """
  use Mix.Task

  alias PortfolioCoder.Portfolio.{Config, Scanner, Registry, Context}

  @switches [id: :string, type: :string, status: :string]

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:portfolio_coder)

    {opts, args, _} = OptionParser.parse(args, switches: @switches)

    case args do
      [path | _] ->
        add_repo(Config.expand_path(path), opts)

      [] ->
        Mix.shell().error("Usage: mix portfolio.add <path> [OPTIONS]")
        exit({:shutdown, 1})
    end
  end

  defp add_repo(path, opts) do
    unless File.dir?(path) do
      Mix.shell().error("Path does not exist or is not a directory: #{path}")
      exit({:shutdown, 1})
    end

    unless Scanner.is_git_repo?(path) do
      Mix.shell().error("Path is not a git repository: #{path}")
      exit({:shutdown, 1})
    end

    name = Path.basename(path)
    id = opts[:id] || name
    language = Scanner.detect_language(path)
    type = parse_type(opts[:type]) || Scanner.detect_type(path) || :library
    status = parse_status(opts[:status]) || :active
    remotes = Scanner.extract_remotes(path)

    attrs = %{
      id: id,
      name: name,
      path: path,
      language: language,
      type: type,
      status: status,
      remote_url: get_primary_remote(remotes)
    }

    case Registry.add_repo(attrs) do
      {:ok, repo} ->
        # Create context directory
        Context.ensure_repo_dir(id)

        # Create initial context
        initial_context = %{
          "id" => id,
          "name" => name,
          "path" => path,
          "language" => to_string(language),
          "type" => to_string(type),
          "status" => to_string(status),
          "purpose" => "TODO: Add description",
          "todos" => []
        }

        Context.save(id, initial_context)

        Mix.shell().info("Added repository: #{repo.id}")
        Mix.shell().info("  Path:     #{repo.path}")
        Mix.shell().info("  Language: #{repo.language}")
        Mix.shell().info("  Type:     #{repo.type}")
        Mix.shell().info("  Status:   #{repo.status}")

      {:error, :already_exists} ->
        Mix.shell().error("Repository '#{id}' already exists in registry")
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("Error adding repository: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp parse_type(nil), do: nil
  defp parse_type(type), do: String.to_atom(type)

  defp parse_status(nil), do: nil
  defp parse_status(status), do: String.to_atom(status)

  defp get_primary_remote([]), do: nil
  defp get_primary_remote([remote | _]), do: remote.url
end
