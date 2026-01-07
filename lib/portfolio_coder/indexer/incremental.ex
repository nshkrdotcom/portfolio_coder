defmodule PortfolioCoder.Indexer.Incremental do
  @moduledoc """
  Incremental indexing with change detection via content hashing.

  Tracks file changes to enable efficient re-indexing of only modified files,
  rather than re-processing the entire codebase.

  ## Usage

      # First scan - indexes all files
      {:ok, changeset, state} = Incremental.incremental_scan("./lib")

      # Subsequent scans - only changed files
      {:ok, changeset, new_state} = Incremental.incremental_scan("./lib",
        state_file: ".index_state"
      )

      # Process only the changes
      Enum.each(changeset.added, &index_file/1)
      Enum.each(changeset.modified, &reindex_file/1)
      Enum.each(changeset.deleted, &remove_from_index/1)

  ## State Persistence

  State can be persisted to a JSON file for incremental updates across sessions:

      Incremental.save_state(state, ".index_state")
      {:ok, state} = Incremental.load_state(".index_state")
  """

  @type file_info :: %{
          hash: String.t(),
          mtime: integer(),
          size: non_neg_integer()
        }

  @type state :: %{String.t() => file_info()}

  @type changeset :: %{
          added: [%{path: String.t(), info: file_info()}],
          modified: [%{path: String.t(), old_info: file_info(), new_info: file_info()}],
          deleted: [String.t()]
        }

  @default_extensions [".ex", ".exs", ".py", ".js", ".ts"]

  @doc """
  Compute SHA256 hash of content string.
  """
  @spec compute_hash(String.t()) :: String.t()
  def compute_hash(content) when is_binary(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Compute hash of a file's contents.
  """
  @spec compute_file_hash(String.t()) :: {:ok, String.t()} | {:error, term()}
  def compute_file_hash(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, compute_hash(content)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Build state map from a directory.

  Returns a map of file paths to their hash and metadata.

  ## Options

    * `:extensions` - List of file extensions to include (default: common code files)
    * `:exclude` - Patterns to exclude
  """
  @spec build_state(String.t(), keyword()) :: state()
  def build_state(dir, opts \\ []) do
    extensions = Keyword.get(opts, :extensions, @default_extensions)
    exclude = Keyword.get(opts, :exclude, ["deps/", "_build/", "node_modules/"])

    dir
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(fn path ->
      File.regular?(path) and
        has_extension?(path, extensions) and
        not excluded?(path, exclude)
    end)
    |> Enum.reduce(%{}, fn path, acc ->
      case build_file_info(path) do
        {:ok, info} -> Map.put(acc, path, info)
        {:error, _} -> acc
      end
    end)
  end

  @doc """
  Detect changes between old and new state.

  Returns a changeset with added, modified, and deleted files.
  """
  @spec detect_changes(state(), state()) :: changeset()
  def detect_changes(old_state, new_state) do
    old_paths = Map.keys(old_state) |> MapSet.new()
    new_paths = Map.keys(new_state) |> MapSet.new()

    # Deleted files
    deleted =
      MapSet.difference(old_paths, new_paths)
      |> MapSet.to_list()

    # Added files
    added =
      MapSet.difference(new_paths, old_paths)
      |> MapSet.to_list()
      |> Enum.map(fn path ->
        %{path: path, info: Map.fetch!(new_state, path)}
      end)

    # Possibly modified files (exist in both)
    common = MapSet.intersection(old_paths, new_paths)

    modified =
      common
      |> Enum.filter(fn path ->
        old_info = Map.fetch!(old_state, path)
        new_info = Map.fetch!(new_state, path)
        old_info.hash != new_info.hash
      end)
      |> Enum.map(fn path ->
        %{
          path: path,
          old_info: Map.fetch!(old_state, path),
          new_info: Map.fetch!(new_state, path)
        }
      end)

    %{
      added: added,
      modified: modified,
      deleted: deleted
    }
  end

  @doc """
  Save state to a JSON file.
  """
  @spec save_state(state(), String.t()) :: :ok | {:error, term()}
  def save_state(state, path) do
    json = Jason.encode!(state, pretty: true)

    case File.write(path, json) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Load state from a JSON file.
  """
  @spec load_state(String.t()) :: {:ok, state()} | {:error, term()}
  def load_state(path) do
    with {:ok, json} <- File.read(path),
         {:ok, data} <- Jason.decode(json) do
      # Convert string keys back to atoms in nested maps
      state =
        Enum.into(data, %{}, fn {path, info} ->
          {path,
           %{
             hash: info["hash"],
             mtime: info["mtime"],
             size: info["size"]
           }}
        end)

      {:ok, state}
    end
  end

  @doc """
  Perform an incremental scan of a directory.

  If a state file exists, loads it and returns only changes.
  Otherwise, returns all files as added.

  ## Options

    * `:state_file` - Path to state persistence file
    * `:extensions` - List of file extensions
    * `:exclude` - Patterns to exclude
  """
  @spec incremental_scan(String.t(), keyword()) ::
          {:ok, changeset(), state()} | {:error, term()}
  def incremental_scan(dir, opts \\ []) do
    state_file = Keyword.get(opts, :state_file)
    extensions = Keyword.get(opts, :extensions, @default_extensions)
    exclude = Keyword.get(opts, :exclude, ["deps/", "_build/", "node_modules/"])

    # Load existing state if available
    old_state =
      if state_file && File.exists?(state_file) do
        case load_state(state_file) do
          {:ok, state} -> state
          {:error, _} -> %{}
        end
      else
        %{}
      end

    # Build current state
    new_state = build_state(dir, extensions: extensions, exclude: exclude)

    # Detect changes
    changeset = detect_changes(old_state, new_state)

    # Save new state if path provided
    if state_file do
      save_state(new_state, state_file)
    end

    {:ok, changeset, new_state}
  end

  @doc """
  Check if a file needs to be re-indexed.

  Returns true if the file is not in state or has changed.
  """
  @spec needs_reindex?(String.t(), state()) :: boolean()
  def needs_reindex?(path, state) do
    case Map.get(state, path) do
      nil ->
        true

      old_info ->
        case compute_file_hash(path) do
          {:ok, current_hash} -> current_hash != old_info.hash
          {:error, _} -> true
        end
    end
  end

  # Private functions

  defp build_file_info(path) do
    with {:ok, stat} <- File.stat(path),
         {:ok, hash} <- compute_file_hash(path) do
      {:ok,
       %{
         hash: hash,
         mtime: stat.mtime |> to_unix_time(),
         size: stat.size
       }}
    end
  end

  defp to_unix_time({{year, month, day}, {hour, min, sec}}) do
    NaiveDateTime.new!(year, month, day, hour, min, sec)
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_unix()
  end

  defp to_unix_time(other), do: other

  defp has_extension?(path, extensions) do
    ext = Path.extname(path) |> String.downcase()
    ext in extensions
  end

  defp excluded?(path, exclude_patterns) do
    Enum.any?(exclude_patterns, fn pattern ->
      String.contains?(path, pattern)
    end)
  end
end
