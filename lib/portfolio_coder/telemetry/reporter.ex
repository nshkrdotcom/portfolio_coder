defmodule PortfolioCoder.Telemetry.Reporter do
  @moduledoc """
  Telemetry reporter for generating reports and dashboards.

  Outputs metrics in various formats:
  - Console/terminal
  - JSON
  - Prometheus-compatible
  - Simple text reports

  ## Usage

      # Console report
      Reporter.console_report()

      # JSON export
      json = Reporter.to_json()

      # Prometheus format
      metrics = Reporter.prometheus_format()
  """

  alias PortfolioCoder.Telemetry

  @doc """
  Print a formatted report to console.
  """
  @spec console_report() :: :ok
  def console_report do
    summary = Telemetry.summary()

    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("📊 Portfolio Coder Telemetry Report")
    IO.puts(String.duplicate("=", 60) <> "\n")

    print_histograms(summary.histograms)
    print_counters(summary.counters)
    print_gauges(summary.gauges)

    IO.puts("\n" <> String.duplicate("=", 60))
    :ok
  end

  @doc """
  Generate a text summary string.
  """
  @spec text_summary() :: String.t()
  def text_summary do
    summary = Telemetry.summary()

    histogram_lines =
      summary.histograms
      |> Enum.map(fn {name, stats} ->
        "#{name}: count=#{stats.count}, mean=#{format_number(stats.mean)}µs, p95=#{format_number(stats.p95)}µs"
      end)

    counter_lines =
      summary.counters
      |> Enum.map(fn {name, data} ->
        "#{name}: #{data.total}"
      end)

    gauge_lines =
      summary.gauges
      |> Enum.flat_map(fn {name, values} ->
        Enum.map(values, fn v ->
          "#{name}[#{format_tags(v.tags)}]: #{v.value}"
        end)
      end)

    (histogram_lines ++ counter_lines ++ gauge_lines)
    |> Enum.join("\n")
  end

  @doc """
  Export metrics as JSON string.
  """
  @spec to_json() :: String.t()
  def to_json do
    Telemetry.export()
    |> Jason.encode!(pretty: true)
  end

  @doc """
  Generate Prometheus-compatible metrics format.
  """
  @spec prometheus_format() :: String.t()
  def prometheus_format do
    summary = Telemetry.summary()

    histogram_metrics =
      summary.histograms
      |> Enum.flat_map(fn {name, stats} ->
        prefix = "portfolio_coder_#{name}"

        [
          "# HELP #{prefix} #{name} metric",
          "# TYPE #{prefix} histogram",
          "#{prefix}_count #{stats.count}",
          "#{prefix}_sum #{stats.mean * stats.count}",
          "#{prefix}{quantile=\"0.5\"} #{stats.p50}",
          "#{prefix}{quantile=\"0.95\"} #{stats.p95}",
          "#{prefix}{quantile=\"0.99\"} #{stats.p99}"
        ]
      end)

    counter_metrics =
      summary.counters
      |> Enum.flat_map(fn {name, data} ->
        prefix = "portfolio_coder_#{name}"

        [
          "# HELP #{prefix}_total Total #{name}",
          "# TYPE #{prefix}_total counter",
          "#{prefix}_total #{data.total}"
        ]
      end)

    gauge_metrics =
      summary.gauges
      |> Enum.flat_map(fn {name, values} ->
        prefix = "portfolio_coder_#{name}"

        header = [
          "# HELP #{prefix} Current #{name}",
          "# TYPE #{prefix} gauge"
        ]

        value_lines =
          Enum.map(values, fn v ->
            tags_str = prometheus_tags(v.tags)
            "#{prefix}#{tags_str} #{v.value}"
          end)

        header ++ value_lines
      end)

    (histogram_metrics ++ counter_metrics ++ gauge_metrics)
    |> Enum.join("\n")
  end

  @doc """
  Calculate aggregate statistics from metrics.
  """
  @spec aggregate_stats() :: map()
  def aggregate_stats do
    summary = Telemetry.summary()

    total_operations =
      summary.histograms
      |> Enum.map(fn {_, stats} -> stats.count end)
      |> Enum.sum()

    avg_latency =
      if map_size(summary.histograms) > 0 do
        summary.histograms
        |> Enum.map(fn {_, stats} -> stats.mean * stats.count end)
        |> Enum.sum()
        |> Kernel./(max(total_operations, 1))
      else
        0.0
      end

    total_errors =
      summary.counters
      |> Enum.filter(fn {name, _} -> String.contains?(to_string(name), "error") end)
      |> Enum.map(fn {_, data} -> data.total end)
      |> Enum.sum()

    error_rate =
      if total_operations > 0 do
        total_errors / total_operations * 100
      else
        0.0
      end

    %{
      total_operations: total_operations,
      average_latency_us: avg_latency,
      total_errors: total_errors,
      error_rate_percent: error_rate,
      metrics_count:
        map_size(summary.histograms) + map_size(summary.counters) + map_size(summary.gauges)
    }
  end

  @doc """
  Generate a health status based on metrics.
  """
  @spec health_status() :: :healthy | :degraded | :unhealthy
  def health_status do
    stats = aggregate_stats()

    cond do
      stats.error_rate_percent > 10 -> :unhealthy
      stats.error_rate_percent > 5 -> :degraded
      stats.average_latency_us > 1_000_000 -> :degraded
      true -> :healthy
    end
  end

  # Private helpers

  defp print_histograms(histograms) when map_size(histograms) == 0 do
    IO.puts("No timing metrics recorded\n")
  end

  defp print_histograms(histograms) do
    IO.puts("⏱  Timing Metrics")
    IO.puts(String.duplicate("-", 40))

    Enum.each(histograms, fn {name, stats} ->
      IO.puts("\n  #{name}:")
      IO.puts("    Count:  #{stats.count}")
      IO.puts("    Min:    #{format_number(stats.min)} µs")
      IO.puts("    Max:    #{format_number(stats.max)} µs")
      IO.puts("    Mean:   #{format_number(stats.mean)} µs")
      IO.puts("    P50:    #{format_number(stats.p50)} µs")
      IO.puts("    P95:    #{format_number(stats.p95)} µs")
      IO.puts("    P99:    #{format_number(stats.p99)} µs")
    end)

    IO.puts("")
  end

  defp print_counters(counters) when map_size(counters) == 0 do
    IO.puts("No counter metrics recorded\n")
  end

  defp print_counters(counters) do
    IO.puts("📈 Counters")
    IO.puts(String.duplicate("-", 40))

    Enum.each(counters, fn {name, data} ->
      IO.puts("  #{name}: #{data.total}")

      Enum.each(data.by_tags, fn entry ->
        if map_size(entry.tags) > 0 do
          IO.puts("    #{format_tags(entry.tags)}: #{entry.count}")
        end
      end)
    end)

    IO.puts("")
  end

  defp print_gauges(gauges) when map_size(gauges) == 0 do
    IO.puts("No gauge metrics recorded\n")
  end

  defp print_gauges(gauges) do
    IO.puts("📉 Gauges")
    IO.puts(String.duplicate("-", 40))

    Enum.each(gauges, fn {name, values} ->
      IO.puts("  #{name}:")

      Enum.each(values, fn v ->
        tags_str = if map_size(v.tags) > 0, do: " [#{format_tags(v.tags)}]", else: ""
        IO.puts("    #{v.value}#{tags_str}")
      end)
    end)

    IO.puts("")
  end

  defp format_number(num) when is_float(num) do
    :erlang.float_to_binary(num, decimals: 2)
  end

  defp format_number(num), do: to_string(num)

  defp format_tags(tags) when map_size(tags) == 0, do: ""

  defp format_tags(tags) do
    tags
    |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
    |> Enum.join(", ")
  end

  defp prometheus_tags(tags) when map_size(tags) == 0, do: ""

  defp prometheus_tags(tags) do
    labels =
      tags
      |> Enum.map(fn {k, v} -> "#{k}=\"#{v}\"" end)
      |> Enum.join(",")

    "{#{labels}}"
  end
end
