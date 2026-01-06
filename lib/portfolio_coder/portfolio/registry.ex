defmodule PortfolioCoder.Portfolio.Registry do
  @moduledoc """
  Manages the portfolio registry (registry.yml).

  The registry is the master list of all tracked repositories. Each repo entry
  contains minimal metadata; full context is stored in per-repo context.yml files.

  ## Repo Structure

      %{
        id: "flowstone",
        name: "FlowStone",
        path: "/home/user/p/g/n/flowstone",
        language: :elixir,
        type: :library,
        status: :active,
        remote_url: "git@github.com:user/flowstone.git",
        tags: ["beam", "data"],
        created_at: ~U[2026-01-05 00:00:00Z],
        updated_at: ~U[2026-01-05 00:00:00Z]
      }

  """

  alias PortfolioCoder.Portfolio.Config

  @type repo :: %{
          id: String.t(),
          name: String.t(),
          path: String.t(),
          language: atom(),
          type: atom(),
          status: atom(),
          remote_url: String.t() | nil,
          tags: [String.t()],
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @doc """
  Lists all repos in the registry.

  ## Options

    * `:limit` - Maximum number of repos to return

  """
  @spec list_repos(keyword()) :: {:ok, [repo()]} | {:error, term()}
  def list_repos(opts \\ []) do
    case load_registry() do
      {:ok, data} ->
        repos =
          data
          |> Map.get("repos", [])
          |> Enum.map(&parse_repo/1)
          |> maybe_limit(opts[:limit])

        {:ok, repos}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a single repo by ID.
  """
  @spec get_repo(String.t()) :: {:ok, repo()} | {:error, :not_found}
  def get_repo(id) do
    case list_repos() do
      {:ok, repos} ->
        case Enum.find(repos, &(&1.id == id)) do
          nil -> {:error, :not_found}
          repo -> {:ok, repo}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds a new repo to the registry.

  ## Required Fields

    * `:id` - Unique identifier (slug)
    * `:name` - Display name
    * `:path` - Local filesystem path
    * `:language` - Primary language
    * `:type` - Repo type (:library, :application, :port, etc.)
    * `:status` - Current status (:active, :stale, :archived, etc.)

  """
  @spec add_repo(map()) :: {:ok, repo()} | {:error, term()}
  def add_repo(attrs) when is_map(attrs) do
    with {:ok, id} <- validate_id(attrs),
         :ok <- validate_unique(id),
         {:ok, repo} <- build_repo(attrs) do
      case add_to_registry(repo) do
        :ok -> {:ok, repo}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Updates an existing repo.
  """
  @spec update_repo(String.t(), map()) :: {:ok, repo()} | {:error, term()}
  def update_repo(id, updates) when is_binary(id) and is_map(updates) do
    case get_repo(id) do
      {:ok, existing} ->
        updated =
          existing
          |> Map.merge(atomize_keys(updates))
          |> Map.put(:updated_at, DateTime.utc_now())

        case update_in_registry(id, updated) do
          :ok -> {:ok, updated}
          {:error, reason} -> {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Removes a repo from the registry.
  """
  @spec remove_repo(String.t()) :: :ok | {:error, term()}
  def remove_repo(id) when is_binary(id) do
    case get_repo(id) do
      {:ok, _} -> remove_from_registry(id)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Filters repos by a field value.
  """
  @spec filter_by(atom(), term()) :: {:ok, [repo()]} | {:error, term()}
  def filter_by(field, value) when is_atom(field) do
    case list_repos() do
      {:ok, repos} ->
        filtered = Enum.filter(repos, &(Map.get(&1, field) == value))
        {:ok, filtered}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Saves the current registry state to disk.
  """
  @spec save() :: :ok | {:error, term()}
  def save do
    # Registry is saved on each modification, so this is a no-op
    :ok
  end

  # Private functions

  defp load_registry do
    path = Config.registry_path()

    case File.read(path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, {:parse_error, reason}}
        end

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  defp save_registry(data) do
    path = Config.registry_path()
    yaml = encode_yaml(data)

    case File.write(path, yaml) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_error, reason}}
    end
  end

  defp encode_yaml(data) do
    repos = Map.get(data, "repos", [])

    if Enum.empty?(repos) do
      "repos: []\n"
    else
      repos_yaml = repos |> Enum.map(&encode_repo/1) |> Enum.join("")
      "repos:\n#{repos_yaml}"
    end
  end

  defp encode_repo(repo) when is_map(repo) do
    id = Map.get(repo, :id) || Map.get(repo, "id")
    name = Map.get(repo, :name) || Map.get(repo, "name")
    path = Map.get(repo, :path) || Map.get(repo, "path")
    language = Map.get(repo, :language) || Map.get(repo, "language")
    type = Map.get(repo, :type) || Map.get(repo, "type")
    status = Map.get(repo, :status) || Map.get(repo, "status")
    remote_url = Map.get(repo, :remote_url) || Map.get(repo, "remote_url")
    tags = Map.get(repo, :tags) || Map.get(repo, "tags") || []
    created_at = Map.get(repo, :created_at) || Map.get(repo, "created_at")
    updated_at = Map.get(repo, :updated_at) || Map.get(repo, "updated_at")

    tags_str = if tags == [], do: "[]", else: "[#{Enum.join(tags, ", ")}]"

    """
      - id: #{id}
        name: #{name}
        path: #{path}
        language: #{language}
        type: #{type}
        status: #{status}
        remote_url: #{remote_url || "null"}
        tags: #{tags_str}
        created_at: #{format_datetime(created_at)}
        updated_at: #{format_datetime(updated_at)}
    """
  end

  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(str) when is_binary(str), do: str
  defp format_datetime(_), do: DateTime.to_iso8601(DateTime.utc_now())

  defp parse_repo(data) when is_map(data) do
    %{
      id: Map.get(data, "id"),
      name: Map.get(data, "name"),
      path: Map.get(data, "path"),
      language: parse_atom(Map.get(data, "language")),
      type: parse_atom(Map.get(data, "type")),
      status: parse_atom(Map.get(data, "status")),
      remote_url: Map.get(data, "remote_url"),
      tags: Map.get(data, "tags") || [],
      created_at: parse_datetime(Map.get(data, "created_at")),
      updated_at: parse_datetime(Map.get(data, "updated_at"))
    }
  end

  defp parse_atom(nil), do: nil
  defp parse_atom(val) when is_atom(val), do: val
  defp parse_atom(val) when is_binary(val), do: String.to_atom(val)

  defp parse_datetime(nil), do: nil
  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp validate_id(%{id: id}) when is_binary(id) and byte_size(id) > 0, do: {:ok, id}
  defp validate_id(%{"id" => id}) when is_binary(id) and byte_size(id) > 0, do: {:ok, id}
  defp validate_id(_), do: {:error, :missing_id}

  defp validate_unique(id) do
    case get_repo(id) do
      {:ok, _} -> {:error, :already_exists}
      {:error, :not_found} -> :ok
    end
  end

  defp build_repo(attrs) do
    now = DateTime.utc_now()
    attrs = atomize_keys(attrs)

    repo = %{
      id: attrs[:id],
      name: attrs[:name] || attrs[:id],
      path: attrs[:path],
      language: parse_atom(attrs[:language]),
      type: parse_atom(attrs[:type]),
      status: parse_atom(attrs[:status]) || :active,
      remote_url: attrs[:remote_url],
      tags: attrs[:tags] || [],
      created_at: now,
      updated_at: now
    }

    {:ok, repo}
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  end

  defp add_to_registry(repo) do
    case load_registry() do
      {:ok, data} ->
        repos = Map.get(data, "repos", [])
        updated = Map.put(data, "repos", repos ++ [repo])
        save_registry(updated)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_in_registry(id, updated_repo) do
    case load_registry() do
      {:ok, data} ->
        repos =
          data
          |> Map.get("repos", [])
          |> Enum.map(&parse_repo/1)
          |> Enum.map(fn repo ->
            if repo.id == id, do: updated_repo, else: repo
          end)

        save_registry(Map.put(data, "repos", repos))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp remove_from_registry(id) do
    case load_registry() do
      {:ok, data} ->
        repos =
          data
          |> Map.get("repos", [])
          |> Enum.map(&parse_repo/1)
          |> Enum.reject(&(&1.id == id))

        save_registry(Map.put(data, "repos", repos))

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_limit(repos, nil), do: repos
  defp maybe_limit(repos, limit), do: Enum.take(repos, limit)
end
