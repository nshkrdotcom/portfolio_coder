defmodule PortfolioCoder.Tools.ReadFileTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Tools.ReadFile

  describe "definition/0" do
    test "returns tool definition with required fields" do
      definition = ReadFile.definition()

      assert definition.name == "read_file"
      assert is_binary(definition.description)
      assert Map.has_key?(definition.parameters, :properties)
      assert "path" in definition.parameters.required
    end
  end

  describe "execute/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "portfolio_coder_read_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(tmp_dir)

      test_file = Path.join(tmp_dir, "test.ex")

      content = """
      defmodule Test do
        def hello do
          :world
        end

        def goodbye do
          :farewell
        end
      end
      """

      File.write!(test_file, content)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir, test_file: test_file}
    end

    test "reads entire file", %{test_file: test_file} do
      {:ok, result} = ReadFile.execute(%{"path" => test_file})

      assert result.path == test_file
      assert result.language == "elixir"
      assert String.contains?(result.content, "defmodule Test")
      assert result.total_lines > 0
    end

    test "reads file with line numbers", %{test_file: test_file} do
      {:ok, result} = ReadFile.execute(%{"path" => test_file, "include_line_numbers" => true})

      assert String.contains?(result.content, "1 |")
      assert String.contains?(result.content, "2 |")
    end

    test "reads file without line numbers", %{test_file: test_file} do
      {:ok, result} = ReadFile.execute(%{"path" => test_file, "include_line_numbers" => false})

      refute String.match?(result.content, ~r/^\s*\d+\s*\|/)
    end

    test "reads specific line range", %{test_file: test_file} do
      {:ok, result} =
        ReadFile.execute(%{"path" => test_file, "start_line" => 2, "end_line" => 4})

      assert result.start_line == 2
      assert result.end_line == 4
    end

    test "returns error for non-existent file" do
      result = ReadFile.execute(%{"path" => "/non/existent/file.ex"})
      assert {:error, :file_not_found} = result
    end

    test "returns error for directory" do
      result = ReadFile.execute(%{"path" => System.tmp_dir!()})
      assert {:error, :is_directory} = result
    end

    test "detects language from extension", %{tmp_dir: tmp_dir} do
      py_file = Path.join(tmp_dir, "test.py")
      File.write!(py_file, "print('hello')")

      {:ok, result} = ReadFile.execute(%{"path" => py_file})
      assert result.language == "python"
    end
  end
end
