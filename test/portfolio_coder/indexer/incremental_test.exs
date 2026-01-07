defmodule PortfolioCoder.Indexer.IncrementalTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Indexer.Incremental

  @test_dir "test/fixtures/incremental_test"
  @state_file "test/fixtures/incremental_test/.index_state"

  setup do
    File.mkdir_p!(@test_dir)

    File.write!(Path.join(@test_dir, "unchanged.ex"), """
    defmodule Unchanged do
      def hello, do: "world"
    end
    """)

    File.write!(Path.join(@test_dir, "modified.ex"), """
    defmodule Modified do
      def original, do: :original
    end
    """)

    on_exit(fn ->
      File.rm_rf!(@test_dir)
    end)

    {:ok, dir: @test_dir, state_file: @state_file}
  end

  describe "compute_hash/1" do
    test "returns consistent hash for same content" do
      content = "defmodule Test do\nend"
      hash1 = Incremental.compute_hash(content)
      hash2 = Incremental.compute_hash(content)

      assert hash1 == hash2
      assert is_binary(hash1)
      # SHA256 hex
      assert byte_size(hash1) == 64
    end

    test "returns different hash for different content" do
      hash1 = Incremental.compute_hash("content a")
      hash2 = Incremental.compute_hash("content b")

      assert hash1 != hash2
    end
  end

  describe "compute_file_hash/1" do
    test "computes hash from file path", %{dir: dir} do
      path = Path.join(dir, "unchanged.ex")
      {:ok, hash} = Incremental.compute_file_hash(path)

      assert is_binary(hash)
      assert byte_size(hash) == 64
    end

    test "returns error for nonexistent file" do
      result = Incremental.compute_file_hash("/nonexistent/file.ex")
      assert {:error, _} = result
    end
  end

  describe "build_state/2" do
    test "builds state map from directory", %{dir: dir} do
      state = Incremental.build_state(dir, extensions: [".ex"])

      assert is_map(state)
      assert map_size(state) >= 2

      Enum.each(state, fn {path, info} ->
        assert String.ends_with?(path, ".ex")
        assert is_binary(info.hash)
        assert is_integer(info.mtime)
      end)
    end

    test "respects extension filter", %{dir: dir} do
      File.write!(Path.join(dir, "other.txt"), "text content")

      state = Incremental.build_state(dir, extensions: [".ex"])

      paths = Map.keys(state)
      assert Enum.all?(paths, &String.ends_with?(&1, ".ex"))
    end
  end

  describe "detect_changes/2" do
    test "detects new files", %{dir: dir} do
      old_state = %{}
      new_state = Incremental.build_state(dir, extensions: [".ex"])

      changes = Incremental.detect_changes(old_state, new_state)

      assert length(changes.added) >= 2
      assert changes.modified == []
      assert changes.deleted == []
    end

    test "detects modified files", %{dir: dir} do
      old_state = Incremental.build_state(dir, extensions: [".ex"])

      # Modify a file
      modified_path = Path.join(dir, "modified.ex")

      File.write!(modified_path, """
      defmodule Modified do
        def changed, do: :changed
      end
      """)

      # Ensure mtime changes
      Process.sleep(10)

      new_state = Incremental.build_state(dir, extensions: [".ex"])
      changes = Incremental.detect_changes(old_state, new_state)

      modified_paths = Enum.map(changes.modified, & &1.path)
      assert modified_path in modified_paths
    end

    test "detects deleted files", %{dir: dir} do
      old_state = Incremental.build_state(dir, extensions: [".ex"])

      # Delete a file
      deleted_path = Path.join(dir, "modified.ex")
      File.rm!(deleted_path)

      new_state = Incremental.build_state(dir, extensions: [".ex"])
      changes = Incremental.detect_changes(old_state, new_state)

      assert deleted_path in changes.deleted
    end

    test "ignores unchanged files", %{dir: dir} do
      state1 = Incremental.build_state(dir, extensions: [".ex"])
      state2 = Incremental.build_state(dir, extensions: [".ex"])

      changes = Incremental.detect_changes(state1, state2)

      assert changes.added == []
      assert changes.modified == []
      assert changes.deleted == []
    end
  end

  describe "save_state/2 and load_state/1" do
    test "persists and loads state", %{dir: dir, state_file: state_file} do
      state = Incremental.build_state(dir, extensions: [".ex"])

      :ok = Incremental.save_state(state, state_file)
      assert File.exists?(state_file)

      {:ok, loaded} = Incremental.load_state(state_file)
      assert loaded == state
    end

    test "load returns error for missing file" do
      result = Incremental.load_state("/nonexistent/state.json")
      assert {:error, _} = result
    end
  end

  describe "incremental_scan/2" do
    test "returns all files on first scan", %{dir: dir, state_file: state_file} do
      # Ensure no existing state
      File.rm(state_file)

      {:ok, changeset, _new_state} =
        Incremental.incremental_scan(dir,
          state_file: state_file,
          extensions: [".ex"]
        )

      assert length(changeset.added) >= 2
      assert changeset.modified == []
      assert changeset.deleted == []
    end

    test "returns only changes on subsequent scans", %{dir: dir, state_file: state_file} do
      # First scan
      {:ok, _changeset, _state} =
        Incremental.incremental_scan(dir,
          state_file: state_file,
          extensions: [".ex"]
        )

      # Add a new file
      new_file = Path.join(dir, "new_file.ex")
      File.write!(new_file, "defmodule NewFile do\nend")
      Process.sleep(10)

      # Second scan
      {:ok, changeset, _new_state} =
        Incremental.incremental_scan(dir,
          state_file: state_file,
          extensions: [".ex"]
        )

      added_paths = Enum.map(changeset.added, & &1.path)
      assert new_file in added_paths
    end
  end

  describe "needs_reindex?/2" do
    test "returns true for changed files", %{dir: dir} do
      state = Incremental.build_state(dir, extensions: [".ex"])
      path = Path.join(dir, "unchanged.ex")

      # Change content
      File.write!(path, "defmodule Changed do\nend")

      assert Incremental.needs_reindex?(path, state)
    end

    test "returns false for unchanged files", %{dir: dir} do
      state = Incremental.build_state(dir, extensions: [".ex"])
      path = Path.join(dir, "unchanged.ex")

      refute Incremental.needs_reindex?(path, state)
    end

    test "returns true for new files" do
      state = %{}
      assert Incremental.needs_reindex?("/some/new/file.ex", state)
    end
  end
end
