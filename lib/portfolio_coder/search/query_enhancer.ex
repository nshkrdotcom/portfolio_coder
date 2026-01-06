defmodule PortfolioCoder.Search.QueryEnhancer do
  @moduledoc """
  Improve search queries for better code retrieval.

  This module wraps the portfolio_index query processing adapters to provide
  a unified interface for query enhancement in code search scenarios.

  ## Features

  - **Rewriting**: Clean conversational input into focused search queries
  - **Expansion**: Add synonyms and related terms for better recall
  - **Decomposition**: Break complex questions into simpler sub-queries

  ## Usage

      # Full enhancement pipeline
      {:ok, enhanced} = QueryEnhancer.enhance("Hey, how do we handle user login?")
      enhanced.rewritten
      # => "user login authentication handler"
      enhanced.expanded
      # => "user login authentication handler sign-in session auth"
      enhanced.sub_queries
      # => ["user authentication implementation", "login session management"]

      # Individual operations
      {:ok, result} = QueryEnhancer.rewrite("Can you help me find the auth code?")
      {:ok, result} = QueryEnhancer.expand("GenServer state")
      {:ok, result} = QueryEnhancer.decompose("Compare Elixir and Go for web services")

  ## Configuration

  Uses LLM adapters from portfolio_index. Set the `:context` option to specify
  which LLM adapter to use:

      opts = [context: %{adapters: %{llm: PortfolioIndex.Adapters.LLM.Gemini}}]
      {:ok, result} = QueryEnhancer.enhance(query, opts)

  Without explicit context, defaults to Gemini LLM.
  """

  alias PortfolioIndex.Adapters.QueryRewriter
  alias PortfolioIndex.Adapters.QueryExpander
  alias PortfolioIndex.Adapters.QueryDecomposer

  @type enhanced_query :: %{
          original: String.t(),
          rewritten: String.t(),
          expanded: String.t(),
          sub_queries: [String.t()],
          is_complex: boolean(),
          changes: [String.t()],
          added_terms: [String.t()]
        }

  @type rewrite_result :: %{
          original: String.t(),
          rewritten: String.t(),
          changes_made: [String.t()]
        }

  @type expansion_result :: %{
          original: String.t(),
          expanded: String.t(),
          added_terms: [String.t()]
        }

  @type decomposition_result :: %{
          original: String.t(),
          sub_questions: [String.t()],
          is_complex: boolean()
        }

  @doc """
  Run the full query enhancement pipeline.

  This applies rewriting, expansion, and decomposition in sequence to
  produce an optimized query for code search.

  ## Options

    - `:context` - Adapter context for LLM selection
    - `:skip_rewrite` - Skip the rewriting step (default: false)
    - `:skip_expand` - Skip the expansion step (default: false)
    - `:skip_decompose` - Skip the decomposition step (default: false)

  ## Examples

      {:ok, result} = QueryEnhancer.enhance("Hey, how does Phoenix LiveView work?")
      result.rewritten   # => "how Phoenix LiveView works"
      result.expanded    # => "how Phoenix LiveView real-time websocket works"
      result.sub_queries # => ["how Phoenix LiveView works"]
  """
  @spec enhance(String.t(), keyword()) :: {:ok, enhanced_query()} | {:error, term()}
  def enhance(query, opts \\ []) do
    skip_rewrite = Keyword.get(opts, :skip_rewrite, false)
    skip_expand = Keyword.get(opts, :skip_expand, false)
    skip_decompose = Keyword.get(opts, :skip_decompose, false)

    with {:ok, rewritten} <- maybe_rewrite(query, skip_rewrite, opts),
         {:ok, expanded} <- maybe_expand(rewritten.rewritten, skip_expand, opts),
         {:ok, decomposed} <- maybe_decompose(rewritten.rewritten, skip_decompose, opts) do
      {:ok,
       %{
         original: query,
         rewritten: rewritten.rewritten,
         expanded: expanded.expanded,
         sub_queries: decomposed.sub_questions,
         is_complex: decomposed.is_complex,
         changes: rewritten.changes_made,
         added_terms: expanded.added_terms
       }}
    end
  end

  @doc """
  Rewrite a conversational query into a focused search query.

  Removes greetings, filler words, and politeness markers while
  preserving technical terms and the core question.

  ## Examples

      {:ok, result} = QueryEnhancer.rewrite("Hey, can you help me find the auth code?")
      result.rewritten  # => "find auth code"
      result.changes_made  # => ["removed greeting", "removed politeness markers"]
  """
  @spec rewrite(String.t(), keyword()) :: {:ok, rewrite_result()} | {:error, term()}
  def rewrite(query, opts \\ []) do
    QueryRewriter.LLM.rewrite(query, opts)
  end

  @doc """
  Expand a query with synonyms and related terms.

  Adds alternative phrasings, expands abbreviations, and includes
  related technical terms to improve search recall.

  ## Examples

      {:ok, result} = QueryEnhancer.expand("GenServer state")
      result.expanded    # => "GenServer gen_server OTP server state management Elixir"
      result.added_terms # => ["gen_server", "OTP", "server", "management", "Elixir"]
  """
  @spec expand(String.t(), keyword()) :: {:ok, expansion_result()} | {:error, term()}
  def expand(query, opts \\ []) do
    QueryExpander.LLM.expand(query, opts)
  end

  @doc """
  Decompose a complex query into simpler sub-queries.

  Identifies comparison questions, multi-part questions, and questions
  requiring multi-hop reasoning, breaking them into independent sub-queries.

  ## Examples

      {:ok, result} = QueryEnhancer.decompose("Compare Elixir and Go for web services")
      result.sub_questions
      # => ["What are Elixir's web service features?",
      #     "What are Go's web service features?",
      #     "How do they compare for web services?"]
      result.is_complex  # => true

      {:ok, result} = QueryEnhancer.decompose("What is pattern matching?")
      result.sub_questions  # => ["What is pattern matching?"]
      result.is_complex     # => false
  """
  @spec decompose(String.t(), keyword()) :: {:ok, decomposition_result()} | {:error, term()}
  def decompose(query, opts \\ []) do
    QueryDecomposer.LLM.decompose(query, opts)
  end

  @doc """
  Rewrite a query specifically for code search.

  This is a specialized rewrite that focuses on transforming natural
  language questions into code-relevant search terms.

  ## Examples

      rewritten = QueryEnhancer.rewrite_for_code("how do we handle user login?")
      # => "user login authentication handler"
  """
  @spec rewrite_for_code(String.t(), keyword()) :: String.t()
  def rewrite_for_code(query, opts \\ []) do
    custom_prompt = fn q ->
      """
      Transform this natural language question into code search terms.
      Focus on function names, module names, and technical terms.
      Return only the search terms, nothing else.

      Question: "#{q}"
      """
    end

    case QueryRewriter.LLM.rewrite(query, Keyword.put(opts, :prompt, custom_prompt)) do
      {:ok, %{rewritten: rewritten}} -> rewritten
      {:error, _} -> query
    end
  end

  @doc """
  Expand a query with code-specific synonyms.

  Adds programming-specific synonyms, framework terms, and common
  abbreviation expansions relevant to code search.

  ## Examples

      expanded = QueryEnhancer.expand_with_code_terms("auth middleware")
      # => "auth authentication middleware plug pipeline authorization"
  """
  @spec expand_with_code_terms(String.t(), keyword()) :: String.t()
  def expand_with_code_terms(query, opts \\ []) do
    custom_prompt = fn q ->
      """
      Expand this code search query with programming-related synonyms and terms.
      Include:
      - Abbreviation expansions (auth -> authentication)
      - Framework-specific terms (middleware -> plug for Elixir)
      - Common alternative names

      Return the expanded query string only.

      Query: "#{q}"
      """
    end

    case QueryExpander.LLM.expand(query, Keyword.put(opts, :prompt, custom_prompt)) do
      {:ok, %{expanded: expanded}} -> expanded
      {:error, _} -> query
    end
  end

  # Private helpers

  defp maybe_rewrite(query, true, _opts) do
    {:ok,
     %{
       original: query,
       rewritten: query,
       changes_made: []
     }}
  end

  defp maybe_rewrite(query, false, opts) do
    case rewrite(query, opts) do
      {:ok, result} -> {:ok, result}
      {:error, _} -> {:ok, %{original: query, rewritten: query, changes_made: []}}
    end
  end

  defp maybe_expand(query, true, _opts) do
    {:ok,
     %{
       original: query,
       expanded: query,
       added_terms: []
     }}
  end

  defp maybe_expand(query, false, opts) do
    case expand(query, opts) do
      {:ok, result} -> {:ok, result}
      {:error, _} -> {:ok, %{original: query, expanded: query, added_terms: []}}
    end
  end

  defp maybe_decompose(query, true, _opts) do
    {:ok,
     %{
       original: query,
       sub_questions: [query],
       is_complex: false
     }}
  end

  defp maybe_decompose(query, false, opts) do
    case decompose(query, opts) do
      {:ok, result} -> {:ok, result}
      {:error, _} -> {:ok, %{original: query, sub_questions: [query], is_complex: false}}
    end
  end
end
