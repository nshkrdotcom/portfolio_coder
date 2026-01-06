defmodule PortfolioCoder.Portfolio.RegistryTest do
  use ExUnit.Case, async: false

  alias PortfolioCoder.Portfolio.Registry
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

  describe "list_repos/1" do
    test "returns empty list when no repos", %{portfolio_path: _path} do
      assert {:ok, []} = Registry.list_repos()
    end

    test "returns list of repos after adding", %{portfolio_path: _path} do
      {:ok, _repo} =
        Registry.add_repo(%{
          id: "test_repo",
          name: "Test Repo",
          path: "/tmp/test_repo",
          language: :elixir,
          type: :library,
          status: :active
        })

      assert {:ok, repos} = Registry.list_repos()
      assert length(repos) == 1
      assert hd(repos).id == "test_repo"
    end
  end

  describe "get_repo/1" do
    test "returns error when repo not found" do
      assert {:error, :not_found} = Registry.get_repo("nonexistent")
    end

    test "returns repo when found", %{portfolio_path: _path} do
      {:ok, _} =
        Registry.add_repo(%{
          id: "my_repo",
          name: "My Repo",
          path: "/tmp/my_repo",
          language: :elixir,
          type: :library,
          status: :active
        })

      assert {:ok, repo} = Registry.get_repo("my_repo")
      assert repo.id == "my_repo"
      assert repo.name == "My Repo"
    end
  end

  describe "add_repo/1" do
    test "adds a new repo to registry", %{portfolio_path: _path} do
      attrs = %{
        id: "new_repo",
        name: "New Repo",
        path: "/tmp/new_repo",
        language: :python,
        type: :application,
        status: :active,
        tags: ["web", "api"]
      }

      assert {:ok, repo} = Registry.add_repo(attrs)
      assert repo.id == "new_repo"
      assert repo.language == :python
      assert repo.tags == ["web", "api"]
      assert repo.created_at != nil
      assert repo.updated_at != nil
    end

    test "returns error for duplicate id", %{portfolio_path: _path} do
      attrs = %{
        id: "dup_repo",
        name: "Dup",
        path: "/tmp/dup",
        language: :elixir,
        type: :library,
        status: :active
      }

      assert {:ok, _} = Registry.add_repo(attrs)
      assert {:error, :already_exists} = Registry.add_repo(attrs)
    end

    test "requires id field" do
      assert {:error, :missing_id} = Registry.add_repo(%{name: "No ID"})
    end
  end

  describe "update_repo/2" do
    test "updates existing repo", %{portfolio_path: _path} do
      {:ok, _} =
        Registry.add_repo(%{
          id: "update_me",
          name: "Original",
          path: "/tmp/update_me",
          language: :elixir,
          type: :library,
          status: :active
        })

      assert {:ok, updated} = Registry.update_repo("update_me", %{status: :stale, priority: :low})
      assert updated.status == :stale
      assert updated.priority == :low
      # unchanged
      assert updated.name == "Original"
    end

    test "returns error for nonexistent repo" do
      assert {:error, :not_found} = Registry.update_repo("nonexistent", %{status: :active})
    end
  end

  describe "remove_repo/1" do
    test "removes repo from registry", %{portfolio_path: _path} do
      {:ok, _} =
        Registry.add_repo(%{
          id: "remove_me",
          name: "Remove Me",
          path: "/tmp/remove_me",
          language: :elixir,
          type: :library,
          status: :active
        })

      assert :ok = Registry.remove_repo("remove_me")
      assert {:error, :not_found} = Registry.get_repo("remove_me")
    end

    test "returns error for nonexistent repo" do
      assert {:error, :not_found} = Registry.remove_repo("nonexistent")
    end
  end

  describe "filter_by/2" do
    setup %{portfolio_path: _path} do
      # Add some test repos
      {:ok, _} =
        Registry.add_repo(%{
          id: "lib1",
          name: "Lib 1",
          path: "/tmp/lib1",
          language: :elixir,
          type: :library,
          status: :active
        })

      {:ok, _} =
        Registry.add_repo(%{
          id: "lib2",
          name: "Lib 2",
          path: "/tmp/lib2",
          language: :python,
          type: :library,
          status: :stale
        })

      {:ok, _} =
        Registry.add_repo(%{
          id: "app1",
          name: "App 1",
          path: "/tmp/app1",
          language: :elixir,
          type: :application,
          status: :active
        })

      :ok
    end

    test "filters by status" do
      assert {:ok, repos} = Registry.filter_by(:status, :active)
      assert length(repos) == 2
      assert Enum.all?(repos, &(&1.status == :active))
    end

    test "filters by type" do
      assert {:ok, repos} = Registry.filter_by(:type, :library)
      assert length(repos) == 2
      assert Enum.all?(repos, &(&1.type == :library))
    end

    test "filters by language" do
      assert {:ok, repos} = Registry.filter_by(:language, :elixir)
      assert length(repos) == 2
      assert Enum.all?(repos, &(&1.language == :elixir))
    end

    test "returns empty list for no matches" do
      assert {:ok, []} = Registry.filter_by(:language, :rust)
    end
  end

  describe "persistence" do
    test "repos persist across reloads", %{portfolio_path: _path} do
      {:ok, _} =
        Registry.add_repo(%{
          id: "persist_test",
          name: "Persist Test",
          path: "/tmp/persist_test",
          language: :elixir,
          type: :library,
          status: :active
        })

      # Force reload
      assert {:ok, repos} = Registry.list_repos()
      assert Enum.any?(repos, &(&1.id == "persist_test"))
    end
  end
end
