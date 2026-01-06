defmodule PortfolioCoder.Indexer.InMemorySearchTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Indexer.InMemorySearch

  setup do
    {:ok, index} = InMemorySearch.new()
    %{index: index}
  end

  describe "add/2 and search/3" do
    test "adds documents and finds them by keyword", %{index: index} do
      :ok =
        InMemorySearch.add(index, %{
          id: "doc1",
          content: "defmodule MyApp.User do end",
          metadata: %{language: :elixir}
        })

      {:ok, results} = InMemorySearch.search(index, "MyApp")
      assert length(results) == 1
      assert hd(results).id == "doc1"
    end

    test "returns multiple results ranked by score", %{index: index} do
      :ok =
        InMemorySearch.add(index, %{
          id: "doc1",
          content: "user authentication login",
          metadata: %{}
        })

      :ok =
        InMemorySearch.add(index, %{
          id: "doc2",
          content: "user profile settings",
          metadata: %{}
        })

      :ok =
        InMemorySearch.add(index, %{
          id: "doc3",
          content: "database connection pool",
          metadata: %{}
        })

      {:ok, results} = InMemorySearch.search(index, "user")
      assert length(results) == 2

      ids = Enum.map(results, & &1.id)
      assert "doc1" in ids
      assert "doc2" in ids
    end

    test "respects limit option", %{index: index} do
      for i <- 1..10 do
        :ok =
          InMemorySearch.add(index, %{
            id: "doc#{i}",
            content: "function definition #{i}",
            metadata: %{}
          })
      end

      {:ok, results} = InMemorySearch.search(index, "function", limit: 3)
      assert length(results) == 3
    end

    test "filters by minimum score", %{index: index} do
      :ok =
        InMemorySearch.add(index, %{
          id: "high",
          content: "user user user",
          metadata: %{}
        })

      :ok =
        InMemorySearch.add(index, %{
          id: "low",
          content: "some other content with user",
          metadata: %{}
        })

      {:ok, results} = InMemorySearch.search(index, "user", min_score: 0.5)
      assert length(results) <= 2
      # All returned results should have score >= 0.5
      assert Enum.all?(results, &(&1.score >= 0.5))
    end
  end

  describe "filter options" do
    test "filters by language", %{index: index} do
      :ok =
        InMemorySearch.add(index, %{
          id: "elixir1",
          content: "def hello",
          metadata: %{language: :elixir}
        })

      :ok =
        InMemorySearch.add(index, %{
          id: "python1",
          content: "def hello",
          metadata: %{language: :python}
        })

      {:ok, results} = InMemorySearch.search(index, "hello", language: :elixir)
      assert length(results) == 1
      assert hd(results).id == "elixir1"
    end

    test "filters by type", %{index: index} do
      :ok =
        InMemorySearch.add(index, %{
          id: "func1",
          content: "function code",
          metadata: %{type: :function}
        })

      :ok =
        InMemorySearch.add(index, %{
          id: "class1",
          content: "class code",
          metadata: %{type: :class}
        })

      {:ok, results} = InMemorySearch.search(index, "code", type: :function)
      assert length(results) == 1
      assert hd(results).id == "func1"
    end

    test "filters by path pattern", %{index: index} do
      :ok =
        InMemorySearch.add(index, %{
          id: "lib1",
          content: "module code",
          metadata: %{path: "lib/app/module.ex"}
        })

      :ok =
        InMemorySearch.add(index, %{
          id: "test1",
          content: "test code",
          metadata: %{path: "test/app/module_test.exs"}
        })

      {:ok, results} = InMemorySearch.search(index, "code", path_pattern: "lib/")
      assert length(results) == 1
      assert hd(results).id == "lib1"
    end
  end

  describe "add_all/2" do
    test "adds multiple documents at once", %{index: index} do
      docs = [
        %{id: "doc1", content: "first document", metadata: %{}},
        %{id: "doc2", content: "second document", metadata: %{}},
        %{id: "doc3", content: "third document", metadata: %{}}
      ]

      :ok = InMemorySearch.add_all(index, docs)

      {:ok, results} = InMemorySearch.search(index, "document")
      assert length(results) == 3
    end
  end

  describe "stats/1" do
    test "returns correct statistics", %{index: index} do
      :ok =
        InMemorySearch.add(index, %{
          id: "doc1",
          content: "hello world",
          metadata: %{}
        })

      :ok =
        InMemorySearch.add(index, %{
          id: "doc2",
          content: "hello there",
          metadata: %{}
        })

      stats = InMemorySearch.stats(index)
      assert stats.document_count == 2
      assert stats.term_count > 0
    end
  end

  describe "clear/1" do
    test "removes all documents", %{index: index} do
      :ok =
        InMemorySearch.add(index, %{
          id: "doc1",
          content: "content",
          metadata: %{}
        })

      :ok = InMemorySearch.clear(index)

      stats = InMemorySearch.stats(index)
      assert stats.document_count == 0

      {:ok, results} = InMemorySearch.search(index, "content")
      assert results == []
    end
  end

  describe "edge cases" do
    test "handles empty query", %{index: index} do
      :ok =
        InMemorySearch.add(index, %{
          id: "doc1",
          content: "content",
          metadata: %{}
        })

      {:ok, results} = InMemorySearch.search(index, "")
      assert results == []
    end

    test "handles special characters in query", %{index: index} do
      :ok =
        InMemorySearch.add(index, %{
          id: "doc1",
          content: "def hello(name), do: name",
          metadata: %{}
        })

      # Special chars should be treated as word separators
      {:ok, results} = InMemorySearch.search(index, "hello()")
      assert length(results) == 1
    end

    test "handles missing content field", %{index: index} do
      :ok =
        InMemorySearch.add(index, %{
          id: "doc1",
          content: nil,
          metadata: %{}
        })

      {:ok, results} = InMemorySearch.search(index, "anything")
      assert results == []
    end
  end
end
