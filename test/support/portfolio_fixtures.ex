defmodule PortfolioCoder.PortfolioFixtures do
  @moduledoc """
  Test fixtures for Portfolio integration tests.
  """

  @doc """
  Creates a temporary portfolio directory structure for testing.
  Returns the path to the temporary directory.
  """
  def setup_test_portfolio(opts \\ []) do
    tmp_dir =
      System.tmp_dir!()
      |> Path.join("portfolio_test_#{:rand.uniform(100_000)}")

    File.mkdir_p!(tmp_dir)
    File.mkdir_p!(Path.join(tmp_dir, "repos"))

    # Create config.yml
    config_content = Keyword.get(opts, :config, default_config(tmp_dir))
    File.write!(Path.join(tmp_dir, "config.yml"), config_content)

    # Create registry.yml
    registry_content = Keyword.get(opts, :registry, default_registry())
    File.write!(Path.join(tmp_dir, "registry.yml"), registry_content)

    # Create relationships.yml
    relationships_content = Keyword.get(opts, :relationships, default_relationships())
    File.write!(Path.join(tmp_dir, "relationships.yml"), relationships_content)

    tmp_dir
  end

  @doc """
  Cleans up a temporary portfolio directory.
  """
  def cleanup_test_portfolio(path) do
    File.rm_rf!(path)
  end

  @doc """
  Creates a test repository in the given base directory.
  Returns the path to the created repo.
  """
  def create_test_repo(base_dir, name, opts \\ []) do
    repo_path = Path.join(base_dir, name)
    File.mkdir_p!(repo_path)

    # Initialize git repo
    {_, 0} = System.cmd("git", ["init"], cd: repo_path, stderr_to_stdout: true)

    # Create language marker file
    language = Keyword.get(opts, :language, :elixir)
    create_language_marker(repo_path, language)

    # Create README if requested
    if Keyword.get(opts, :readme, true) do
      File.write!(Path.join(repo_path, "README.md"), "# #{name}\n\nTest repository.\n")
    end

    repo_path
  end

  @doc """
  Creates a repo context directory in the portfolio.
  """
  def create_repo_context(portfolio_path, repo_id, context_content) do
    repo_dir = Path.join([portfolio_path, "repos", repo_id])
    File.mkdir_p!(repo_dir)

    File.write!(Path.join(repo_dir, "context.yml"), context_content)
    repo_dir
  end

  # Private helpers

  defp default_config(tmp_dir) do
    """
    version: "1.0"

    portfolio:
      name: "Test Portfolio"
      owner: test_user

    scan:
      directories:
        - #{tmp_dir}/repos
      exclude_patterns:
        - "**/node_modules/**"
        - "**/.git/**"
        - "**/deps/**"
        - "**/_build/**"

    sync:
      auto_commit: false

    defaults:
      new_repo:
        status: active
        priority: medium
    """
  end

  defp default_registry do
    """
    repos: []
    """
  end

  defp default_relationships do
    """
    relationships: []
    """
  end

  defp create_language_marker(repo_path, :elixir) do
    File.write!(Path.join(repo_path, "mix.exs"), """
    defmodule TestProject.MixProject do
      use Mix.Project

      def project do
        [
          app: :test_project,
          version: "0.1.0",
          elixir: "~> 1.15",
          deps: []
        ]
      end
    end
    """)
  end

  defp create_language_marker(repo_path, :python) do
    File.write!(Path.join(repo_path, "requirements.txt"), """
    requests>=2.25.0
    flask>=2.0.0
    """)
  end

  defp create_language_marker(repo_path, :javascript) do
    File.write!(Path.join(repo_path, "package.json"), """
    {
      "name": "test-project",
      "version": "1.0.0",
      "dependencies": {
        "express": "^4.18.0"
      }
    }
    """)
  end

  defp create_language_marker(_repo_path, _language), do: :ok
end
