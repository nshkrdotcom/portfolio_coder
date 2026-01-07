defmodule PortfolioCoder.QA.CodeQA do
  @moduledoc """
  Code Q&A using retrieval-augmented generation (RAG).

  Provides a simple interface for asking questions about code
  using a search index and optional LLM for answer generation.

  ## Usage

      {:ok, index} = InMemorySearch.new()
      # ... add documents to index ...

      qa = CodeQA.new(index)
      {:ok, result} = CodeQA.ask(qa, "How does authentication work?")

      IO.puts(result.answer)
      IO.inspect(result.sources)

  ## Configuration Options

      qa = CodeQA.new(index,
        max_results: 5,           # Number of documents to retrieve
        llm_module: MyLLM,        # LLM module for answer generation
        answer_prompt: "...",     # Custom prompt template
        query_enhancement: true   # Enable query rewriting
      )
  """

  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.Search.QueryEnhancer

  defstruct [
    :index,
    :llm_module,
    :answer_prompt,
    :max_results,
    :query_enhancement
  ]

  @type t :: %__MODULE__{
          index: pid(),
          llm_module: module() | nil,
          answer_prompt: String.t(),
          max_results: pos_integer(),
          query_enhancement: boolean()
        }

  @default_answer_prompt """
  You are a helpful code assistant. Answer the user's question based on the provided code context.

  Rules:
  - Only use information from the provided context
  - If the context doesn't contain enough information, say so
  - Include relevant code snippets in your answer when helpful
  - Keep answers concise but complete

  Context (relevant code):
  <%= context %>

  Question: <%= question %>

  Answer:
  """

  @default_config %{
    max_results: 5,
    answer_prompt: @default_answer_prompt,
    query_enhancement: false
  }

  @doc """
  Create a new CodeQA instance.

  ## Options

    * `:max_results` - Maximum documents to retrieve (default: 5)
    * `:llm_module` - Module for LLM calls (optional)
    * `:answer_prompt` - Custom answer prompt template
    * `:query_enhancement` - Enable query rewriting (default: false)
  """
  @spec new(pid(), keyword()) :: t()
  def new(index, opts \\ []) do
    %__MODULE__{
      index: index,
      llm_module: Keyword.get(opts, :llm_module),
      answer_prompt: Keyword.get(opts, :answer_prompt, @default_answer_prompt),
      max_results: Keyword.get(opts, :max_results, 5),
      query_enhancement: Keyword.get(opts, :query_enhancement, false)
    }
  end

  @doc """
  Ask a question about the code.

  Returns a result map with:
    * `:question` - The original question
    * `:enhanced_query` - The enhanced query (if enhancement enabled)
    * `:context` - The formatted context used
    * `:sources` - List of source documents
    * `:answer` - The generated answer (if LLM configured)
  """
  @spec ask(t(), String.t(), keyword()) :: {:ok, map()}
  def ask(%__MODULE__{} = qa, question, opts \\ []) do
    # Step 1: Optionally enhance the query
    query =
      if qa.query_enhancement do
        case QueryEnhancer.rewrite(question) do
          {:ok, %{rewritten: rewritten}} -> rewritten
          {:error, _} -> question
        end
      else
        question
      end

    # Step 2: Retrieve context
    {:ok, context} = retrieve_context(qa, query)

    result = %{
      question: question,
      enhanced_query: query,
      context: context.formatted,
      sources: prepare_sources(context.documents)
    }

    # Step 3: Generate answer if LLM configured
    result =
      if qa.llm_module do
        prompt = build_prompt(context.formatted, question, prompt: qa.answer_prompt)

        case call_llm(qa.llm_module, prompt, opts) do
          {:ok, answer} ->
            Map.put(result, :answer, answer)

          {:error, reason} ->
            Map.merge(result, %{answer: nil, error: reason})
        end
      else
        Map.put(result, :answer, nil)
      end

    {:ok, result}
  end

  @doc """
  Retrieve relevant context for a query.

  Returns a map with:
    * `:documents` - List of matching documents
    * `:formatted` - Formatted context string
  """
  @spec retrieve_context(t(), String.t()) :: {:ok, map()}
  def retrieve_context(%__MODULE__{} = qa, query) do
    {:ok, documents} = InMemorySearch.search(qa.index, query, limit: qa.max_results)

    {:ok,
     %{
       documents: documents,
       formatted: format_context(documents)
     }}
  end

  @doc """
  Format documents into a context string.
  """
  @spec format_context([map()]) :: String.t()
  def format_context([]) do
    "No relevant code found."
  end

  def format_context(documents) do
    Enum.map_join(documents, "\n", fn doc ->
      path = get_path(doc)
      start_line = doc.metadata[:start_line] || 1
      end_line = doc.metadata[:end_line]

      line_info =
        if end_line do
          "L#{start_line}-#{end_line}"
        else
          "L#{start_line}"
        end

      """
      File: #{path} (#{line_info})
      ```
      #{doc.content}
      ```
      """
    end)
  end

  @doc """
  Build a prompt from context and question.

  ## Options

    * `:template` - Custom template with `<%= context %>` and `<%= question %>` placeholders
    * `:prompt` - Same as `:template` (alias)
  """
  @spec build_prompt(String.t(), String.t(), keyword()) :: String.t()
  def build_prompt(context, question, opts \\ []) do
    template = Keyword.get(opts, :template) || Keyword.get(opts, :prompt, @default_answer_prompt)

    template
    |> String.replace("<%= context %>", context)
    |> String.replace("<%= question %>", question)
  end

  @doc """
  Prepare source information from documents.
  """
  @spec prepare_sources([map()]) :: [map()]
  def prepare_sources(documents) do
    Enum.map(documents, fn doc ->
      %{
        id: doc.id,
        path: get_path(doc),
        start_line: doc.metadata[:start_line],
        end_line: doc.metadata[:end_line],
        type: doc.metadata[:type],
        name: doc.metadata[:name]
      }
    end)
  end

  @doc """
  Enable or disable query enhancement.
  """
  @spec with_query_enhancement(t(), boolean()) :: t()
  def with_query_enhancement(%__MODULE__{} = qa, enabled) do
    %{qa | query_enhancement: enabled}
  end

  @doc """
  Set the LLM module for answer generation.
  """
  @spec with_llm(t(), module()) :: t()
  def with_llm(%__MODULE__{} = qa, llm_module) do
    %{qa | llm_module: llm_module}
  end

  @doc """
  Set the maximum results to retrieve.
  """
  @spec with_max_results(t(), pos_integer()) :: t()
  def with_max_results(%__MODULE__{} = qa, max_results) do
    %{qa | max_results: max_results}
  end

  @doc """
  Get default configuration.
  """
  @spec config() :: map()
  def config do
    @default_config
  end

  # Private functions

  defp get_path(doc) do
    doc.metadata[:relative_path] || doc.metadata[:path] || doc.id
  end

  defp call_llm(llm_module, prompt, opts) do
    messages = [%{role: :user, content: prompt}]
    max_tokens = Keyword.get(opts, :max_tokens, 1000)

    case llm_module.complete(messages, max_tokens: max_tokens) do
      {:ok, %{content: answer}} ->
        {:ok, String.trim(answer)}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
