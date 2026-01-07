defmodule Mix.Tasks.Code.Eval do
  @moduledoc """
  Evaluate RAG pipeline quality.

  ## Usage

      mix code.eval [path]
      mix code.eval --metrics
      mix code.eval --test-cases

  ## Options

    * `--metrics` - Show retrieval metrics
    * `--test-cases` - Generate test cases for evaluation
    * `--output` - Output format (text, json)

  ## Examples

      # Run evaluation
      mix code.eval lib

      # Show metrics only
      mix code.eval --metrics lib

      # Generate test cases
      mix code.eval --test-cases lib
  """

  use Mix.Task

  alias PortfolioCoder.Evaluation.Metrics
  alias PortfolioCoder.Evaluation.TestGenerator
  alias PortfolioCoder.Indexer.CodeChunker
  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.Indexer.Parser

  @shortdoc "Evaluate RAG pipeline quality"

  @switches [
    metrics: :boolean,
    test_cases: :boolean,
    output: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, paths, _} = OptionParser.parse(args, switches: @switches)

    path = List.first(paths) || "lib"
    output_format = Keyword.get(opts, :output, "text")

    Mix.shell().info("RAG Evaluation")
    Mix.shell().info(String.duplicate("=", 60))

    # Build index
    Mix.shell().info("\nIndexing code...")
    {:ok, index} = InMemorySearch.new()

    doc_count = build_index(path, index)
    Mix.shell().info("  Indexed #{doc_count} documents\n")

    cond do
      Keyword.get(opts, :metrics, false) ->
        show_metrics(index)

      Keyword.get(opts, :test_cases, false) ->
        generate_test_cases(index, output_format)

      true ->
        run_evaluation(index, output_format)
    end
  end

  defp build_index(path, index) do
    path
    |> Path.join("**/*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.reject(&excluded_path?/1)
    |> Enum.take(50)
    |> Enum.reduce(0, fn file, count ->
      case index_file(file, index) do
        {:ok, docs_added} -> count + docs_added
        :skip -> count
      end
    end)
  end

  defp excluded_path?(file) do
    String.contains?(file, ["deps/", "_build/", ".git/"])
  end

  defp index_file(file, index) do
    with {:ok, parsed} <- Parser.parse(file),
         {:ok, chunks} <- CodeChunker.chunk_file(file, strategy: :hybrid, chunk_size: 800) do
      docs = build_docs(file, parsed, chunks)
      InMemorySearch.add_all(index, docs)
      {:ok, length(docs)}
    else
      _ -> :skip
    end
  end

  defp build_docs(file, parsed, chunks) do
    Enum.with_index(chunks)
    |> Enum.map(fn {chunk, idx} ->
      %{
        id: "#{Path.basename(file)}:#{idx}",
        content: chunk.content,
        metadata: %{
          path: file,
          language: parsed.language,
          type: chunk.type
        }
      }
    end)
  end

  defp show_metrics(index) do
    Mix.shell().info("--- Retrieval Metrics ---\n")

    # Create sample queries and evaluate
    queries = [
      "defmodule",
      "def parse",
      "function",
      "@doc",
      "test"
    ]

    results =
      Enum.map(queries, fn query ->
        {:ok, search_results} = InMemorySearch.search(index, query, limit: 10)

        # For demo, we simulate relevance based on query presence
        retrieved = Enum.map(search_results, & &1.id)

        relevant =
          search_results
          |> Enum.filter(fn r -> String.contains?(r.content, query) end)
          |> Enum.map(& &1.id)

        {query, retrieved, relevant}
      end)

    # Calculate metrics for each query
    for {query, retrieved, relevant} <- results do
      k = 5

      relevant_set = MapSet.new(relevant)
      recall = Metrics.recall_at_k(retrieved, relevant_set, k)
      precision = Metrics.precision_at_k(retrieved, relevant_set, k)
      f1 = Metrics.f1_score(precision, recall)

      Mix.shell().info("Query: \"#{query}\"")
      Mix.shell().info("  Recall@#{k}: #{Float.round(recall, 3)}")
      Mix.shell().info("  Precision@#{k}: #{Float.round(precision, 3)}")
      Mix.shell().info("  F1: #{Float.round(f1, 3)}")
      Mix.shell().info("")
    end

    # Aggregate metrics
    Mix.shell().info("--- Aggregate ---")

    all_retrieved = Enum.flat_map(results, fn {_, r, _} -> r end)

    all_relevant =
      results
      |> Enum.flat_map(fn {_, _, r} -> r end)
      |> MapSet.new()

    avg_recall = Metrics.recall_at_k(all_retrieved, all_relevant, 5)
    avg_precision = Metrics.precision_at_k(all_retrieved, all_relevant, 5)

    Mix.shell().info("Average Recall@5: #{Float.round(avg_recall, 3)}")
    Mix.shell().info("Average Precision@5: #{Float.round(avg_precision, 3)}")
  end

  defp generate_test_cases(index, output_format) do
    Mix.shell().info("--- Generating Test Cases ---\n")

    # Get sample documents
    {:ok, docs} = InMemorySearch.search(index, "defmodule", limit: 10)

    # Generate test cases from documents
    test_cases =
      docs
      |> Enum.flat_map(fn doc ->
        TestGenerator.from_code(doc.content, source: doc.id)
      end)
      |> Enum.take(20)

    case output_format do
      "json" ->
        json = Jason.encode!(%{test_cases: test_cases}, pretty: true)
        IO.puts(json)

      _ ->
        Mix.shell().info("Generated #{length(test_cases)} test cases:\n")

        for {tc, idx} <- Enum.with_index(test_cases, 1) do
          Mix.shell().info("#{idx}. #{tc.question}")
          Mix.shell().info("   Expected: #{String.slice(tc.expected_answer || "", 0, 50)}...")
          Mix.shell().info("")
        end
    end
  end

  defp run_evaluation(index, output_format) do
    Mix.shell().info("--- Full Evaluation ---\n")

    # Run both metrics and generate summary
    show_metrics(index)

    Mix.shell().info("\n--- Summary ---\n")

    stats = InMemorySearch.stats(index)

    summary = %{
      documents: stats.document_count,
      terms: stats.term_count,
      status: "evaluation_complete"
    }

    case output_format do
      "json" ->
        json = Jason.encode!(summary, pretty: true)
        IO.puts(json)

      _ ->
        Mix.shell().info("Documents indexed: #{summary.documents}")
        Mix.shell().info("Unique terms: #{summary.terms}")
        Mix.shell().info("Status: #{summary.status}")
    end
  end
end
