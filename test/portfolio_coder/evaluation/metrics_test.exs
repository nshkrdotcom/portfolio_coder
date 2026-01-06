defmodule PortfolioCoder.Evaluation.MetricsTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Evaluation.Metrics

  describe "recall_at_k/3" do
    test "calculates recall with all relevant items retrieved" do
      retrieved = ["doc1", "doc2", "doc3"]
      relevant = MapSet.new(["doc1", "doc2", "doc3"])

      assert Metrics.recall_at_k(retrieved, relevant, 3) == 1.0
    end

    test "calculates recall with partial retrieval" do
      retrieved = ["doc1", "doc2", "doc4", "doc5"]
      relevant = MapSet.new(["doc1", "doc2", "doc3"])

      # 2 out of 3 relevant docs found
      assert Metrics.recall_at_k(retrieved, relevant, 4) == 2 / 3
    end

    test "calculates recall at specific k" do
      retrieved = ["doc1", "doc2", "doc3", "doc4", "doc5"]
      relevant = MapSet.new(["doc2", "doc4"])

      # At k=2: only doc2 is found (1/2 = 0.5)
      assert Metrics.recall_at_k(retrieved, relevant, 2) == 0.5
      # At k=4: both doc2 and doc4 found (2/2 = 1.0)
      assert Metrics.recall_at_k(retrieved, relevant, 4) == 1.0
    end

    test "handles empty relevant set" do
      retrieved = ["doc1", "doc2"]
      relevant = MapSet.new([])

      assert Metrics.recall_at_k(retrieved, relevant, 2) == 0.0
    end
  end

  describe "precision_at_k/3" do
    test "calculates precision with all retrieved relevant" do
      retrieved = ["doc1", "doc2", "doc3"]
      relevant = MapSet.new(["doc1", "doc2", "doc3"])

      assert Metrics.precision_at_k(retrieved, relevant, 3) == 1.0
    end

    test "calculates precision with some irrelevant" do
      retrieved = ["doc1", "irrelevant1", "doc2", "irrelevant2"]
      relevant = MapSet.new(["doc1", "doc2", "doc3"])

      # 2 relevant out of 4 retrieved at k=4
      assert Metrics.precision_at_k(retrieved, relevant, 4) == 0.5
    end

    test "calculates precision at specific k" do
      retrieved = ["doc1", "irrelevant", "doc2"]
      relevant = MapSet.new(["doc1", "doc2"])

      # At k=1: 1/1 = 1.0
      assert Metrics.precision_at_k(retrieved, relevant, 1) == 1.0
      # At k=2: 1/2 = 0.5
      assert Metrics.precision_at_k(retrieved, relevant, 2) == 0.5
    end
  end

  describe "mrr/2" do
    test "calculates MRR for single query" do
      # First relevant at position 1
      retrieved = ["relevant", "other1", "other2"]
      relevant = MapSet.new(["relevant"])

      assert Metrics.mrr(retrieved, relevant) == 1.0
    end

    test "calculates MRR when first relevant is not first" do
      retrieved = ["other1", "other2", "relevant", "other3"]
      relevant = MapSet.new(["relevant"])

      # First relevant at position 3 -> 1/3
      assert Metrics.mrr(retrieved, relevant) == 1 / 3
    end

    test "returns 0 when no relevant found" do
      retrieved = ["other1", "other2", "other3"]
      relevant = MapSet.new(["relevant"])

      assert Metrics.mrr(retrieved, relevant) == 0.0
    end
  end

  describe "hit_rate/2" do
    test "returns 1 when any relevant found" do
      retrieved = ["other1", "relevant", "other2"]
      relevant = MapSet.new(["relevant"])

      assert Metrics.hit_rate(retrieved, relevant) == 1.0
    end

    test "returns 0 when no relevant found" do
      retrieved = ["other1", "other2", "other3"]
      relevant = MapSet.new(["relevant"])

      assert Metrics.hit_rate(retrieved, relevant) == 0.0
    end
  end

  describe "ndcg_at_k/3" do
    test "calculates NDCG with perfect ranking" do
      # Relevance scores: doc1=3, doc2=2, doc3=1
      retrieved = ["doc1", "doc2", "doc3"]
      relevance = %{"doc1" => 3, "doc2" => 2, "doc3" => 1}

      # Perfect ranking should give NDCG = 1.0
      assert_in_delta Metrics.ndcg_at_k(retrieved, relevance, 3), 1.0, 0.01
    end

    test "calculates NDCG with imperfect ranking" do
      # Relevance scores: doc1=3, doc2=2, doc3=1
      # Retrieved in reverse order (worst ranking)
      retrieved = ["doc3", "doc2", "doc1"]
      relevance = %{"doc1" => 3, "doc2" => 2, "doc3" => 1}

      # Imperfect ranking should give NDCG < 1.0
      ndcg = Metrics.ndcg_at_k(retrieved, relevance, 3)
      assert ndcg < 1.0
      assert ndcg > 0.0
    end
  end

  describe "f1_score/2" do
    test "calculates F1 from precision and recall" do
      # F1 = 2 * (precision * recall) / (precision + recall)
      assert_in_delta Metrics.f1_score(0.8, 0.6), 0.685, 0.01
    end

    test "returns 0 when precision and recall are 0" do
      assert Metrics.f1_score(0.0, 0.0) == 0.0
    end

    test "returns 1 when both are 1" do
      assert Metrics.f1_score(1.0, 1.0) == 1.0
    end
  end

  describe "average_precision/2" do
    test "calculates average precision" do
      retrieved = ["rel1", "irr1", "rel2", "irr2", "rel3"]
      relevant = MapSet.new(["rel1", "rel2", "rel3"])

      # P@1=1/1, P@3=2/3, P@5=3/5
      # AP = (1/1 + 2/3 + 3/5) / 3
      ap = Metrics.average_precision(retrieved, relevant)
      assert_in_delta ap, 0.756, 0.01
    end

    test "returns 0 for no relevant" do
      retrieved = ["irr1", "irr2"]
      relevant = MapSet.new(["rel1"])

      assert Metrics.average_precision(retrieved, relevant) == 0.0
    end
  end

  describe "calculate_all/3" do
    test "returns all metrics in a map" do
      retrieved = ["doc1", "doc2", "doc3", "doc4", "doc5"]
      relevant = MapSet.new(["doc1", "doc3"])

      metrics = Metrics.calculate_all(retrieved, relevant, k: 5)

      assert Map.has_key?(metrics, :recall_at_k)
      assert Map.has_key?(metrics, :precision_at_k)
      assert Map.has_key?(metrics, :mrr)
      assert Map.has_key?(metrics, :hit_rate)
      assert Map.has_key?(metrics, :f1_score)
    end
  end
end
