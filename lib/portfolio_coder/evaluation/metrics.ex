defmodule PortfolioCoder.Evaluation.Metrics do
  @moduledoc """
  Retrieval and ranking metrics for evaluating search quality.

  Implements standard information retrieval metrics:

  - **Recall@K**: Fraction of relevant documents found in top K
  - **Precision@K**: Fraction of top K documents that are relevant
  - **MRR**: Mean Reciprocal Rank - position of first relevant result
  - **Hit Rate**: Whether any relevant document was retrieved
  - **NDCG@K**: Normalized Discounted Cumulative Gain
  - **F1 Score**: Harmonic mean of precision and recall
  - **Average Precision**: Average of precision at each relevant position

  ## Usage

      retrieved = ["doc1", "doc2", "doc3"]
      relevant = MapSet.new(["doc1", "doc3"])

      Metrics.recall_at_k(retrieved, relevant, 3)    # => 1.0
      Metrics.precision_at_k(retrieved, relevant, 3) # => 0.67
      Metrics.mrr(retrieved, relevant)               # => 1.0

      # Or calculate all metrics at once
      Metrics.calculate_all(retrieved, relevant, k: 3)
  """

  @type doc_id :: String.t()
  @type relevance_scores :: %{doc_id() => number()}

  @doc """
  Calculate Recall@K - fraction of relevant documents in top K results.

  Recall = |Retrieved ∩ Relevant| / |Relevant|
  """
  @spec recall_at_k([doc_id()], MapSet.t(), non_neg_integer()) :: float()
  def recall_at_k(retrieved, relevant, k) do
    if MapSet.size(relevant) == 0 do
      0.0
    else
      top_k = Enum.take(retrieved, k)
      relevant_found = Enum.count(top_k, &MapSet.member?(relevant, &1))
      relevant_found / MapSet.size(relevant)
    end
  end

  @doc """
  Calculate Precision@K - fraction of top K results that are relevant.

  Precision = |Retrieved ∩ Relevant| / K
  """
  @spec precision_at_k([doc_id()], MapSet.t(), non_neg_integer()) :: float()
  def precision_at_k(retrieved, relevant, k) do
    top_k = Enum.take(retrieved, k)
    actual_k = length(top_k)

    if actual_k == 0 do
      0.0
    else
      relevant_found = Enum.count(top_k, &MapSet.member?(relevant, &1))
      relevant_found / actual_k
    end
  end

  @doc """
  Calculate Mean Reciprocal Rank - 1/position of first relevant result.

  MRR = 1 / rank(first_relevant)
  """
  @spec mrr([doc_id()], MapSet.t()) :: float()
  def mrr(retrieved, relevant) do
    case Enum.find_index(retrieved, &MapSet.member?(relevant, &1)) do
      nil -> 0.0
      index -> 1 / (index + 1)
    end
  end

  @doc """
  Calculate Hit Rate - whether any relevant document was retrieved.

  Hit Rate = 1 if any relevant found, 0 otherwise
  """
  @spec hit_rate([doc_id()], MapSet.t()) :: float()
  def hit_rate(retrieved, relevant) do
    if Enum.any?(retrieved, &MapSet.member?(relevant, &1)), do: 1.0, else: 0.0
  end

  @doc """
  Calculate NDCG@K - Normalized Discounted Cumulative Gain.

  NDCG measures ranking quality considering graded relevance scores.
  NDCG = DCG / IDCG where DCG = Σ (2^rel - 1) / log2(rank + 1)
  """
  @spec ndcg_at_k([doc_id()], relevance_scores(), non_neg_integer()) :: float()
  def ndcg_at_k(retrieved, relevance_scores, k) do
    dcg = calculate_dcg(retrieved, relevance_scores, k)
    idcg = calculate_idcg(relevance_scores, k)

    if idcg == 0 do
      0.0
    else
      dcg / idcg
    end
  end

  @doc """
  Calculate F1 Score - harmonic mean of precision and recall.

  F1 = 2 * (precision * recall) / (precision + recall)
  """
  @spec f1_score(float(), float()) :: float()
  def f1_score(precision, recall) do
    if precision + recall == 0 do
      0.0
    else
      2 * precision * recall / (precision + recall)
    end
  end

  @doc """
  Calculate Average Precision - mean of precision at each relevant position.

  AP = (1/R) * Σ P(k) * rel(k) where R is total relevant documents
  """
  @spec average_precision([doc_id()], MapSet.t()) :: float()
  def average_precision(retrieved, relevant) do
    relevant_count = MapSet.size(relevant)

    if relevant_count == 0 do
      0.0
    else
      precision_sum(retrieved, relevant) / relevant_count
    end
  end

  defp precision_sum(retrieved, relevant) do
    retrieved
    |> Enum.with_index(1)
    |> Enum.reduce({0.0, 0}, &update_precision_sum(relevant, &1, &2))
    |> elem(0)
  end

  defp update_precision_sum(relevant, {doc, k}, {sum, rel_count}) do
    if MapSet.member?(relevant, doc) do
      new_rel_count = rel_count + 1
      {sum + new_rel_count / k, new_rel_count}
    else
      {sum, rel_count}
    end
  end

  @doc """
  Calculate all retrieval metrics at once.

  ## Options

  - `:k` - The K value for @K metrics (default: 10)
  - `:relevance_scores` - Map of doc_id => score for NDCG (optional)

  ## Returns

  Map with all metric values.
  """
  @spec calculate_all([doc_id()], MapSet.t(), keyword()) :: map()
  def calculate_all(retrieved, relevant, opts \\ []) do
    k = Keyword.get(opts, :k, 10)
    relevance_scores = Keyword.get(opts, :relevance_scores, %{})

    recall = recall_at_k(retrieved, relevant, k)
    precision = precision_at_k(retrieved, relevant, k)

    metrics = %{
      recall_at_k: recall,
      precision_at_k: precision,
      mrr: mrr(retrieved, relevant),
      hit_rate: hit_rate(retrieved, relevant),
      f1_score: f1_score(precision, recall),
      average_precision: average_precision(retrieved, relevant),
      k: k
    }

    # Add NDCG if relevance scores provided
    if map_size(relevance_scores) > 0 do
      Map.put(metrics, :ndcg_at_k, ndcg_at_k(retrieved, relevance_scores, k))
    else
      metrics
    end
  end

  # Private helpers

  defp calculate_dcg(retrieved, relevance_scores, k) do
    retrieved
    |> Enum.take(k)
    |> Enum.with_index(1)
    |> Enum.reduce(0.0, fn {doc, rank}, sum ->
      rel = Map.get(relevance_scores, doc, 0)
      gain = (:math.pow(2, rel) - 1) / :math.log2(rank + 1)
      sum + gain
    end)
  end

  defp calculate_idcg(relevance_scores, k) do
    relevance_scores
    |> Map.values()
    |> Enum.sort(:desc)
    |> Enum.take(k)
    |> Enum.with_index(1)
    |> Enum.reduce(0.0, fn {rel, rank}, sum ->
      gain = (:math.pow(2, rel) - 1) / :math.log2(rank + 1)
      sum + gain
    end)
  end
end
