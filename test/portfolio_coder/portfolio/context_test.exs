defmodule PortfolioCoder.Portfolio.ContextTest do
  use ExUnit.Case, async: false

  alias PortfolioCoder.Portfolio.Context
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

  describe "load/1" do
    test "returns error when repo context doesn't exist" do
      assert {:error, :not_found} = Context.load("nonexistent")
    end

    test "loads context from existing repo", %{portfolio_path: portfolio_path} do
      context_content = """
      id: test_repo
      name: Test Repo
      path: /tmp/test_repo
      language: elixir
      type: library
      status: active
      purpose: A test repository
      """

      PortfolioFixtures.create_repo_context(portfolio_path, "test_repo", context_content)

      assert {:ok, context} = Context.load("test_repo")
      assert context["id"] == "test_repo"
      assert context["name"] == "Test Repo"
      assert context["purpose"] == "A test repository"
    end
  end

  describe "save/2" do
    test "creates context file for new repo", %{portfolio_path: _path} do
      context = %{
        "id" => "new_repo",
        "name" => "New Repo",
        "path" => "/tmp/new_repo",
        "language" => "elixir",
        "type" => "library",
        "status" => "active"
      }

      assert :ok = Context.save("new_repo", context)
      assert {:ok, loaded} = Context.load("new_repo")
      assert loaded["id"] == "new_repo"
    end

    test "updates existing context", %{portfolio_path: portfolio_path} do
      initial = """
      id: update_me
      name: Original
      status: active
      """

      PortfolioFixtures.create_repo_context(portfolio_path, "update_me", initial)

      updated = %{
        "id" => "update_me",
        "name" => "Updated Name",
        "status" => "stale"
      }

      assert :ok = Context.save("update_me", updated)
      assert {:ok, loaded} = Context.load("update_me")
      assert loaded["name"] == "Updated Name"
      assert loaded["status"] == "stale"
    end
  end

  describe "get_notes/1" do
    test "returns error when notes don't exist" do
      assert {:error, :not_found} = Context.get_notes("no_notes")
    end

    test "returns notes content", %{portfolio_path: portfolio_path} do
      repo_dir = Path.join([portfolio_path, "repos", "with_notes"])
      File.mkdir_p!(repo_dir)
      File.write!(Path.join(repo_dir, "notes.md"), "# Notes\n\nSome notes here.")

      assert {:ok, notes} = Context.get_notes("with_notes")
      assert notes =~ "# Notes"
      assert notes =~ "Some notes here"
    end
  end

  describe "save_notes/2" do
    test "creates notes file", %{portfolio_path: portfolio_path} do
      # Ensure repo dir exists
      repo_dir = Path.join([portfolio_path, "repos", "notes_test"])
      File.mkdir_p!(repo_dir)

      notes = "# My Notes\n\nThese are my notes."

      assert :ok = Context.save_notes("notes_test", notes)
      assert {:ok, loaded} = Context.get_notes("notes_test")
      assert loaded == notes
    end
  end

  describe "ensure_repo_dir/1" do
    test "creates repo directory if missing", %{portfolio_path: portfolio_path} do
      repo_id = "new_repo_dir"
      repo_path = Path.join([portfolio_path, "repos", repo_id])

      refute File.dir?(repo_path)

      assert :ok = Context.ensure_repo_dir(repo_id)
      assert File.dir?(repo_path)
    end

    test "succeeds if directory already exists", %{portfolio_path: portfolio_path} do
      repo_id = "existing_dir"
      repo_path = Path.join([portfolio_path, "repos", repo_id])
      File.mkdir_p!(repo_path)

      assert :ok = Context.ensure_repo_dir(repo_id)
    end
  end

  describe "update_field/3" do
    test "updates a single field", %{portfolio_path: portfolio_path} do
      context_content = """
      id: field_test
      name: Original
      status: active
      """

      PortfolioFixtures.create_repo_context(portfolio_path, "field_test", context_content)

      assert :ok = Context.update_field("field_test", "status", "stale")
      assert {:ok, loaded} = Context.load("field_test")
      assert loaded["status"] == "stale"
      # unchanged
      assert loaded["name"] == "Original"
    end
  end

  describe "get_field/2" do
    test "returns field value", %{portfolio_path: portfolio_path} do
      context_content = """
      id: get_field_test
      name: Test Name
      purpose: Test purpose
      """

      PortfolioFixtures.create_repo_context(portfolio_path, "get_field_test", context_content)

      assert {:ok, "Test Name"} = Context.get_field("get_field_test", "name")
      assert {:ok, "Test purpose"} = Context.get_field("get_field_test", "purpose")
    end

    test "returns error for missing field", %{portfolio_path: portfolio_path} do
      context_content = """
      id: missing_field
      name: Test
      """

      PortfolioFixtures.create_repo_context(portfolio_path, "missing_field", context_content)

      assert {:error, :field_not_found} = Context.get_field("missing_field", "nonexistent")
    end
  end
end
