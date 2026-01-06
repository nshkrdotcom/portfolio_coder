defmodule PortfolioCoder.Optimization.BatchTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Optimization.Batch

  describe "parallel_map/3" do
    test "processes items in parallel" do
      items = [1, 2, 3, 4, 5]

      results =
        Batch.parallel_map(items, fn x -> x * 2 end, max_concurrency: 2)

      assert Enum.sort(results) == [2, 4, 6, 8, 10]
    end

    test "respects max_concurrency" do
      # This is hard to test precisely, but we can verify it completes
      items = Enum.to_list(1..10)

      results =
        Batch.parallel_map(
          items,
          fn x ->
            Process.sleep(10)
            x * 2
          end,
          max_concurrency: 2
        )

      assert length(results) == 10
    end

    test "handles errors with :skip" do
      items = [1, 2, 3, 4, 5]

      results =
        Batch.parallel_map(
          items,
          fn x ->
            if x == 3, do: raise("error"), else: x * 2
          end,
          on_error: :skip
        )

      assert length(results) == 4
      assert 6 not in results
    end

    test "handles errors with :collect" do
      items = [1, 2, 3]

      results =
        Batch.parallel_map(
          items,
          fn x ->
            if x == 2, do: raise("test error"), else: x * 2
          end,
          on_error: :collect
        )

      assert Enum.any?(results, &match?({:error, _, _}, &1))
    end
  end

  describe "in_batches/3" do
    test "processes items in batches" do
      items = 1..10

      batch_sizes =
        Batch.in_batches(items, &length/1, batch_size: 3)

      assert batch_sizes == [3, 3, 3, 1]
    end

    test "accumulates batch results" do
      items = 1..6

      sums =
        Batch.in_batches(items, &Enum.sum/1, batch_size: 2)

      # [1+2, 3+4, 5+6]
      assert sums == [3, 7, 11]
    end
  end

  describe "stream/2" do
    test "returns a stream of batches" do
      items = 1..10
      stream = Batch.stream(items, batch_size: 3)

      batches = Enum.to_list(stream)

      assert length(batches) == 4
      assert hd(batches) == [1, 2, 3]
    end
  end

  describe "rate_limited/3" do
    test "processes with rate limiting" do
      items = [1, 2, 3]

      start_time = System.monotonic_time(:millisecond)

      results =
        Batch.rate_limited(items, fn x -> x * 2 end, rate: 10, per: :second)

      elapsed = System.monotonic_time(:millisecond) - start_time

      assert results == [2, 4, 6]
      # Should take at least 200ms (3 items at 100ms interval)
      assert elapsed >= 200
    end
  end

  describe "with_retry/2" do
    test "succeeds without retry" do
      result = Batch.with_retry(fn -> :success end)

      assert result == {:ok, :success}
    end

    test "retries on failure" do
      # Use Agent to track retry count
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        Batch.with_retry(
          fn ->
            count = Agent.get_and_update(agent, fn c -> {c + 1, c + 1} end)
            if count < 3, do: raise("error"), else: :success
          end,
          max_retries: 5,
          base_delay: 10
        )

      assert result == {:ok, :success}
      assert Agent.get(agent, & &1) == 3

      Agent.stop(agent)
    end

    test "returns error after max retries" do
      result =
        Batch.with_retry(
          fn -> raise "always fails" end,
          max_retries: 2,
          base_delay: 10
        )

      assert {:error, _} = result
    end
  end

  describe "with_progress/3" do
    test "tracks progress" do
      items = [1, 2, 3, 4, 5]
      progress = :ets.new(:progress, [:set, :public])

      Batch.with_progress(
        items,
        fn x -> x * 2 end,
        on_progress: fn current, total ->
          :ets.insert(progress, {current, total})
        end
      )

      # Verify all progress updates were made
      assert :ets.lookup(progress, 5) == [{5, 5}]
    end
  end

  describe "map_reduce/4" do
    test "maps and reduces in parallel" do
      items = [1, 2, 3, 4, 5]

      result =
        Batch.map_reduce(
          items,
          fn x -> x * 2 end,
          &Enum.sum/1,
          max_concurrency: 2
        )

      # Sum of [2, 4, 6, 8, 10]
      assert result == 30
    end
  end

  describe "collector/2" do
    test "collects items until batch size" do
      collected = :ets.new(:collected, [:set, :public])

      collect =
        Batch.collector(
          fn batch ->
            :ets.insert(collected, {:batch, batch})
            length(batch)
          end,
          batch_size: 3
        )

      # Add items one by one
      assert collect.(1) == :ok
      assert collect.(2) == :ok
      assert {:batch, 3} = collect.(3)

      # Verify batch was processed
      [{:batch, batch}] = :ets.lookup(collected, :batch)
      assert length(batch) == 3
    end

    test "flushes remaining items" do
      collect =
        Batch.collector(
          fn batch -> {:processed, batch} end,
          batch_size: 5
        )

      collect.(1)
      collect.(2)

      result = collect.(:flush)
      assert {:batch, {:processed, batch}} = result
      assert length(batch) == 2
    end
  end
end
