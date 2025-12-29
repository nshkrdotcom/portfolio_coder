defmodule PortfolioCoder.IndexerTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Indexer

  describe "detect_language/1" do
    test "detects Elixir files" do
      assert Indexer.detect_language("lib/my_app.ex") == :elixir
      assert Indexer.detect_language("test/my_app_test.exs") == :elixir
    end

    test "detects Python files" do
      assert Indexer.detect_language("main.py") == :python
      assert Indexer.detect_language("gui.pyw") == :python
    end

    test "detects JavaScript files" do
      assert Indexer.detect_language("app.js") == :javascript
      assert Indexer.detect_language("component.jsx") == :javascript
      assert Indexer.detect_language("module.mjs") == :javascript
    end

    test "detects TypeScript files" do
      assert Indexer.detect_language("app.ts") == :typescript
      assert Indexer.detect_language("component.tsx") == :typescript
    end

    test "detects other file types" do
      assert Indexer.detect_language("README.md") == :markdown
      assert Indexer.detect_language("config.json") == :json
      assert Indexer.detect_language("config.yml") == :yaml
      assert Indexer.detect_language("config.yaml") == :yaml
    end

    test "returns unknown for unrecognized extensions" do
      assert Indexer.detect_language("file.xyz") == :unknown
      assert Indexer.detect_language("file") == :unknown
    end
  end

  describe "scan_files/3" do
    setup do
      # Create a temporary directory structure for testing
      tmp_dir = Path.join(System.tmp_dir!(), "portfolio_coder_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(Path.join(tmp_dir, "lib"))
      File.mkdir_p!(Path.join(tmp_dir, "test"))
      File.mkdir_p!(Path.join(tmp_dir, "deps/some_dep"))

      # Create test files
      File.write!(Path.join(tmp_dir, "lib/app.ex"), "defmodule App do end")
      File.write!(Path.join(tmp_dir, "lib/app.py"), "class App: pass")
      File.write!(Path.join(tmp_dir, "test/app_test.exs"), "defmodule AppTest do end")
      File.write!(Path.join(tmp_dir, "deps/some_dep/dep.ex"), "defmodule Dep do end")
      File.write!(Path.join(tmp_dir, "README.md"), "# README")

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "scans files with specified languages", %{tmp_dir: tmp_dir} do
      files = Indexer.scan_files(tmp_dir, [:elixir], [])

      paths = Enum.map(files, & &1.path)
      assert Enum.any?(paths, &String.ends_with?(&1, "app.ex"))
      assert Enum.any?(paths, &String.ends_with?(&1, "app_test.exs"))
      refute Enum.any?(paths, &String.ends_with?(&1, "app.py"))
    end

    test "respects exclude patterns", %{tmp_dir: tmp_dir} do
      files = Indexer.scan_files(tmp_dir, [:elixir], ["deps/"])

      paths = Enum.map(files, & &1.path)
      refute Enum.any?(paths, &String.contains?(&1, "deps/"))
    end

    test "includes relative_path in results", %{tmp_dir: tmp_dir} do
      files = Indexer.scan_files(tmp_dir, [:elixir], ["deps/"])

      file = Enum.find(files, &(&1.relative_path == "lib/app.ex"))
      assert file != nil
      assert file.type == :elixir
    end
  end

  describe "index_repo/2" do
    test "returns error for non-existent directory" do
      result = Indexer.index_repo("/non/existent/path")
      assert {:error, {:not_a_directory, _}} = result
    end
  end
end
