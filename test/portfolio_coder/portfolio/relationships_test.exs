defmodule PortfolioCoder.Portfolio.RelationshipsTest do
  use ExUnit.Case, async: false

  alias PortfolioCoder.Portfolio.Relationships
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

  describe "list/1" do
    test "returns empty list when no relationships" do
      assert {:ok, []} = Relationships.list()
    end

    test "returns all relationships after adding" do
      {:ok, _} = Relationships.add(:depends_on, "app1", "lib1")
      {:ok, _} = Relationships.add(:related_to, "lib1", "lib2")

      assert {:ok, rels} = Relationships.list()
      assert length(rels) == 2
    end
  end

  describe "add/4" do
    test "adds a new relationship" do
      assert {:ok, rel} = Relationships.add(:depends_on, "flowstone_ai", "flowstone")

      assert rel.type == :depends_on
      assert rel.from == "flowstone_ai"
      assert rel.to == "flowstone"
      assert rel.auto_detected == false
    end

    test "adds relationship with details" do
      details = %{reason: "Both NSAI components"}

      assert {:ok, rel} = Relationships.add(:related_to, "flowstone", "synapse", details)
      assert rel.details == details
    end

    test "allows duplicate relationships with different types" do
      {:ok, _} = Relationships.add(:depends_on, "a", "b")
      {:ok, _} = Relationships.add(:related_to, "a", "b")

      assert {:ok, rels} = Relationships.list()
      assert length(rels) == 2
    end
  end

  describe "remove/2" do
    test "removes relationship between repos" do
      {:ok, _} = Relationships.add(:depends_on, "a", "b")
      assert :ok = Relationships.remove("a", "b")
      assert {:ok, []} = Relationships.list()
    end

    test "returns error when relationship doesn't exist" do
      assert {:error, :not_found} = Relationships.remove("x", "y")
    end
  end

  describe "get_for_repo/1" do
    setup do
      {:ok, _} = Relationships.add(:depends_on, "app", "lib1")
      {:ok, _} = Relationships.add(:depends_on, "app", "lib2")
      {:ok, _} = Relationships.add(:depends_on, "other", "lib1")
      {:ok, _} = Relationships.add(:related_to, "lib1", "lib2")

      :ok
    end

    test "returns all relationships involving a repo" do
      assert {:ok, rels} = Relationships.get_for_repo("lib1")

      # lib1 is in: app->lib1, other->lib1, lib1<->lib2
      assert length(rels) == 3
    end

    test "returns empty list for repo with no relationships" do
      assert {:ok, []} = Relationships.get_for_repo("isolated")
    end
  end

  describe "get_dependencies/1" do
    setup do
      {:ok, _} = Relationships.add(:depends_on, "app", "lib1")
      {:ok, _} = Relationships.add(:depends_on, "app", "lib2")
      {:ok, _} = Relationships.add(:depends_on, "lib1", "core")

      :ok
    end

    test "returns repos that the given repo depends on" do
      assert {:ok, deps} = Relationships.get_dependencies("app")
      assert length(deps) == 2
      assert "lib1" in deps
      assert "lib2" in deps
    end

    test "returns empty list for repo with no dependencies" do
      assert {:ok, []} = Relationships.get_dependencies("core")
    end
  end

  describe "get_dependents/1" do
    setup do
      {:ok, _} = Relationships.add(:depends_on, "app1", "lib")
      {:ok, _} = Relationships.add(:depends_on, "app2", "lib")
      {:ok, _} = Relationships.add(:depends_on, "app1", "other")

      :ok
    end

    test "returns repos that depend on the given repo" do
      assert {:ok, dependents} = Relationships.get_dependents("lib")
      assert length(dependents) == 2
      assert "app1" in dependents
      assert "app2" in dependents
    end

    test "returns empty list for repo with no dependents" do
      assert {:ok, []} = Relationships.get_dependents("app1")
    end
  end

  describe "filter_by_type/1" do
    setup do
      {:ok, _} = Relationships.add(:depends_on, "a", "b")
      {:ok, _} = Relationships.add(:depends_on, "c", "d")
      {:ok, _} = Relationships.add(:port_of, "port1", "external:github.com/orig/repo")
      {:ok, _} = Relationships.add(:related_to, "x", "y")

      :ok
    end

    test "filters by relationship type" do
      assert {:ok, deps} = Relationships.filter_by_type(:depends_on)
      assert length(deps) == 2

      assert {:ok, ports} = Relationships.filter_by_type(:port_of)
      assert length(ports) == 1
    end
  end
end
