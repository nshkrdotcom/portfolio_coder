defmodule PortfolioCoder.Portfolio.Relationships do
  @moduledoc """
  Manages inter-repository relationships.

  Relationships are stored in `relationships.yml` in the portfolio root.
  They track how repositories connect to each other.

  ## Relationship Types

    * `:depends_on` - From uses To as a dependency
    * `:port_of` - From is a port of To (different language)
    * `:evolved_from` - From is a rewrite/evolution of To
    * `:related_to` - From and To are conceptually related
    * `:forked_from` - From is a git fork of To

  ## Relationship Structure

      %{
        type: :depends_on,
        from: "flowstone_ai",
        to: "flowstone",
        auto_detected: true,
        details: %{dependency_type: "runtime"}
      }

  """

  alias PortfolioCoder.Portfolio.Config

  @type relationship :: %{
          type: atom(),
          from: String.t(),
          to: String.t(),
          auto_detected: boolean(),
          details: map()
        }

  @valid_types [
    :depends_on,
    :port_of,
    :evolved_from,
    :related_to,
    :forked_from,
    :supersedes,
    :alternative_to,
    :contains
  ]

  @doc """
  Lists all relationships.

  ## Options

    * `:type` - Filter by relationship type

  """
  @spec list(keyword()) :: {:ok, [relationship()]} | {:error, term()}
  def list(opts \\ []) do
    case load_relationships() do
      {:ok, data} ->
        rels =
          data
          |> Map.get("relationships", [])
          |> Enum.map(&parse_relationship/1)
          |> maybe_filter_type(opts[:type])

        {:ok, rels}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds a new relationship.
  """
  @spec add(atom(), String.t(), String.t(), map()) :: {:ok, relationship()} | {:error, term()}
  def add(type, from, to, details \\ %{})
      when type in @valid_types and is_binary(from) and is_binary(to) do
    rel = %{
      type: type,
      from: from,
      to: to,
      auto_detected: Map.get(details, :auto_detected, false),
      details: Map.delete(details, :auto_detected)
    }

    case add_to_file(rel) do
      :ok -> {:ok, rel}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes all relationships between two repos.
  """
  @spec remove(String.t(), String.t()) :: :ok | {:error, term()}
  def remove(from, to) when is_binary(from) and is_binary(to) do
    case list() do
      {:ok, rels} ->
        matching = Enum.filter(rels, fn r -> r.from == from and r.to == to end)

        if Enum.empty?(matching) do
          {:error, :not_found}
        else
          filtered = Enum.reject(rels, fn r -> r.from == from and r.to == to end)
          save_relationships(filtered)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets all relationships involving a repo (as either from or to).
  """
  @spec get_for_repo(String.t()) :: {:ok, [relationship()]} | {:error, term()}
  def get_for_repo(repo_id) when is_binary(repo_id) do
    case list() do
      {:ok, rels} ->
        matching = Enum.filter(rels, fn r -> r.from == repo_id or r.to == repo_id end)
        {:ok, matching}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets repos that the given repo depends on.
  """
  @spec get_dependencies(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def get_dependencies(repo_id) when is_binary(repo_id) do
    case list() do
      {:ok, rels} ->
        deps =
          rels
          |> Enum.filter(fn r -> r.type == :depends_on and r.from == repo_id end)
          |> Enum.map(& &1.to)

        {:ok, deps}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets repos that depend on the given repo.
  """
  @spec get_dependents(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def get_dependents(repo_id) when is_binary(repo_id) do
    case list() do
      {:ok, rels} ->
        dependents =
          rels
          |> Enum.filter(fn r -> r.type == :depends_on and r.to == repo_id end)
          |> Enum.map(& &1.from)

        {:ok, dependents}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Filters relationships by type.
  """
  @spec filter_by_type(atom()) :: {:ok, [relationship()]} | {:error, term()}
  def filter_by_type(type) when is_atom(type) do
    list(type: type)
  end

  @doc """
  Saves relationships to disk.
  """
  @spec save() :: :ok | {:error, term()}
  def save do
    :ok
  end

  # Private functions

  defp load_relationships do
    path = Config.relationships_path()

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

  defp save_relationships(rels) do
    path = Config.relationships_path()
    yaml = encode_relationships_yaml(rels)

    case File.write(path, yaml) do
      :ok -> :ok
      {:error, reason} -> {:error, {:write_error, reason}}
    end
  end

  defp add_to_file(rel) do
    case list() do
      {:ok, rels} ->
        save_relationships(rels ++ [rel])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode_relationships_yaml(rels) do
    if Enum.empty?(rels) do
      "relationships: []\n"
    else
      items =
        rels
        |> Enum.map(&encode_relationship/1)
        |> Enum.join("")

      "relationships:\n#{items}"
    end
  end

  defp encode_relationship(rel) do
    type = rel.type
    from = rel.from
    to = rel.to
    auto = rel.auto_detected

    base = """
      - type: #{type}
        from: #{from}
        to: #{to}
        auto_detected: #{auto}
    """

    if rel.details && map_size(rel.details) > 0 do
      details =
        rel.details
        |> Enum.map(fn {k, v} -> "      #{k}: #{v}" end)
        |> Enum.join("\n")

      base <> "    details:\n#{details}\n"
    else
      base
    end
  end

  defp parse_relationship(data) when is_map(data) do
    %{
      type: parse_atom(Map.get(data, "type")),
      from: Map.get(data, "from"),
      to: Map.get(data, "to"),
      auto_detected: Map.get(data, "auto_detected", false),
      details: Map.get(data, "details", %{})
    }
  end

  defp parse_atom(nil), do: nil
  defp parse_atom(val) when is_atom(val), do: val
  defp parse_atom(val) when is_binary(val), do: String.to_atom(val)

  defp maybe_filter_type(rels, nil), do: rels
  defp maybe_filter_type(rels, type), do: Enum.filter(rels, &(&1.type == type))
end
