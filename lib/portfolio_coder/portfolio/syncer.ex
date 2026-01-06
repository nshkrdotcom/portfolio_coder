defmodule PortfolioCoder.Portfolio.Syncer do
  @moduledoc """
  Syncs portfolio with actual repository state.

  The syncer updates computed fields in repo contexts by reading
  information from the actual repositories (git status, dependencies, etc).

  ## Usage

      # Sync all repos
      {:ok, result} = Syncer.sync_all()

      # Sync a single repo
      {:ok, result} = Syncer.sync_repo("flowstone")

  """

  alias PortfolioCoder.Portfolio.{Registry, Context, Scanner}

  @doc """
  Syncs all registered repositories.

  Returns a summary of the sync operation.
  """
  @spec sync_all(keyword()) :: {:ok, map()} | {:error, term()}
  def sync_all(opts \\ []) do
    case Registry.list_repos() do
      {:ok, repos} ->
        results =
          repos
          |> maybe_filter_repos(opts)
          |> Enum.map(fn repo ->
            case sync_repo(repo.id, opts) do
              {:ok, _} -> {:ok, repo.id}
              {:error, reason} -> {:error, repo.id, reason}
            end
          end)

        synced = Enum.count(results, &match?({:ok, _}, &1))
        failed = Enum.count(results, &match?({:error, _, _}, &1))
        errors = Enum.filter(results, &match?({:error, _, _}, &1))

        {:ok,
         %{
           synced: synced,
           failed: failed,
           errors: errors,
           total: length(repos)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Syncs a single repository.

  Updates computed fields like last commit, dependencies, etc.
  """
  @spec sync_repo(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def sync_repo(repo_id, opts \\ []) when is_binary(repo_id) do
    with {:ok, repo} <- Registry.get_repo(repo_id),
         {:ok, computed} <- update_computed_fields(repo_id, repo.path, opts) do
      {:ok,
       %{
         repo_id: repo_id,
         computed: computed,
         synced_at: DateTime.utc_now()
       }}
    end
  end

  @doc """
  Updates computed fields for a repository.
  """
  @spec update_computed_fields(String.t()) :: {:ok, map()} | {:error, term()}
  def update_computed_fields(repo_id) when is_binary(repo_id) do
    case Registry.get_repo(repo_id) do
      {:ok, repo} -> update_computed_fields(repo_id, repo.path, [])
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_computed_fields(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def update_computed_fields(repo_id, repo_path, _opts) do
    computed = %{}

    # Get git info
    computed =
      case get_git_info(repo_path) do
        {:ok, git_info} -> Map.merge(computed, git_info)
        {:error, _} -> computed
      end

    # Get dependencies
    language = Scanner.detect_language(repo_path)
    deps = Scanner.extract_dependencies(repo_path, language)
    computed = Map.put(computed, :dependencies, deps)

    # Save to context
    Context.update_computed(repo_id, stringify_keys(computed))

    {:ok, computed}
  end

  @doc """
  Extracts git information from a repository.
  """
  @spec get_git_info(String.t()) :: {:ok, map()} | {:error, term()}
  def get_git_info(repo_path) when is_binary(repo_path) do
    if Scanner.is_git_repo?(repo_path) do
      last_commit = get_last_commit(repo_path)
      commit_count = get_commit_count_30d(repo_path)
      branch = get_current_branch(repo_path)

      {:ok,
       %{
         last_commit: last_commit,
         commit_count_30d: commit_count,
         current_branch: branch
       }}
    else
      {:error, :not_a_git_repo}
    end
  end

  # Private functions

  defp get_last_commit(repo_path) do
    case System.cmd("git", ["log", "-1", "--format=%H|%s|%ai"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case String.trim(output) |> String.split("|", parts: 3) do
          [sha, message, date] ->
            %{
              sha: String.slice(sha, 0, 8),
              message: String.trim(message),
              date: parse_git_date(date)
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  defp get_commit_count_30d(repo_path) do
    since = Date.utc_today() |> Date.add(-30) |> Date.to_iso8601()

    case System.cmd("git", ["rev-list", "--count", "--since=#{since}", "HEAD"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output |> String.trim() |> String.to_integer()

      _ ->
        0
    end
  end

  defp get_current_branch(repo_path) do
    case System.cmd("git", ["rev-parse", "--abbrev-ref", "HEAD"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {output, 0} -> String.trim(output)
      _ -> nil
    end
  end

  defp parse_git_date(date_str) do
    # Git date format: 2026-01-05 10:30:00 -0500
    date_str
    |> String.split(" ")
    |> List.first()
  end

  defp maybe_filter_repos(repos, opts) do
    repos
    |> maybe_filter_status(opts[:status])
    |> maybe_filter_type(opts[:type])
  end

  defp maybe_filter_status(repos, nil), do: repos
  defp maybe_filter_status(repos, status), do: Enum.filter(repos, &(&1.status == status))

  defp maybe_filter_type(repos, nil), do: repos
  defp maybe_filter_type(repos, type), do: Enum.filter(repos, &(&1.type == type))

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_keys(v)}
      {k, v} -> {k, stringify_keys(v)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other
end
