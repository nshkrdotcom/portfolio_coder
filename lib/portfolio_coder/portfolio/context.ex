defmodule PortfolioCoder.Portfolio.Context do
  @moduledoc """
  Manages per-repo context files.

  Each tracked repository has a context directory in the portfolio at
  `repos/{repo_id}/` containing:

    * `context.yml` - Structured metadata
    * `notes.md` - Free-form notes
    * `docs/` - Generated documentation

  ## Context Structure

      %{
        "id" => "flowstone",
        "name" => "FlowStone",
        "path" => "~/p/g/n/flowstone",
        "language" => "elixir",
        "type" => "library",
        "status" => "active",
        "purpose" => "Asset-first orchestration",
        "todos" => ["Add S3 I/O", "Write docs"],
        "computed" => %{...}
      }

  """

  alias PortfolioCoder.Portfolio.Config

  @doc """
  Loads context for a repository.
  """
  @spec load(String.t()) :: {:ok, map()} | {:error, term()}
  def load(repo_id) when is_binary(repo_id) do
    context_path = context_file_path(repo_id)

    case File.read(context_path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, context} -> {:ok, context}
          {:error, reason} -> {:error, {:parse_error, reason}}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  @doc """
  Saves context for a repository.
  """
  @spec save(String.t(), map()) :: :ok | {:error, term()}
  def save(repo_id, context) when is_binary(repo_id) and is_map(context) do
    with :ok <- ensure_repo_dir(repo_id) do
      context_path = context_file_path(repo_id)
      yaml = encode_context_yaml(context)

      case File.write(context_path, yaml) do
        :ok -> :ok
        {:error, reason} -> {:error, {:write_error, reason}}
      end
    end
  end

  @doc """
  Gets the notes for a repository.
  """
  @spec get_notes(String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_notes(repo_id) when is_binary(repo_id) do
    notes_path = notes_file_path(repo_id)

    case File.read(notes_path) do
      {:ok, content} -> {:ok, content}
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, {:file_error, reason}}
    end
  end

  @doc """
  Saves notes for a repository.
  """
  @spec save_notes(String.t(), String.t()) :: :ok | {:error, term()}
  def save_notes(repo_id, notes) when is_binary(repo_id) and is_binary(notes) do
    with :ok <- ensure_repo_dir(repo_id) do
      notes_path = notes_file_path(repo_id)

      case File.write(notes_path, notes) do
        :ok -> :ok
        {:error, reason} -> {:error, {:write_error, reason}}
      end
    end
  end

  @doc """
  Ensures the repo directory exists.
  """
  @spec ensure_repo_dir(String.t()) :: :ok | {:error, term()}
  def ensure_repo_dir(repo_id) when is_binary(repo_id) do
    repo_dir = repo_dir_path(repo_id)

    case File.mkdir_p(repo_dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_error, reason}}
    end
  end

  @doc """
  Updates a single field in the context.
  """
  @spec update_field(String.t(), String.t(), term()) :: :ok | {:error, term()}
  def update_field(repo_id, field, value) when is_binary(repo_id) and is_binary(field) do
    case load(repo_id) do
      {:ok, context} ->
        updated = Map.put(context, field, value)
        save(repo_id, updated)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a single field from the context.
  """
  @spec get_field(String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def get_field(repo_id, field) when is_binary(repo_id) and is_binary(field) do
    case load(repo_id) do
      {:ok, context} ->
        case Map.fetch(context, field) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, :field_not_found}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates computed fields in the context.
  """
  @spec update_computed(String.t(), map()) :: :ok | {:error, term()}
  def update_computed(repo_id, computed) when is_binary(repo_id) and is_map(computed) do
    case load(repo_id) do
      {:ok, context} ->
        existing_computed = Map.get(context, "computed", %{})
        merged = Map.merge(existing_computed, computed)
        updated = Map.put(context, "computed", merged)
        save(repo_id, updated)

      {:error, :not_found} ->
        # Create minimal context with computed fields
        save(repo_id, %{"id" => repo_id, "computed" => computed})

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  defp repo_dir_path(repo_id) do
    Path.join([Config.repos_path(), repo_id])
  end

  defp context_file_path(repo_id) do
    Path.join([repo_dir_path(repo_id), "context.yml"])
  end

  defp notes_file_path(repo_id) do
    Path.join([repo_dir_path(repo_id), "notes.md"])
  end

  defp encode_context_yaml(context) when is_map(context) do
    Enum.map_join(context, "", &encode_yaml_field/1)
  end

  defp encode_yaml_field({key, value}) when is_binary(value) do
    if String.contains?(value, "\n") do
      "#{key}: |\n#{indent_multiline(value)}\n"
    else
      "#{key}: #{value}\n"
    end
  end

  defp encode_yaml_field({key, value}) when is_list(value) do
    if Enum.empty?(value) do
      "#{key}: []\n"
    else
      items = Enum.map_join(value, "\n", &"  - #{encode_list_item(&1)}")
      "#{key}:\n#{items}\n"
    end
  end

  defp encode_yaml_field({key, value}) when is_map(value) do
    nested =
      Enum.map_join(value, "\n", fn {k, v} -> "  #{k}: #{encode_value(v)}" end)

    "#{key}:\n#{nested}\n"
  end

  defp encode_yaml_field({key, value}) do
    "#{key}: #{encode_value(value)}\n"
  end

  defp encode_value(val) when is_binary(val), do: val
  defp encode_value(val) when is_atom(val), do: Atom.to_string(val)
  defp encode_value(val) when is_integer(val), do: Integer.to_string(val)
  defp encode_value(val) when is_float(val), do: Float.to_string(val)
  defp encode_value(nil), do: "null"
  defp encode_value(val), do: inspect(val)

  defp encode_list_item(item) when is_binary(item), do: item
  defp encode_list_item(item), do: inspect(item)

  defp indent_multiline(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &"  #{&1}")
  end
end
