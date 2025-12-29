defmodule PortfolioCoder.GraphTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Graph

  describe "detect_project_language/1" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "portfolio_coder_graph_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "detects Elixir project", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "mix.exs"), "")
      assert Graph.detect_project_language(tmp_dir) == :elixir
    end

    test "detects Python project with pyproject.toml", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "pyproject.toml"), "")
      assert Graph.detect_project_language(tmp_dir) == :python
    end

    test "detects Python project with requirements.txt", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "requirements.txt"), "")
      assert Graph.detect_project_language(tmp_dir) == :python
    end

    test "detects Python project with setup.py", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "setup.py"), "")
      assert Graph.detect_project_language(tmp_dir) == :python
    end

    test "detects JavaScript project", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "package.json"), "{}")
      assert Graph.detect_project_language(tmp_dir) == :javascript
    end

    test "detects TypeScript project", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "tsconfig.json"), "{}")
      assert Graph.detect_project_language(tmp_dir) == :typescript
    end

    test "returns unknown for unrecognized project", %{tmp_dir: tmp_dir} do
      assert Graph.detect_project_language(tmp_dir) == :unknown
    end
  end

  describe "build_dependency_graph/3" do
    test "returns error for non-existent directory" do
      result = Graph.build_dependency_graph("test", "/non/existent/path")
      assert {:error, {:not_a_directory, _}} = result
    end
  end
end
