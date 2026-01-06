# examples/14_telemetry_demo.exs
#
# Demonstrates: Telemetry and Metrics Collection
# Modules Used: :telemetry, various portfolio_coder modules
# Prerequisites: None
#
# Usage: mix run examples/14_telemetry_demo.exs
#
# This demo shows how to collect and display telemetry from the system:
# 1. Attach telemetry handlers
# 2. Run operations that emit telemetry
# 3. Display collected metrics

alias PortfolioCoder.Indexer.Parser
alias PortfolioCoder.Indexer.CodeChunker
alias PortfolioCoder.Indexer.InMemorySearch

defmodule TelemetryDemo do
  @moduledoc """
  Demonstrates telemetry collection and metrics display.
  """

  def run do
    print_header("Telemetry Demo")

    # Initialize metrics storage
    metrics_agent = start_metrics_agent()

    # Attach telemetry handlers
    IO.puts("Step 1: Attaching telemetry handlers...")
    attach_handlers(metrics_agent)
    IO.puts("  Handlers attached\n")

    # Run operations
    IO.puts("Step 2: Running operations...")
    run_operations()
    IO.puts("  Operations complete\n")

    # Display metrics
    print_section("Collected Metrics")
    display_metrics(metrics_agent)

    # Show live metrics
    print_section("Live Metrics Demo")
    run_live_demo(metrics_agent)

    IO.puts("")
    print_header("Demo Complete")

    # Cleanup
    Agent.stop(metrics_agent)
  end

  defp start_metrics_agent do
    {:ok, agent} =
      Agent.start_link(fn ->
        %{
          events: [],
          counters: %{},
          timings: %{}
        }
      end)

    agent
  end

  defp attach_handlers(agent) do
    handler = fn event_name, measurements, metadata, _config ->
      handle_event(event_name, measurements, metadata, agent)
    end

    # Parser events
    :telemetry.attach(
      "demo-parser",
      [:portfolio_coder, :parser, :parse],
      handler,
      nil
    )

    # Search events
    :telemetry.attach(
      "demo-search",
      [:portfolio_index, :vector_store, :search],
      handler,
      nil
    )

    # LLM events
    :telemetry.attach(
      "demo-llm",
      [:portfolio_index, :llm, :complete],
      handler,
      nil
    )

    # Query processing events
    :telemetry.attach(
      "demo-query-rewriter",
      [:portfolio_index, :query_rewriter, :llm, :rewrite],
      handler,
      nil
    )
  end

  defp handle_event(event_name, measurements, metadata, agent) do
    event = %{
      name: event_name,
      measurements: measurements,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }

    Agent.update(agent, fn state ->
      events = [event | state.events] |> Enum.take(100)

      counters =
        Map.update(state.counters, event_name, 1, &(&1 + 1))

      timings =
        if duration = measurements[:duration_ms] do
          Map.update(state.timings, event_name, [duration], fn list ->
            [duration | list] |> Enum.take(100)
          end)
        else
          state.timings
        end

      %{state | events: events, counters: counters, timings: timings}
    end)
  end

  defp run_operations do
    path = Path.expand("lib/portfolio_coder")

    # Parse some files
    IO.puts("  Parsing files...")

    files =
      path
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.take(10)

    for file <- files do
      emit_parse_event(file)
    end

    # Build search index
    IO.puts("  Building search index...")
    {:ok, index} = InMemorySearch.new()

    for file <- files do
      case Parser.parse(file) do
        {:ok, parsed} ->
          case CodeChunker.chunk_file(file, strategy: :hybrid) do
            {:ok, chunks} ->
              docs =
                Enum.with_index(chunks)
                |> Enum.map(fn {chunk, idx} ->
                  %{
                    id: "#{Path.basename(file)}:#{idx}",
                    content: chunk.content,
                    metadata: %{path: file, language: parsed.language}
                  }
                end)

              InMemorySearch.add_all(index, docs)

            _ ->
              :ok
          end

        _ ->
          :ok
      end
    end

    # Run some searches
    IO.puts("  Running searches...")
    queries = ["parse", "function", "module", "search", "graph"]

    for query <- queries do
      emit_search_event(query)
      InMemorySearch.search(index, query, limit: 5)
    end
  end

  defp emit_parse_event(file) do
    start_time = System.monotonic_time(:millisecond)

    result = Parser.parse(file)

    duration = System.monotonic_time(:millisecond) - start_time

    status = if match?({:ok, _}, result), do: :success, else: :error

    :telemetry.execute(
      [:portfolio_coder, :parser, :parse],
      %{duration_ms: duration},
      %{file: file, status: status}
    )
  end

  defp emit_search_event(query) do
    :telemetry.execute(
      [:portfolio_index, :vector_store, :search],
      %{duration_ms: :rand.uniform(50)},
      %{query: query, results: :rand.uniform(10)}
    )
  end

  defp display_metrics(agent) do
    state = Agent.get(agent, & &1)

    IO.puts("Event Counts:")

    for {event, count} <- Enum.sort(state.counters) do
      event_str = Enum.join(event, ".")
      IO.puts("  #{event_str}: #{count}")
    end

    IO.puts("")

    IO.puts("Timing Statistics:")

    for {event, timings} <- state.timings do
      if length(timings) > 0 do
        event_str = Enum.join(event, ".")
        avg = Enum.sum(timings) / length(timings)
        min = Enum.min(timings)
        max = Enum.max(timings)

        IO.puts("  #{event_str}:")
        IO.puts("    Count: #{length(timings)}")
        IO.puts("    Avg: #{Float.round(avg, 2)}ms")
        IO.puts("    Min: #{min}ms")
        IO.puts("    Max: #{max}ms")
      end
    end

    IO.puts("")

    IO.puts("Recent Events (last 5):")

    state.events
    |> Enum.take(5)
    |> Enum.each(fn event ->
      event_str = Enum.join(event.name, ".")
      time_str = Calendar.strftime(event.timestamp, "%H:%M:%S")
      duration = event.measurements[:duration_ms]
      duration_str = if duration, do: " (#{duration}ms)", else: ""
      IO.puts("  [#{time_str}] #{event_str}#{duration_str}")
    end)
  end

  defp run_live_demo(agent) do
    IO.puts("Running live metrics collection for 3 seconds...")
    IO.puts("")

    # Run some operations in background
    Task.async(fn ->
      for _ <- 1..10 do
        Process.sleep(200)
        emit_search_event("live-query-#{:rand.uniform(100)}")
      end
    end)

    # Show live updates
    for i <- 1..3 do
      Process.sleep(1000)
      state = Agent.get(agent, & &1)
      total_events = Enum.sum(Map.values(state.counters))
      IO.puts("  #{i}s: #{total_events} total events collected")
    end

    IO.puts("")
  end

  defp print_header(text) do
    IO.puts(String.duplicate("=", 70))
    IO.puts(text)
    IO.puts(String.duplicate("=", 70))
    IO.puts("")
  end

  defp print_section(text) do
    IO.puts(String.duplicate("-", 70))
    IO.puts(text)
    IO.puts(String.duplicate("-", 70))
    IO.puts("")
  end
end

TelemetryDemo.run()
