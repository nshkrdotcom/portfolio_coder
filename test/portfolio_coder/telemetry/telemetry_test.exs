defmodule PortfolioCoder.TelemetryTest do
  use ExUnit.Case

  alias PortfolioCoder.Telemetry

  setup do
    # Start fresh telemetry for each test
    case Process.whereis(Telemetry) do
      nil -> Telemetry.start()
      _pid -> Telemetry.reset()
    end

    :ok
  end

  describe "start/1" do
    test "starts the telemetry GenServer" do
      # Already started in setup
      assert Process.whereis(Telemetry) != nil
    end

    test "returns existing process if already started" do
      {:ok, pid1} = Telemetry.start()
      {:ok, pid2} = Telemetry.start()

      assert pid1 == pid2
    end
  end

  describe "record/3" do
    test "records a metric value" do
      :ok = Telemetry.record(:test_metric, 100, %{tag: "value"})

      # Give time for async cast
      Process.sleep(10)

      result = Telemetry.get_metric(:test_metric)
      assert length(result.histogram) == 1
    end

    test "accumulates multiple values" do
      Telemetry.record(:test_metric, 100)
      Telemetry.record(:test_metric, 200)
      Telemetry.record(:test_metric, 300)

      Process.sleep(10)

      result = Telemetry.get_metric(:test_metric)
      assert length(result.histogram) == 3
    end
  end

  describe "span/3" do
    test "executes function and records duration" do
      result =
        Telemetry.span(:test_operation, %{type: :test}, fn ->
          Process.sleep(10)
          :done
        end)

      assert result == :done

      Process.sleep(10)

      metric = Telemetry.get_metric(:test_operation)
      assert length(metric.histogram) == 1

      [entry] = metric.histogram
      assert entry.value >= 10_000
      assert entry.tags.type == :test
      assert entry.tags.status == :ok
    end

    test "records error status on exception" do
      assert_raise RuntimeError, fn ->
        Telemetry.span(:failing_operation, fn ->
          raise "test error"
        end)
      end

      Process.sleep(10)

      metric = Telemetry.get_metric(:failing_operation)
      [entry] = metric.histogram
      assert entry.tags.status == :error
    end
  end

  describe "increment/2" do
    test "increments a counter" do
      Telemetry.increment(:requests)
      Telemetry.increment(:requests)
      Telemetry.increment(:requests)

      Process.sleep(10)

      metric = Telemetry.get_metric(:requests)
      assert metric.counter == 3
    end

    test "supports tagged counters" do
      Telemetry.increment(:requests, %{endpoint: "/api/search"})
      Telemetry.increment(:requests, %{endpoint: "/api/search"})
      Telemetry.increment(:requests, %{endpoint: "/api/index"})

      Process.sleep(10)

      summary = Telemetry.summary()
      assert summary.counters.requests.total == 3
    end
  end

  describe "gauge/3" do
    test "sets a gauge value" do
      Telemetry.gauge(:active_connections, 42)

      Process.sleep(10)

      metric = Telemetry.get_metric(:active_connections)
      assert metric.gauge == 42
    end

    test "updates gauge value" do
      Telemetry.gauge(:queue_size, 10)
      Process.sleep(10)
      Telemetry.gauge(:queue_size, 20)
      Process.sleep(10)

      metric = Telemetry.get_metric(:queue_size)
      assert metric.gauge == 20
    end
  end

  describe "summary/0" do
    test "returns summary of all metrics" do
      Telemetry.record(:latency, 100)
      Telemetry.record(:latency, 200)
      Telemetry.increment(:errors)
      Telemetry.gauge(:memory, 1024)

      Process.sleep(10)

      summary = Telemetry.summary()

      assert Map.has_key?(summary, :histograms)
      assert Map.has_key?(summary, :counters)
      assert Map.has_key?(summary, :gauges)
    end

    test "calculates histogram statistics" do
      Telemetry.record(:latency, 100)
      Telemetry.record(:latency, 200)
      Telemetry.record(:latency, 300)

      Process.sleep(10)

      summary = Telemetry.summary()
      stats = summary.histograms.latency

      assert stats.count == 3
      assert stats.min == 100
      assert stats.max == 300
      assert_in_delta stats.mean, 200.0, 0.1
    end
  end

  describe "reset/0" do
    test "clears all metrics" do
      Telemetry.record(:metric1, 100)
      Telemetry.increment(:counter1)
      Telemetry.gauge(:gauge1, 42)

      Process.sleep(10)

      Telemetry.reset()

      summary = Telemetry.summary()
      assert summary.histograms == %{}
      assert summary.counters == %{}
      assert summary.gauges == %{}
    end
  end

  describe "export/0" do
    test "exports all metrics with system info" do
      Telemetry.record(:test, 100)
      Process.sleep(10)

      export = Telemetry.export()

      assert Map.has_key?(export, :timestamp)
      assert Map.has_key?(export, :metrics)
      assert Map.has_key?(export, :system)
      assert Map.has_key?(export.system, :memory)
      assert Map.has_key?(export.system, :process_count)
    end
  end

  describe "get_all_metrics/0" do
    test "returns all raw metrics" do
      Telemetry.record(:metric1, 100)
      Telemetry.record(:metric2, 200)

      Process.sleep(10)

      metrics = Telemetry.get_all_metrics()

      assert length(metrics) == 2
      assert Enum.all?(metrics, &Map.has_key?(&1, :name))
      assert Enum.all?(metrics, &Map.has_key?(&1, :value))
      assert Enum.all?(metrics, &Map.has_key?(&1, :timestamp))
    end
  end
end
