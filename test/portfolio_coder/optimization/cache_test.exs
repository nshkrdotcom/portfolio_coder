defmodule PortfolioCoder.Optimization.CacheTest do
  use ExUnit.Case

  alias PortfolioCoder.Optimization.Cache

  setup do
    case Process.whereis(Cache) do
      nil -> Cache.start()
      _pid -> Cache.clear_all()
    end

    :ok
  end

  describe "start/1" do
    test "starts the cache server" do
      assert Process.whereis(Cache) != nil
    end

    test "returns existing process if already started" do
      {:ok, pid1} = Cache.start()
      {:ok, pid2} = Cache.start()
      assert pid1 == pid2
    end
  end

  describe "put/4 and get/2" do
    test "stores and retrieves values" do
      Cache.put(:test, "key1", "value1")
      Process.sleep(10)

      assert Cache.get(:test, "key1") == "value1"
    end

    test "returns nil for missing keys" do
      assert Cache.get(:test, "nonexistent") == nil
    end

    test "separates values by cache namespace" do
      Cache.put(:cache1, "key", "value1")
      Cache.put(:cache2, "key", "value2")
      Process.sleep(10)

      assert Cache.get(:cache1, "key") == "value1"
      assert Cache.get(:cache2, "key") == "value2"
    end

    test "expires values after TTL" do
      Cache.put(:test, "key", "value", ttl: 50)
      Process.sleep(10)
      assert Cache.get(:test, "key") == "value"

      Process.sleep(100)
      assert Cache.get(:test, "key") == nil
    end
  end

  describe "fetch/4" do
    test "returns cached value if present" do
      Cache.put(:test, "key", "cached")
      Process.sleep(10)

      result =
        Cache.fetch(:test, "key", fn ->
          "computed"
        end)

      assert result == "cached"
    end

    test "computes and caches value if not present" do
      result =
        Cache.fetch(:test, "missing", fn ->
          "computed"
        end)

      assert result == "computed"

      Process.sleep(10)
      assert Cache.get(:test, "missing") == "computed"
    end

    test "only calls compute function once" do
      counter = :counters.new(1, [])

      Cache.fetch(:test, "key", fn ->
        :counters.add(counter, 1, 1)
        "value"
      end)

      Process.sleep(10)

      Cache.fetch(:test, "key", fn ->
        :counters.add(counter, 1, 1)
        "value"
      end)

      assert :counters.get(counter, 1) == 1
    end
  end

  describe "delete/2" do
    test "removes value from cache" do
      Cache.put(:test, "key", "value")
      Process.sleep(10)
      assert Cache.get(:test, "key") == "value"

      Cache.delete(:test, "key")
      Process.sleep(10)
      assert Cache.get(:test, "key") == nil
    end
  end

  describe "clear/1" do
    test "clears specific cache namespace" do
      Cache.put(:cache1, "key", "value1")
      Cache.put(:cache2, "key", "value2")
      Process.sleep(10)

      Cache.clear(:cache1)
      Process.sleep(10)

      assert Cache.get(:cache1, "key") == nil
      assert Cache.get(:cache2, "key") == "value2"
    end
  end

  describe "clear_all/0" do
    test "clears all caches" do
      Cache.put(:cache1, "key", "value1")
      Cache.put(:cache2, "key", "value2")
      Process.sleep(10)

      Cache.clear_all()
      Process.sleep(10)

      assert Cache.get(:cache1, "key") == nil
      assert Cache.get(:cache2, "key") == nil
    end
  end

  describe "stats/0" do
    test "returns cache statistics" do
      Cache.put(:test, "key", "value")
      Process.sleep(10)
      Cache.get(:test, "key")
      Cache.get(:test, "missing")

      stats = Cache.stats()

      assert Map.has_key?(stats, :caches)
      assert Map.has_key?(stats, :hits)
      assert Map.has_key?(stats, :misses)
      assert Map.has_key?(stats, :hit_rate)
    end

    test "tracks hits and misses" do
      Cache.put(:test, "key", "value")
      Process.sleep(10)

      Cache.get(:test, "key")
      Cache.get(:test, "key")
      Cache.get(:test, "missing")

      stats = Cache.stats()

      assert stats.hits == 2
      assert stats.misses == 1
    end
  end

  describe "convenience functions" do
    test "put_embedding and get_embedding" do
      embedding = [0.1, 0.2, 0.3]
      Cache.put_embedding("hash123", embedding)
      Process.sleep(10)

      assert Cache.get_embedding("hash123") == embedding
    end

    test "put_search and get_search" do
      results = ["doc1", "doc2", "doc3"]
      Cache.put_search("query_hash", results)
      Process.sleep(10)

      assert Cache.get_search("query_hash") == results
    end

    test "put_ast and get_ast" do
      ast = {:defmodule, [], []}
      Cache.put_ast("file_hash", ast)
      Process.sleep(10)

      assert Cache.get_ast("file_hash") == ast
    end
  end
end
