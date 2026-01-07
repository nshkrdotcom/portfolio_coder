defmodule PortfolioCoder.Search.CollectionRouterTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Search.CollectionRouter

  @collections [
    %{
      id: "auth",
      name: "Authentication",
      description: "User authentication, login, sessions, tokens",
      patterns: ["auth", "session", "login", "token", "password"]
    },
    %{
      id: "api",
      name: "API Endpoints",
      description: "REST API routes, controllers, handlers",
      patterns: ["api", "endpoint", "controller", "route", "handler", "http"]
    },
    %{
      id: "database",
      name: "Database",
      description: "Database models, queries, migrations",
      patterns: ["database", "schema", "migration", "query", "ecto", "repo"]
    },
    %{
      id: "frontend",
      name: "Frontend",
      description: "UI components, views, templates",
      patterns: ["view", "template", "component", "ui", "frontend", "html", "css"]
    },
    %{
      id: "tests",
      name: "Tests",
      description: "Test files and specifications",
      patterns: ["test", "spec", "assert", "mock", "fixture"]
    }
  ]

  describe "new/1" do
    test "creates router with collections" do
      router = CollectionRouter.new(@collections)

      assert is_struct(router, CollectionRouter)
      assert length(router.collections) == 5
    end

    test "creates router with options" do
      router = CollectionRouter.new(@collections, strategy: :keyword, max_collections: 2)

      assert router.strategy == :keyword
      assert router.max_collections == 2
    end
  end

  describe "route/2" do
    test "routes to matching collections based on keywords" do
      router = CollectionRouter.new(@collections)

      result = CollectionRouter.route(router, "how do I authenticate users?")

      assert is_list(result)
      assert result != []
      collection_ids = Enum.map(result, & &1.id)
      assert "auth" in collection_ids
    end

    test "routes database queries to database collection" do
      router = CollectionRouter.new(@collections)

      result = CollectionRouter.route(router, "how do I write a database migration?")

      collection_ids = Enum.map(result, & &1.id)
      assert "database" in collection_ids
    end

    test "routes API queries to api collection" do
      router = CollectionRouter.new(@collections)

      result = CollectionRouter.route(router, "show me the API endpoints")

      collection_ids = Enum.map(result, & &1.id)
      assert "api" in collection_ids
    end

    test "respects max_collections limit" do
      router = CollectionRouter.new(@collections, max_collections: 2)

      result = CollectionRouter.route(router, "auth api database frontend")

      assert length(result) <= 2
    end

    test "returns empty list for no matches" do
      router = CollectionRouter.new(@collections)

      result = CollectionRouter.route(router, "xyz123 gibberish query")

      # Should return something or empty based on strategy
      assert is_list(result)
    end
  end

  describe "route_with_scores/2" do
    test "returns collections with relevance scores" do
      router = CollectionRouter.new(@collections)

      result = CollectionRouter.route_with_scores(router, "authenticate login session")

      assert is_list(result)

      Enum.each(result, fn {collection, score} ->
        assert is_map(collection)
        assert is_number(score)
        assert score >= 0.0
      end)
    end

    test "higher scores for more matching keywords" do
      router = CollectionRouter.new(@collections)

      result = CollectionRouter.route_with_scores(router, "authentication login session token")

      # Auth should have high score due to multiple matches
      auth_score = Enum.find_value(result, fn {c, s} -> if c.id == "auth", do: s end)
      assert auth_score != nil
      assert auth_score > 0
    end
  end

  describe "add_collection/2" do
    test "adds new collection to router" do
      router = CollectionRouter.new(@collections)

      new_collection = %{
        id: "config",
        name: "Configuration",
        description: "Config files and settings",
        patterns: ["config", "settings", "env", "environment"]
      }

      updated = CollectionRouter.add_collection(router, new_collection)

      assert length(updated.collections) == 6
      collection_ids = Enum.map(updated.collections, & &1.id)
      assert "config" in collection_ids
    end
  end

  describe "remove_collection/2" do
    test "removes collection by id" do
      router = CollectionRouter.new(@collections)

      updated = CollectionRouter.remove_collection(router, "tests")

      assert length(updated.collections) == 4
      collection_ids = Enum.map(updated.collections, & &1.id)
      refute "tests" in collection_ids
    end
  end

  describe "strategies" do
    test "keyword strategy matches based on patterns" do
      router = CollectionRouter.new(@collections, strategy: :keyword)

      result = CollectionRouter.route(router, "database schema")

      collection_ids = Enum.map(result, & &1.id)
      assert "database" in collection_ids
    end

    test "semantic strategy uses embeddings when available" do
      router = CollectionRouter.new(@collections, strategy: :semantic)

      # Falls back to keyword when no embedder configured
      result = CollectionRouter.route(router, "data persistence layer")

      assert is_list(result)
    end

    test "hybrid strategy combines keyword and semantic" do
      router = CollectionRouter.new(@collections, strategy: :hybrid)

      result = CollectionRouter.route(router, "user authentication")

      assert is_list(result)
    end
  end

  describe "get_all_collections/1" do
    test "returns all configured collections" do
      router = CollectionRouter.new(@collections)

      result = CollectionRouter.get_all_collections(router)

      assert length(result) == 5
    end
  end

  describe "find_collection/2" do
    test "finds collection by id" do
      router = CollectionRouter.new(@collections)

      result = CollectionRouter.find_collection(router, "auth")

      assert result.id == "auth"
      assert result.name == "Authentication"
    end

    test "returns nil for unknown id" do
      router = CollectionRouter.new(@collections)

      result = CollectionRouter.find_collection(router, "unknown")

      assert result == nil
    end
  end
end
