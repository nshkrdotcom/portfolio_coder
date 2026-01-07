defmodule PortfolioCoder.Portfolio.SyncerTest do
  use ExUnit.Case, async: false

  alias PortfolioCoder.Portfolio.{Context, Registry, Syncer}
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

  describe "sync_repo/2" do
    test "updates computed fields for a repo", %{portfolio_path: portfolio_path} do
      # Create a test repo
      repos_dir = Path.join(portfolio_path, "repos")
      repo_path = PortfolioFixtures.create_test_repo(repos_dir, "sync_test", language: :elixir)

      # Make a commit
      {_, 0} = System.cmd("git", ["add", "."], cd: repo_path, stderr_to_stdout: true)

      {_, 0} =
        System.cmd(
          "git",
          [
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@test.com",
            "commit",
            "-m",
            "Initial commit"
          ],
          cd: repo_path,
          stderr_to_stdout: true
        )

      # Register the repo
      {:ok, _} =
        Registry.add_repo(%{
          id: "sync_test",
          name: "Sync Test",
          path: repo_path,
          language: :elixir,
          type: :library,
          status: :active
        })

      # Create context
      Context.ensure_repo_dir("sync_test")

      # Sync
      assert {:ok, result} = Syncer.sync_repo("sync_test")
      assert result.computed != nil
      assert result.computed.last_commit != nil
    end
  end

  describe "get_git_info/1" do
    test "extracts git info from repo", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")
      repo_path = PortfolioFixtures.create_test_repo(repos_dir, "git_info", language: :elixir)

      # Make a commit
      {_, 0} = System.cmd("git", ["add", "."], cd: repo_path, stderr_to_stdout: true)

      {_, 0} =
        System.cmd(
          "git",
          [
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@test.com",
            "commit",
            "-m",
            "Test commit"
          ],
          cd: repo_path,
          stderr_to_stdout: true
        )

      assert {:ok, info} = Syncer.get_git_info(repo_path)
      assert info.last_commit != nil
      assert is_binary(info.last_commit.sha)
      assert info.last_commit.message =~ "Test commit"
    end

    test "returns error for non-git directory" do
      assert {:error, :not_a_git_repo} =
               Syncer.get_git_info("/tmp/not_a_repo_#{:rand.uniform(10000)}")
    end
  end

  describe "update_computed_fields/1" do
    test "updates computed section in context", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")

      repo_path =
        PortfolioFixtures.create_test_repo(repos_dir, "computed_test", language: :elixir)

      # Make a commit
      {_, 0} = System.cmd("git", ["add", "."], cd: repo_path, stderr_to_stdout: true)

      {_, 0} =
        System.cmd(
          "git",
          ["-c", "user.name=Test", "-c", "user.email=test@test.com", "commit", "-m", "Test"],
          cd: repo_path,
          stderr_to_stdout: true
        )

      # Register
      {:ok, _} =
        Registry.add_repo(%{
          id: "computed_test",
          name: "Computed Test",
          path: repo_path,
          language: :elixir,
          type: :library,
          status: :active
        })

      # Create initial context
      Context.save("computed_test", %{
        "id" => "computed_test",
        "name" => "Computed Test"
      })

      # Update computed
      assert {:ok, computed} = Syncer.update_computed_fields("computed_test")
      assert computed.last_commit != nil
      assert computed.dependencies != nil
    end
  end

  describe "sync_all/1" do
    test "syncs all registered repos", %{portfolio_path: portfolio_path} do
      repos_dir = Path.join(portfolio_path, "repos")

      # Create and register two repos
      for name <- ["sync_all_1", "sync_all_2"] do
        repo_path = PortfolioFixtures.create_test_repo(repos_dir, name, language: :elixir)

        {_, 0} = System.cmd("git", ["add", "."], cd: repo_path, stderr_to_stdout: true)

        {_, 0} =
          System.cmd(
            "git",
            ["-c", "user.name=Test", "-c", "user.email=test@test.com", "commit", "-m", "Init"],
            cd: repo_path,
            stderr_to_stdout: true
          )

        {:ok, _} =
          Registry.add_repo(%{
            id: name,
            name: name,
            path: repo_path,
            language: :elixir,
            type: :library,
            status: :active
          })

        Context.ensure_repo_dir(name)
      end

      assert {:ok, result} = Syncer.sync_all()
      assert result.synced == 2
      assert result.failed == 0
    end
  end
end
