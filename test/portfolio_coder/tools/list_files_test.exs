defmodule PortfolioCoder.Tools.ListFilesTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Tools.ListFiles

  describe "definition/0" do
    test "returns tool definition with required fields" do
      definition = ListFiles.definition()

      assert definition.name == "list_files"
      assert is_binary(definition.description)
      assert Map.has_key?(definition.parameters, :properties)
      assert "path" in definition.parameters.required
    end
  end

  describe "execute/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "portfolio_coder_list_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.mkdir_p!(Path.join(tmp_dir, "test"))
      File.mkdir_p!(Path.join(tmp_dir, ".hidden"))

      File.write!(Path.join(tmp_dir, "lib/app.ex"), "")
      File.write!(Path.join(tmp_dir, "lib/helper.ex"), "")
      File.write!(Path.join(tmp_dir, "test/app_test.exs"), "")
      File.write!(Path.join(tmp_dir, ".hidden/secret.ex"), "")
      File.write!(Path.join(tmp_dir, "README.md"), "")

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "lists all files recursively", %{tmp_dir: tmp_dir} do
      {:ok, result} = ListFiles.execute(%{"path" => tmp_dir})

      assert result.count >= 3
      filenames = Enum.map(result.files, & &1.name)
      assert "app.ex" in filenames
      assert "helper.ex" in filenames
      assert "README.md" in filenames
    end

    test "filters by extension", %{tmp_dir: tmp_dir} do
      {:ok, result} = ListFiles.execute(%{"path" => tmp_dir, "extensions" => [".ex", ".exs"]})

      extensions = result.files |> Enum.map(& &1.extension) |> Enum.uniq()
      assert Enum.all?(extensions, &(&1 in [".ex", ".exs"]))
    end

    test "excludes hidden files by default", %{tmp_dir: tmp_dir} do
      {:ok, result} = ListFiles.execute(%{"path" => tmp_dir})

      paths = Enum.map(result.files, & &1.path)
      refute Enum.any?(paths, &String.contains?(&1, ".hidden"))
    end

    test "includes hidden files when requested", %{tmp_dir: tmp_dir} do
      {:ok, result} = ListFiles.execute(%{"path" => tmp_dir, "include_hidden" => true})

      paths = Enum.map(result.files, & &1.path)
      assert Enum.any?(paths, &String.contains?(&1, ".hidden"))
    end

    test "returns error for non-existent path" do
      result = ListFiles.execute(%{"path" => "/non/existent/path"})
      assert {:error, :path_not_found} = result
    end

    test "returns error for file path" do
      file = Path.join(System.tmp_dir!(), "temp_file_#{:rand.uniform(10000)}")
      File.write!(file, "")

      on_exit(fn -> File.rm(file) end)

      result = ListFiles.execute(%{"path" => file})
      assert {:error, :not_a_directory} = result
    end

    test "respects glob pattern", %{tmp_dir: tmp_dir} do
      {:ok, result} = ListFiles.execute(%{"path" => tmp_dir, "pattern" => "**/*.ex"})

      extensions = Enum.map(result.files, & &1.extension)
      assert Enum.all?(extensions, &(&1 == ".ex"))
    end

    test "includes file metadata", %{tmp_dir: tmp_dir} do
      {:ok, result} = ListFiles.execute(%{"path" => tmp_dir})

      [file | _] = result.files
      assert Map.has_key?(file, :path)
      assert Map.has_key?(file, :name)
      assert Map.has_key?(file, :extension)
      assert Map.has_key?(file, :size)
      assert Map.has_key?(file, :language)
    end
  end
end
