defmodule PortfolioCoder.Evaluation.RAGTriad do
  @moduledoc """
  RAG Triad evaluation for assessing RAG system quality.

  The RAG Triad evaluates three key dimensions:

  1. **Context Relevance**: Is the retrieved context relevant to the question?
  2. **Groundedness**: Is the answer grounded in the provided context?
  3. **Answer Relevance**: Does the answer actually address the question?

  These three metrics together provide a comprehensive view of RAG quality
  and help identify specific failure modes.

  ## Usage

      {:ok, result} = RAGTriad.evaluate(question, context, answer)

      # Result contains:
      # %{
      #   context_relevance: 0.85,
      #   groundedness: 0.92,
      #   answer_relevance: 0.88,
      #   overall_score: 0.88
      # }

  ## Hallucination Detection

      result = RAGTriad.detect_hallucination(context, answer)
      # %{has_hallucination: true, unsupported_claims: [...]}
  """

  @doc """
  Evaluate all three dimensions of the RAG triad.

  Returns scores for context relevance, groundedness, and answer relevance,
  plus an overall weighted score.
  """
  @spec evaluate(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def evaluate(question, context, answer, opts \\ []) do
    context_rel = context_relevance(question, context)
    grounded = groundedness(context, answer)
    answer_rel = answer_relevance(question, answer)

    scores = %{
      context_relevance: context_rel,
      groundedness: grounded,
      answer_relevance: answer_rel
    }

    overall = overall_score(scores, opts)

    {:ok,
     Map.merge(scores, %{
       overall_score: overall,
       hallucination: detect_hallucination(context, answer)
     })}
  end

  @doc """
  Calculate context relevance - how relevant is the context to the question?

  Uses keyword overlap and semantic similarity estimation.
  """
  @spec context_relevance(String.t(), String.t()) :: float()
  def context_relevance(_question, "") do
    0.0
  end

  def context_relevance(question, context) do
    question_tokens = tokenize(question)
    context_tokens = tokenize(context)

    # Calculate keyword overlap
    keyword_score = jaccard_similarity(question_tokens, context_tokens)

    # Boost for question-answer indicators in context
    qa_boost = if has_qa_indicators?(question, context), do: 0.2, else: 0.0

    # Combine scores (capped at 1.0)
    min(keyword_score + qa_boost, 1.0)
  end

  @doc """
  Calculate groundedness - is the answer supported by the context?

  Checks if claims in the answer can be traced back to the context.
  """
  @spec groundedness(String.t(), String.t()) :: float()
  def groundedness(_context, "") do
    0.0
  end

  def groundedness(context, answer) do
    context_tokens = tokenize(context)
    answer_tokens = tokenize(answer)

    # Calculate what fraction of answer tokens appear in context
    coverage = token_coverage(answer_tokens, context_tokens)

    # Penalize very long answers (likely adding unsupported info)
    length_penalty =
      if length(answer_tokens) > length(context_tokens) * 2 do
        0.8
      else
        1.0
      end

    coverage * length_penalty
  end

  @doc """
  Calculate answer relevance - does the answer address the question?

  Uses keyword matching and answer type detection.
  """
  @spec answer_relevance(String.t(), String.t()) :: float()
  def answer_relevance("", _answer), do: 0.0
  def answer_relevance(_question, ""), do: 0.0

  def answer_relevance(question, answer) do
    question_tokens = tokenize(question)
    answer_tokens = tokenize(answer)

    # Keyword overlap
    keyword_score = jaccard_similarity(question_tokens, answer_tokens)

    # Check if answer type matches question type
    type_match_score = answer_type_match(question, answer)

    # Combine (weighted average)
    keyword_score * 0.6 + type_match_score * 0.4
  end

  @doc """
  Calculate overall score from individual scores.

  ## Options

  - `:weights` - Custom weights for each dimension (default: equal weights)
  """
  @spec overall_score(map(), keyword()) :: float()
  def overall_score(scores, opts \\ []) do
    default_weights = %{
      context_relevance: 1 / 3,
      groundedness: 1 / 3,
      answer_relevance: 1 / 3
    }

    weights = Keyword.get(opts, :weights, default_weights)

    scores.context_relevance * weights.context_relevance +
      scores.groundedness * weights.groundedness +
      scores.answer_relevance * weights.answer_relevance
  end

  @doc """
  Detect hallucination - claims in answer not supported by context.

  Returns a map with:
  - `:has_hallucination` - boolean
  - `:unsupported_claims` - list of potentially hallucinated phrases
  """
  @spec detect_hallucination(String.t(), String.t()) :: map()
  def detect_hallucination(context, answer) do
    context_tokens = MapSet.new(tokenize(context))
    answer_sentences = String.split(answer, ~r/[.!?]/, trim: true)

    unsupported =
      answer_sentences
      |> Enum.filter(fn sentence ->
        sentence_tokens = tokenize(sentence)
        # If less than 30% of tokens are in context, likely hallucination
        coverage = token_coverage(sentence_tokens, context_tokens)
        coverage < 0.3 and length(sentence_tokens) > 3
      end)
      |> Enum.map(&String.trim/1)

    %{
      has_hallucination: unsupported != [],
      unsupported_claims: unsupported,
      confidence: calculate_hallucination_confidence(unsupported, answer_sentences)
    }
  end

  @doc """
  Evaluate a batch of question-context-answer triples.

  ## Options

  - `:aggregate` - Whether to calculate aggregate metrics (default: false)
  """
  @spec evaluate_batch([map()], keyword()) :: {:ok, map() | [map()]}
  def evaluate_batch(test_cases, opts \\ []) do
    results =
      test_cases
      |> Enum.map(fn tc ->
        {:ok, result} = evaluate(tc.question, tc.context, tc.answer)
        Map.put(result, :test_case, tc)
      end)

    if Keyword.get(opts, :aggregate, false) do
      {:ok,
       %{
         individual_results: results,
         average_scores: calculate_average_scores(results),
         pass_rate: calculate_pass_rate(results)
       }}
    else
      {:ok, results}
    end
  end

  # Private helpers

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.filter(fn token ->
      String.length(token) >= 2 and not stop_word?(token)
    end)
  end

  defp stop_word?(word) do
    word in ~w(the a an is are was were be been being have has had do does did
               will would could should may might must shall can to of and in for
               on with at by from as into through during before after above below
               this that these those it its they their them we our us you your)
  end

  defp jaccard_similarity(tokens1, tokens2) do
    set1 = MapSet.new(tokens1)
    set2 = MapSet.new(tokens2)

    intersection = MapSet.intersection(set1, set2) |> MapSet.size()
    union = MapSet.union(set1, set2) |> MapSet.size()

    if union == 0 do
      0.0
    else
      intersection / union
    end
  end

  defp token_coverage(answer_tokens, context_tokens) do
    context_set =
      if is_struct(context_tokens, MapSet) do
        context_tokens
      else
        MapSet.new(context_tokens)
      end

    token_count = length(answer_tokens)

    if token_count == 0 do
      0.0
    else
      covered = Enum.count(answer_tokens, &MapSet.member?(context_set, &1))
      covered / token_count
    end
  end

  defp has_qa_indicators?(question, context) do
    question_lower = String.downcase(question)
    context_lower = String.downcase(context)

    # Check if key question words appear in context
    question_keywords =
      question_lower
      |> String.split(~r/\s+/)
      |> Enum.filter(&(String.length(&1) > 3))
      |> Enum.take(5)

    Enum.any?(question_keywords, &String.contains?(context_lower, &1))
  end

  defp answer_type_match(question, answer) do
    question_lower = String.downcase(question)
    answer_lower = String.downcase(answer)

    case classify_question(question_lower) do
      :explanation ->
        if String.length(answer) > 20, do: 0.8, else: 0.4

      :yes_no ->
        if contains_yes_no?(answer_lower), do: 0.9, else: 0.5

      :why ->
        if contains_reasoning?(answer_lower), do: 0.9, else: 0.5

      :other ->
        0.6
    end
  end

  defp classify_question(question_lower) do
    cond do
      String.contains?(question_lower, "what") or String.contains?(question_lower, "how") ->
        :explanation

      String.contains?(question_lower, "is ") or String.contains?(question_lower, "does ") ->
        :yes_no

      String.contains?(question_lower, "why") ->
        :why

      true ->
        :other
    end
  end

  defp contains_yes_no?(answer_lower) do
    String.contains?(answer_lower, "yes") or String.contains?(answer_lower, "no")
  end

  defp contains_reasoning?(answer_lower) do
    String.contains?(answer_lower, "because") or String.contains?(answer_lower, "since")
  end

  defp calculate_hallucination_confidence(unsupported, all_sentences) do
    sentence_count = length(all_sentences)

    if sentence_count == 0 do
      0.0
    else
      length(unsupported) / sentence_count
    end
  end

  defp calculate_average_scores(results) do
    count = length(results)

    if count == 0 do
      %{}
    else
      %{
        context_relevance: Enum.sum(Enum.map(results, & &1.context_relevance)) / count,
        groundedness: Enum.sum(Enum.map(results, & &1.groundedness)) / count,
        answer_relevance: Enum.sum(Enum.map(results, & &1.answer_relevance)) / count,
        overall_score: Enum.sum(Enum.map(results, & &1.overall_score)) / count
      }
    end
  end

  defp calculate_pass_rate(results, threshold \\ 0.5) do
    result_count = length(results)

    if result_count == 0 do
      0.0
    else
      passing = Enum.count(results, &(&1.overall_score >= threshold))
      passing / result_count
    end
  end
end
