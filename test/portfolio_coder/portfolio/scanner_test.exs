defmodule PortfolioCoder.Portfolio.ScannerTest do
  use ExUnit.Case, async: false

  alias PortfolioCoder.Portfolio.Scanner
  alias PortfolioCoder.PortfolioFixtures

  setup do
    portfolio_path = PortfolioFixtures.setup_test_portfolio()

    # Save original env and app config
    original_env = System.get_env("PORTFOLIO_DIR")
    original_config = Application.get_env(:portfolio_coder, :portfolio_path)

    # Set test portfolio path via env var (takes precedence)
    System.put_env("PORTFOLIO_DIR", portfolio_path)
    Application.put_env(:portfolio_coder, :portfolio_path, portfolio_path)

    on_exit(fn ->
      # Restore original env and config
      if original_env do
        System.put_env("PORTFOLIO_DIR", original_env)
      else
        System.delete_env("PORTFOLIO_DIR")
      end

      if original_config do
        Application.put_env(:portfolio_coder, :portfolio_path, original_config)
      else
        Application.delete_env(:portfolio_coder, :portfolio_path)
      end

      PortfolioFixtures.cleanup_test_portfolio(portfolio_path)
    end)

    {:ok, portfolio_path: portfolio_path}
  end

  describe "scan/1" do
    test "discovers repos in configured directories", %{portfolio_path: portfolio_path} do
      # Create some test repos
      repos_dir = Path.join(portfolio_path, "repos")
      PortfolioFixtures.create_test_repo(repos_dir, "test_elixir", language: :elixir)
      PortfolioFixtures.create_test_repo(repos_dir, "test_python", language: :python)

      assert {:ok, results} = Scanner.scan()
      assert length(results) >= 2

      names = Enum.map(results, & &1.name)
      assert "test_elixir" in names
      assert "test_python" in names
    end

    test "marks repos as new if not in registry", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")
      PortfolioFixtures.create_test_repo(repos_dir, "new_repo", language: :elixir)

      assert {:ok, results} = Scanner.scan()
      new_repo = Enum.find(results, &(&1.name == "new_repo"))

      assert new_repo != nil
      assert new_repo.is_new == true
    end
  end

  describe "scan_directory/2" do
    test "scans a single directory", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")
      PortfolioFixtures.create_test_repo(repos_dir, "single_dir_test", language: :elixir)

      assert {:ok, results} = Scanner.scan_directory(repos_dir)
      assert results != []
    end

    test "excludes directories matching patterns", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")

      # Create a normal repo and a node_modules dir
      PortfolioFixtures.create_test_repo(repos_dir, "real_repo", language: :elixir)
      File.mkdir_p!(Path.join([repos_dir, "node_modules", "fake_package"]))
      File.mkdir_p!(Path.join([repos_dir, "node_modules", "fake_package", ".git"]))

      assert {:ok, results} = Scanner.scan_directory(repos_dir)
      names = Enum.map(results, & &1.name)

      assert "real_repo" in names
      refute "fake_package" in names
    end
  end

  describe "detect_language/1" do
    test "detects Elixir from mix.exs", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")
      repo_path = PortfolioFixtures.create_test_repo(repos_dir, "elixir_proj", language: :elixir)

      assert Scanner.detect_language(repo_path) == :elixir
    end

    test "detects Python from requirements.txt", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")
      repo_path = PortfolioFixtures.create_test_repo(repos_dir, "python_proj", language: :python)

      assert Scanner.detect_language(repo_path) == :python
    end

    test "detects JavaScript from package.json", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")
      repo_path = PortfolioFixtures.create_test_repo(repos_dir, "js_proj", language: :javascript)

      assert Scanner.detect_language(repo_path) == :javascript
    end

    test "returns nil for unknown language", %{portfolio_path: portfolio_path} do
      empty_dir = Path.join([portfolio_path, "repos", "unknown"])
      File.mkdir_p!(empty_dir)

      assert Scanner.detect_language(empty_dir) == nil
    end
  end

  describe "detect_type/1" do
    test "detects library type from mix.exs", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")
      repo_path = PortfolioFixtures.create_test_repo(repos_dir, "lib_proj", language: :elixir)

      # Default type from fixture is library
      assert Scanner.detect_type(repo_path) == :library
    end
  end

  describe "extract_remotes/1" do
    test "extracts git remotes", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")
      repo_path = PortfolioFixtures.create_test_repo(repos_dir, "with_remote", language: :elixir)

      # Add a remote
      {_, 0} =
        System.cmd("git", ["remote", "add", "origin", "git@github.com:test/repo.git"],
          cd: repo_path,
          stderr_to_stdout: true
        )

      remotes = Scanner.extract_remotes(repo_path)
      assert length(remotes) == 1
      assert hd(remotes).name == "origin"
      assert hd(remotes).url == "git@github.com:test/repo.git"
    end

    test "returns empty list for repo without remotes", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")
      repo_path = PortfolioFixtures.create_test_repo(repos_dir, "no_remote", language: :elixir)

      remotes = Scanner.extract_remotes(repo_path)
      assert remotes == []
    end
  end

  describe "git_repo?/1" do
    test "returns true for git repos", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")
      repo_path = PortfolioFixtures.create_test_repo(repos_dir, "git_repo", language: :elixir)

      assert Scanner.git_repo?(repo_path) == true
    end

    test "returns false for non-git directories", %{portfolio_path: portfolio_path} do
      non_git = Path.join([portfolio_path, "not_a_repo"])
      File.mkdir_p!(non_git)

      assert Scanner.git_repo?(non_git) == false
    end
  end

  describe "extract_dependencies/2" do
    test "extracts Elixir dependencies from mix.exs", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")
      repo_path = Path.join(repos_dir, "with_deps")
      File.mkdir_p!(repo_path)

      File.write!(Path.join(repo_path, "mix.exs"), """
      defmodule MyApp.MixProject do
        use Mix.Project

        def project, do: [app: :my_app, version: "0.1.0", deps: deps()]

        defp deps do
          [
            {:ecto, "~> 3.0"},
            {:phoenix, "~> 1.7"},
            {:credo, "~> 1.7", only: :dev}
          ]
        end
      end
      """)

      deps = Scanner.extract_dependencies(repo_path, :elixir)

      assert "ecto" in deps.runtime
      assert "phoenix" in deps.runtime
      assert "credo" in deps.dev
    end
  end
end
