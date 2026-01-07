defmodule PortfolioCoder.QA.SelfCorrecting do
  @moduledoc """
  Self-correcting Q&A with retrieval reflection.

  Implements the Self-RAG pattern where answers are critiqued and refined
  iteratively until sufficient confidence is achieved.

  ## Process

  1. Retrieve initial context
  2. Generate initial answer
  3. Critique the answer (is it complete? accurate?)
  4. If needed, retrieve more context for missing aspects
  5. Refine the answer
  6. Repeat until confident or max iterations reached

  ## Usage

      {:ok, index} = InMemorySearch.new()
      # ... add documents ...

      qa = SelfCorrecting.new(index,
        llm_module: MyLLM,
        max_iterations: 3,
        confidence_threshold: 0.8
      )

      {:ok, result} = SelfCorrecting.ask(qa, "How does authentication work?")

      IO.puts(result.final_answer)
      IO.puts("Iterations: \#{result.iterations}")
      IO.puts("Confidence: \#{result.final_confidence}")
  """

  alias PortfolioCoder.Indexer.InMemorySearch

  defstruct [
    :index,
    :llm_module,
    :max_iterations,
    :confidence_threshold,
    :max_results,
    :generation_prompt,
    :critique_prompt,
    :refinement_prompt
  ]

  @type critique :: %{
          is_sufficient: boolean(),
          confidence: float(),
          missing_aspects: [String.t()]
        }

  @type t :: %__MODULE__{
          index: pid() | nil,
          llm_module: module() | nil,
          max_iterations: pos_integer(),
          confidence_threshold: float(),
          max_results: pos_integer(),
          generation_prompt: String.t(),
          critique_prompt: String.t(),
          refinement_prompt: String.t()
        }

  @default_generation_prompt """
  Answer this question about the codebase using the provided context.

  Context:
  <%= context %>

  Question: <%= question %>

  Provide a detailed answer:
  """

  @default_critique_prompt """
  Review this answer and determine if it adequately answers the question.

  Question: <%= question %>

  Answer: <%= answer %>

  Context used: <%= context_summary %>

  Evaluate:
  1. Is the answer complete?
  2. Does it directly address the question?
  3. Is there information that seems missing?

  Respond with JSON:
  {"is_sufficient": true/false, "missing_aspects": ["aspect1", "aspect2"], "confidence": 0.0-1.0}
  """

  @default_refinement_prompt """
  Improve this answer using the additional context.

  Original Question: <%= question %>
  Previous Answer: <%= previous_answer %>
  Missing Aspects: <%= missing %>

  Additional Context:
  <%= new_context %>

  Provide an improved, more complete answer:
  """

  @default_config %{
    max_iterations: 2,
    confidence_threshold: 0.8,
    max_results: 5
  }

  @doc """
  Create a new self-correcting QA instance.

  ## Options

    * `:max_iterations` - Maximum refinement iterations (default: 2)
    * `:confidence_threshold` - Confidence level to accept answer (default: 0.8)
    * `:llm_module` - LLM module for generation/critique
    * `:max_results` - Results per retrieval (default: 5)
  """
  @spec new(pid() | nil, keyword()) :: t()
  def new(index, opts \\ []) do
    %__MODULE__{
      index: index,
      llm_module: Keyword.get(opts, :llm_module),
      max_iterations: Keyword.get(opts, :max_iterations, 2),
      confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.8),
      max_results: Keyword.get(opts, :max_results, 5),
      generation_prompt: Keyword.get(opts, :generation_prompt, @default_generation_prompt),
      critique_prompt: Keyword.get(opts, :critique_prompt, @default_critique_prompt),
      refinement_prompt: Keyword.get(opts, :refinement_prompt, @default_refinement_prompt)
    }
  end

  @doc """
  Ask a question with self-correction.

  Returns a result with:
    * `:question` - Original question
    * `:context` - Final context used
    * `:sources` - Source documents
    * `:initial_answer` - First answer generated
    * `:final_answer` - Final refined answer
    * `:iterations` - Number of refinement iterations
    * `:final_confidence` - Final confidence score
    * `:critiques` - List of critiques from each iteration
  """
  @spec ask(t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def ask(%__MODULE__{} = qa, question, opts \\ []) do
    # Step 1: Initial retrieval
    {:ok, context} = retrieve_context(qa, question)

    result = %{
      question: question,
      context: context.formatted,
      sources: prepare_sources(context.documents),
      iterations: 0,
      critiques: []
    }

    # Step 2: Generate initial answer (or skip if no LLM)
    result =
      if qa.llm_module do
        case generate_answer(qa, question, context.formatted) do
          {:ok, answer} ->
            Map.merge(result, %{initial_answer: answer, final_answer: answer})

          {:error, _} ->
            Map.merge(result, %{
              initial_answer: nil,
              final_answer: nil,
              final_confidence: 0.0
            })
        end
      else
        Map.merge(result, %{
          initial_answer: nil,
          final_answer: nil,
          final_confidence: 0.5
        })
      end

    # Step 3: Self-correction loop (only if LLM configured)
    result =
      if qa.llm_module && result.initial_answer do
        refine_loop(qa, result, context.documents, 0, opts)
      else
        result
      end

    {:ok, result}
  end

  @doc """
  Critique an answer.

  Returns a critique map with:
    * `:is_sufficient` - Whether the answer is complete
    * `:confidence` - Confidence score (0.0-1.0)
    * `:missing_aspects` - List of missing information
  """
  @spec critique(String.t(), String.t(), keyword()) :: critique()
  def critique(answer, question, opts \\ []) do
    context_summary = Keyword.get(opts, :context_summary, "unknown")
    llm_module = Keyword.get(opts, :llm_module)

    if llm_module do
      prompt =
        @default_critique_prompt
        |> String.replace("<%= question %>", question)
        |> String.replace("<%= answer %>", answer)
        |> String.replace("<%= context_summary %>", context_summary)

      case call_llm(llm_module, prompt) do
        {:ok, response} -> parse_critique_response(response)
        {:error, _} -> default_critique()
      end
    else
      # Without LLM, return a moderate critique
      default_critique()
    end
  end

  @doc """
  Parse a critique response from JSON.
  """
  @spec parse_critique_response(String.t()) :: critique()
  def parse_critique_response(response) do
    case Regex.run(~r/\{[^}]+\}/, response) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, data} ->
            %{
              is_sufficient: Map.get(data, "is_sufficient", true),
              missing_aspects: Map.get(data, "missing_aspects", []),
              confidence: Map.get(data, "confidence", 0.5) |> ensure_float()
            }

          {:error, _} ->
            default_critique()
        end

      nil ->
        default_critique()
    end
  end

  @doc """
  Determine if refinement is needed based on critique.
  """
  @spec should_refine?(t(), critique()) :: boolean()
  def should_refine?(%__MODULE__{} = qa, critique) do
    not critique.is_sufficient or critique.confidence < qa.confidence_threshold
  end

  @doc """
  Retrieve additional context for missing aspects.
  """
  @spec retrieve_additional_context(t(), [String.t()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def retrieve_additional_context(%__MODULE__{} = qa, missing_aspects, _opts \\ []) do
    if Enum.empty?(missing_aspects) or is_nil(qa.index) do
      {:ok, %{documents: [], formatted: ""}}
    else
      # Search for each missing aspect
      documents =
        missing_aspects
        |> Enum.flat_map(fn aspect ->
          {:ok, results} = InMemorySearch.search(qa.index, aspect, limit: 2)
          results
        end)
        |> Enum.uniq_by(& &1.id)
        |> Enum.take(qa.max_results)

      {:ok,
       %{
         documents: documents,
         formatted: format_context(documents)
       }}
    end
  end

  @doc """
  Get default configuration.
  """
  @spec config() :: map()
  def config do
    @default_config
  end

  @doc """
  Set maximum iterations.
  """
  @spec with_max_iterations(t(), pos_integer()) :: t()
  def with_max_iterations(%__MODULE__{} = qa, max_iterations) do
    %{qa | max_iterations: max_iterations}
  end

  @doc """
  Set confidence threshold.
  """
  @spec with_confidence_threshold(t(), float()) :: t()
  def with_confidence_threshold(%__MODULE__{} = qa, threshold) do
    %{qa | confidence_threshold: threshold}
  end

  @doc """
  Set LLM module.
  """
  @spec with_llm(t(), module()) :: t()
  def with_llm(%__MODULE__{} = qa, llm_module) do
    %{qa | llm_module: llm_module}
  end

  # Private functions

  defp retrieve_context(%__MODULE__{index: nil}, _query) do
    {:ok, %{documents: [], formatted: "No search index configured."}}
  end

  defp retrieve_context(%__MODULE__{} = qa, query) do
    {:ok, documents} = InMemorySearch.search(qa.index, query, limit: qa.max_results)

    {:ok,
     %{
       documents: documents,
       formatted: format_context(documents)
     }}
  end

  defp format_context([]) do
    "No relevant code found."
  end

  defp format_context(documents) do
    Enum.map_join(documents, "\n---\n", fn doc ->
      path = doc.metadata[:path] || doc.id
      "File: #{Path.basename(path)}\n#{doc.content}"
    end)
  end

  defp prepare_sources(documents) do
    Enum.map(documents, fn doc ->
      %{
        id: doc.id,
        path: doc.metadata[:path] || doc.id
      }
    end)
  end

  defp generate_answer(qa, question, context) do
    prompt =
      qa.generation_prompt
      |> String.replace("<%= context %>", context)
      |> String.replace("<%= question %>", question)

    call_llm(qa.llm_module, prompt)
  end

  defp refine_loop(qa, result, documents, iteration, opts) when iteration < qa.max_iterations do
    # Critique current answer
    context_summary =
      Enum.map_join(documents, ", ", fn d ->
        Path.basename(d.metadata[:path] || d.id)
      end)

    critique_result =
      critique(
        result.final_answer,
        result.question,
        context_summary: context_summary,
        llm_module: qa.llm_module
      )

    new_critiques = result.critiques ++ [critique_result]

    if should_refine?(qa, critique_result) do
      refine_with_additional_context(
        qa,
        result,
        documents,
        iteration,
        new_critiques,
        critique_result,
        opts
      )
    else
      finalize_refinement(result, new_critiques, iteration, critique_result.confidence)
    end
  end

  defp refine_loop(_qa, result, _documents, iteration, _opts) do
    # Max iterations reached
    %{result | iterations: iteration, final_confidence: 0.5}
  end

  defp refine_with_additional_context(
         qa,
         result,
         documents,
         iteration,
         critiques,
         critique_result,
         opts
       ) do
    case retrieve_additional_context(qa, critique_result.missing_aspects, opts) do
      {:ok, %{documents: [], formatted: _}} ->
        finalize_refinement(result, critiques, iteration, critique_result.confidence)

      {:ok, additional} ->
        refine_answer_with_context(
          qa,
          result,
          documents,
          iteration,
          critiques,
          critique_result,
          additional,
          opts
        )
    end
  end

  defp refine_answer_with_context(
         qa,
         result,
         documents,
         iteration,
         critiques,
         critique_result,
         additional,
         opts
       ) do
    case refine_answer(
           qa,
           result.question,
           result.final_answer,
           critique_result.missing_aspects,
           additional.formatted
         ) do
      {:ok, refined_answer} ->
        new_result = %{
          result
          | final_answer: refined_answer,
            iterations: iteration + 1,
            critiques: critiques
        }

        new_docs = documents ++ additional.documents
        refine_loop(qa, new_result, new_docs, iteration + 1, opts)

      {:error, _} ->
        finalize_refinement(result, critiques, iteration, critique_result.confidence)
    end
  end

  defp finalize_refinement(result, critiques, iteration, confidence) do
    %{
      result
      | iterations: iteration + 1,
        critiques: critiques,
        final_confidence: confidence
    }
  end

  defp refine_answer(qa, question, previous, missing, new_context) do
    missing_str = Enum.join(missing, ", ")

    prompt =
      qa.refinement_prompt
      |> String.replace("<%= question %>", question)
      |> String.replace("<%= previous_answer %>", previous)
      |> String.replace("<%= missing %>", missing_str)
      |> String.replace("<%= new_context %>", new_context)

    call_llm(qa.llm_module, prompt)
  end

  defp call_llm(llm_module, prompt) do
    messages = [%{role: :user, content: prompt}]

    case llm_module.complete(messages, max_tokens: 1000) do
      {:ok, %{content: answer}} ->
        {:ok, String.trim(answer)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp default_critique do
    %{
      is_sufficient: true,
      confidence: 0.5,
      missing_aspects: []
    }
  end

  defp ensure_float(value) when is_float(value), do: value
  defp ensure_float(value) when is_integer(value), do: value / 1
  defp ensure_float(_), do: 0.5
end
