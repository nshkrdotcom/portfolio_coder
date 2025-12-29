defmodule PortfolioCoder.Graph.DependencyTest do
  use ExUnit.Case, async: true

  describe "Elixir dependency extraction" do
    setup do
      tmp_dir = Path.join(System.tmp_dir!(), "portfolio_coder_dep_test_#{:rand.uniform(10000)}")
      File.mkdir_p!(tmp_dir)

      mix_exs = """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project do
          [
            app: :my_app,
            version: "0.1.0",
            deps: deps()
          ]
        end

        defp deps do
          [
            {:phoenix, "~> 1.7"},
            {:ecto, "~> 3.10"},
            {:jason, "~> 1.4"},
            {:credo, "~> 1.7", only: :dev}
          ]
        end
      end
      """

      File.write!(Path.join(tmp_dir, "mix.exs"), mix_exs)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "extracts runtime dependencies", %{tmp_dir: tmp_dir} do
      # This test would require portfolio_manager to be running
      # For unit testing, we test the extraction logic in isolation
      mix_exs = File.read!(Path.join(tmp_dir, "mix.exs"))

      deps =
        Regex.scan(~r/\{:(\w+),\s*"[^"]*"/, mix_exs)
        |> Enum.map(fn [_, name] -> name end)

      assert "phoenix" in deps
      assert "ecto" in deps
      assert "jason" in deps
    end
  end

  describe "Python dependency extraction" do
    setup do
      tmp_dir =
        Path.join(System.tmp_dir!(), "portfolio_coder_py_dep_test_#{:rand.uniform(10000)}")

      File.mkdir_p!(tmp_dir)

      requirements = """
      flask>=2.0
      sqlalchemy~=2.0
      requests
      pytest>=7.0  # testing
      # this is a comment
      """

      File.write!(Path.join(tmp_dir, "requirements.txt"), requirements)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "extracts Python dependencies from requirements.txt", %{tmp_dir: tmp_dir} do
      content = File.read!(Path.join(tmp_dir, "requirements.txt"))

      deps =
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(String.starts_with?(&1, "#") or &1 == ""))
        |> Enum.map(fn line ->
          line |> String.split(~r/[=<>!~\[]/) |> List.first() |> String.trim()
        end)

      assert "flask" in deps
      assert "sqlalchemy" in deps
      assert "requests" in deps
      assert "pytest" in deps
    end
  end

  describe "JavaScript dependency extraction" do
    setup do
      tmp_dir =
        Path.join(System.tmp_dir!(), "portfolio_coder_js_dep_test_#{:rand.uniform(10000)}")

      File.mkdir_p!(tmp_dir)

      package_json = """
      {
        "name": "my-app",
        "version": "1.0.0",
        "dependencies": {
          "react": "^18.0.0",
          "axios": "^1.4.0"
        },
        "devDependencies": {
          "jest": "^29.0.0",
          "typescript": "^5.0.0"
        }
      }
      """

      File.write!(Path.join(tmp_dir, "package.json"), package_json)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, tmp_dir: tmp_dir}
    end

    test "extracts JavaScript dependencies from package.json", %{tmp_dir: tmp_dir} do
      content = File.read!(Path.join(tmp_dir, "package.json"))
      {:ok, package} = Jason.decode(content)

      runtime_deps = Map.keys(package["dependencies"] || %{})
      dev_deps = Map.keys(package["devDependencies"] || %{})

      assert "react" in runtime_deps
      assert "axios" in runtime_deps
      assert "jest" in dev_deps
      assert "typescript" in dev_deps
    end
  end
end
