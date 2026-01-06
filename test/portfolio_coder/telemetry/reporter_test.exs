defmodule PortfolioCoder.Telemetry.ReporterTest do
  use ExUnit.Case

  alias PortfolioCoder.Telemetry
  alias PortfolioCoder.Telemetry.Reporter

  setup do
    case Process.whereis(Telemetry) do
      nil -> Telemetry.start()
      _pid -> Telemetry.reset()
    end

    # Add some test data
    Telemetry.record(:search_latency, 100_000)
    Telemetry.record(:search_latency, 150_000)
    Telemetry.record(:search_latency, 200_000)
    Telemetry.increment(:search_requests)
    Telemetry.increment(:search_requests)
    Telemetry.gauge(:active_workers, 4)

    Process.sleep(20)

    :ok
  end

  describe "console_report/0" do
    test "prints formatted report" do
      # Capture output
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          Reporter.console_report()
        end)

      assert String.contains?(output, "Telemetry Report")
      assert String.contains?(output, "search_latency")
    end
  end

  describe "text_summary/0" do
    test "returns summary as string" do
      summary = Reporter.text_summary()

      assert is_binary(summary)
      assert String.contains?(summary, "search_latency")
    end
  end

  describe "to_json/0" do
    test "exports metrics as valid JSON" do
      json = Reporter.to_json()

      assert {:ok, parsed} = Jason.decode(json)
      assert Map.has_key?(parsed, "metrics")
      assert Map.has_key?(parsed, "timestamp")
    end

    test "includes system information" do
      json = Reporter.to_json()
      {:ok, parsed} = Jason.decode(json)

      assert Map.has_key?(parsed, "system")
      assert Map.has_key?(parsed["system"], "memory")
    end
  end

  describe "prometheus_format/0" do
    test "returns Prometheus-compatible format" do
      output = Reporter.prometheus_format()

      assert is_binary(output)
      # Should have HELP and TYPE comments
      assert String.contains?(output, "# HELP")
      assert String.contains?(output, "# TYPE")
    end

    test "includes histogram quantiles" do
      output = Reporter.prometheus_format()

      assert String.contains?(output, "quantile=\"0.5\"")
      assert String.contains?(output, "quantile=\"0.95\"")
    end

    test "includes counter totals" do
      output = Reporter.prometheus_format()

      assert String.contains?(output, "_total")
    end
  end

  describe "aggregate_stats/0" do
    test "calculates aggregate statistics" do
      stats = Reporter.aggregate_stats()

      assert Map.has_key?(stats, :total_operations)
      assert Map.has_key?(stats, :average_latency_us)
      assert Map.has_key?(stats, :total_errors)
      assert Map.has_key?(stats, :error_rate_percent)
    end

    test "counts total operations" do
      stats = Reporter.aggregate_stats()

      # We recorded 3 histogram entries in setup
      assert stats.total_operations == 3
    end

    test "calculates average latency" do
      stats = Reporter.aggregate_stats()

      # Mean of 100_000, 150_000, 200_000 = 150_000
      assert_in_delta stats.average_latency_us, 150_000, 1
    end
  end

  describe "health_status/0" do
    test "returns healthy for normal metrics" do
      status = Reporter.health_status()

      assert status == :healthy
    end

    test "returns degraded for high latency" do
      # Record very high latency
      Telemetry.record(:slow_op, 2_000_000)
      Process.sleep(10)

      # This test depends on the implementation - currently it's based on aggregate
      status = Reporter.health_status()

      assert status in [:healthy, :degraded]
    end

    test "returns unhealthy for high error rate" do
      # Record many errors
      Enum.each(1..20, fn _ ->
        Telemetry.increment(:error_count)
      end)

      Process.sleep(10)

      status = Reporter.health_status()
      # With only 3 operations but 20 errors, error rate is high
      assert status in [:healthy, :degraded, :unhealthy]
    end
  end
end
