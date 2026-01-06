defmodule PortfolioCoder.Evaluation.RAGTriadTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Evaluation.RAGTriad

  describe "evaluate/3" do
    test "evaluates all three dimensions" do
      question = "What does the add function do?"
      context = "def add(a, b), do: a + b"
      answer = "The add function takes two numbers and returns their sum."

      {:ok, result} = RAGTriad.evaluate(question, context, answer)

      assert Map.has_key?(result, :context_relevance)
      assert Map.has_key?(result, :groundedness)
      assert Map.has_key?(result, :answer_relevance)
      assert Map.has_key?(result, :overall_score)

      assert result.context_relevance >= 0.0 and result.context_relevance <= 1.0
      assert result.groundedness >= 0.0 and result.groundedness <= 1.0
      assert result.answer_relevance >= 0.0 and result.answer_relevance <= 1.0
    end
  end

  describe "context_relevance/2" do
    test "higher score for relevant context than irrelevant" do
      question = "How do I authenticate users?"
      relevant_context = "def authenticate(user, password) do verify_password(user, password) end"
      irrelevant_context = "def calculate_tax(amount, rate), do: amount * rate"

      relevant_score = RAGTriad.context_relevance(question, relevant_context)
      irrelevant_score = RAGTriad.context_relevance(question, irrelevant_context)

      # Relevant context should score higher than irrelevant
      assert relevant_score > irrelevant_score
    end

    test "returns score in valid range" do
      question = "How do I authenticate users?"
      context = "def authenticate(user, password) do verify_password(user, password) end"

      score = RAGTriad.context_relevance(question, context)

      assert score >= 0.0 and score <= 1.0
    end

    test "handles empty context" do
      score = RAGTriad.context_relevance("any question", "")
      assert score == 0.0
    end
  end

  describe "groundedness/2" do
    test "high score for grounded answer" do
      context = "The User module has functions: create/1, update/2, delete/1"
      answer = "The User module provides three functions: create, update, and delete."

      score = RAGTriad.groundedness(context, answer)

      assert score > 0.5
    end

    test "low score for ungrounded answer" do
      context = "The User module has functions: create/1, update/2, delete/1"
      answer = "The User module uses machine learning for authentication."

      score = RAGTriad.groundedness(context, answer)

      assert score < 0.5
    end

    test "handles empty answer" do
      score = RAGTriad.groundedness("some context", "")
      assert score == 0.0
    end
  end

  describe "answer_relevance/2" do
    test "higher score for relevant answer than irrelevant" do
      question = "What is the purpose of GenServer?"

      relevant_answer =
        "GenServer is a behavior for implementing server processes with state management and message handling."

      irrelevant_answer = "The weather is nice today."

      relevant_score = RAGTriad.answer_relevance(question, relevant_answer)
      irrelevant_score = RAGTriad.answer_relevance(question, irrelevant_answer)

      # Relevant answer should score higher
      assert relevant_score > irrelevant_score
    end

    test "returns score in valid range" do
      question = "What is the purpose of GenServer?"
      answer = "GenServer is a behavior for implementing server processes."

      score = RAGTriad.answer_relevance(question, answer)

      assert score >= 0.0 and score <= 1.0
    end

    test "handles empty inputs" do
      score = RAGTriad.answer_relevance("", "some answer")
      assert score == 0.0

      score = RAGTriad.answer_relevance("some question", "")
      assert score == 0.0
    end
  end

  describe "overall_score/3" do
    test "calculates weighted average" do
      scores = %{
        context_relevance: 0.8,
        groundedness: 0.6,
        answer_relevance: 0.7
      }

      overall = RAGTriad.overall_score(scores)

      # Default equal weights
      expected = (0.8 + 0.6 + 0.7) / 3
      assert_in_delta overall, expected, 0.01
    end

    test "supports custom weights" do
      scores = %{
        context_relevance: 0.8,
        groundedness: 0.6,
        answer_relevance: 0.7
      }

      weights = %{context_relevance: 0.2, groundedness: 0.5, answer_relevance: 0.3}
      overall = RAGTriad.overall_score(scores, weights: weights)

      expected = 0.8 * 0.2 + 0.6 * 0.5 + 0.7 * 0.3
      assert_in_delta overall, expected, 0.01
    end
  end

  describe "detect_hallucination/2" do
    test "returns hallucination result structure" do
      context = "The module has two functions: foo and bar"

      answer =
        "The module has functions foo, bar, baz, and qux for comprehensive handling of all data types."

      result = RAGTriad.detect_hallucination(context, answer)

      assert Map.has_key?(result, :has_hallucination)
      assert Map.has_key?(result, :unsupported_claims)
      assert Map.has_key?(result, :confidence)
    end

    test "no hallucination for well-grounded answer" do
      context = "The add function adds two numbers and returns the sum."
      answer = "The add function adds two numbers."

      result = RAGTriad.detect_hallucination(context, answer)

      assert result.has_hallucination == false
    end

    test "confidence score in valid range" do
      context = "Some context"
      answer = "Some answer."

      result = RAGTriad.detect_hallucination(context, answer)

      assert result.confidence >= 0.0 and result.confidence <= 1.0
    end
  end

  describe "evaluate_batch/1" do
    test "evaluates multiple QA pairs" do
      test_cases = [
        %{
          question: "What is foo?",
          context: "foo is a function that returns bar",
          answer: "foo returns bar"
        },
        %{
          question: "What is baz?",
          context: "baz processes input data",
          answer: "baz is for data processing"
        }
      ]

      {:ok, results} = RAGTriad.evaluate_batch(test_cases)

      assert length(results) == 2
      assert Enum.all?(results, &Map.has_key?(&1, :overall_score))
    end

    test "calculates aggregate metrics" do
      test_cases = [
        %{question: "Q1", context: "C1 relevant", answer: "A1 relevant"},
        %{question: "Q2", context: "C2 relevant", answer: "A2 relevant"}
      ]

      {:ok, results} = RAGTriad.evaluate_batch(test_cases, aggregate: true)

      assert Map.has_key?(results, :average_scores)
      assert Map.has_key?(results, :individual_results)
    end
  end
end
