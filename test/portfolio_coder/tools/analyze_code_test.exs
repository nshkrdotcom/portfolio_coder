defmodule PortfolioCoder.Tools.AnalyzeCodeTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Tools.AnalyzeCode

  describe "definition/0" do
    test "returns tool definition with required fields" do
      definition = AnalyzeCode.definition()

      assert definition.name == "analyze_code"
      assert is_binary(definition.description)
      assert Map.has_key?(definition.parameters, :properties)
      assert "path" in definition.parameters.required
    end
  end

  describe "execute/1" do
    setup do
      tmp_dir =
        Path.join(System.tmp_dir!(), "portfolio_coder_analyze_test_#{:rand.uniform(10000)}")

      File.mkdir_p!(tmp_dir)

      elixir_file = Path.join(tmp_dir, "app.ex")

      elixir_content = """
      defmodule MyApp do
        @moduledoc "Main application module"

        alias MyApp.Helper
        import Enum

        def start do
          Helper.init()
        end

        def process(items) do
          items
          |> map(&transform/1)
          |> filter(&valid?/1)
        end

        defp transform(item), do: item
        defp valid?(_item), do: true
      end
      """

      File.write!(elixir_file, elixir_content)

      python_file = Path.join(tmp_dir, "app.py")

      python_content = """
      import os
      from typing import List

      class App:
          def __init__(self):
              pass

          def run(self):
              return True

      def main():
          app = App()
          app.run()
      """

      File.write!(python_file, python_content)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir, elixir_file: elixir_file, python_file: python_file}
    end

    test "analyzes Elixir file structure", %{elixir_file: elixir_file} do
      {:ok, result} =
        AnalyzeCode.execute(%{"path" => elixir_file, "analysis_type" => "structure"})

      assert result.path == elixir_file
      assert result.language == :elixir
      assert is_map(result.result)
    end

    test "analyzes Python file structure", %{python_file: python_file} do
      {:ok, result} =
        AnalyzeCode.execute(%{"path" => python_file, "analysis_type" => "structure"})

      assert result.path == python_file
      assert result.language == :python
      assert is_map(result.result)
    end

    test "analyzes complexity", %{elixir_file: elixir_file} do
      {:ok, result} =
        AnalyzeCode.execute(%{"path" => elixir_file, "analysis_type" => "complexity"})

      complexity = result.result
      assert complexity.total_lines > 0
      assert complexity.code_lines > 0
      assert complexity.function_count > 0
    end

    test "analyzes dependencies", %{elixir_file: elixir_file} do
      {:ok, result} =
        AnalyzeCode.execute(%{"path" => elixir_file, "analysis_type" => "dependencies"})

      deps = result.result
      assert Map.has_key?(deps, :imports) or Map.has_key?(deps, :aliases)
    end

    test "analyzes all aspects", %{elixir_file: elixir_file} do
      {:ok, result} = AnalyzeCode.execute(%{"path" => elixir_file, "analysis_type" => "all"})

      assert Map.has_key?(result.result, :structure)
      assert Map.has_key?(result.result, :dependencies)
      assert Map.has_key?(result.result, :complexity)
    end

    test "analyzes directory", %{tmp_dir: tmp_dir} do
      {:ok, result} = AnalyzeCode.execute(%{"path" => tmp_dir, "analysis_type" => "structure"})

      assert result.files_analyzed >= 2
      assert is_map(result.summary)
    end

    test "returns error for non-existent path" do
      result = AnalyzeCode.execute(%{"path" => "/non/existent/file.ex"})
      assert {:error, :path_not_found} = result
    end
  end
end
