defmodule PortfolioCoder.QA.GraphAware do
  @moduledoc """
  Graph-augmented Q&A that combines search with code relationship context.

  Enhances traditional RAG by adding information about code relationships:
  imports, function calls, dependencies, and module structure.

  ## Usage

      {:ok, index} = InMemorySearch.new()
      {:ok, graph} = InMemoryGraph.new()
      # ... add documents and build graph ...

      qa = GraphAware.new(index, graph)
      {:ok, result} = GraphAware.ask(qa, "What modules does Parser depend on?")

      IO.puts("Code Context:")
      IO.puts(result.code_context)
      IO.puts("Graph Context:")
      IO.puts(result.graph_context)
  """

  alias PortfolioCoder.Graph.InMemoryGraph
  alias PortfolioCoder.Indexer.InMemorySearch

  defstruct [
    :index,
    :graph,
    :llm_module,
    :max_results,
    :max_graph_depth,
    :include_callees,
    :include_callers,
    :answer_prompt
  ]

  @type t :: %__MODULE__{
          index: pid(),
          graph: pid(),
          llm_module: module() | nil,
          max_results: pos_integer(),
          max_graph_depth: pos_integer(),
          include_callees: boolean(),
          include_callers: boolean(),
          answer_prompt: String.t()
        }

  @default_answer_prompt """
  You are a helpful code assistant. Answer the user's question using both the code snippets and the relationship context.

  Code Context:
  <%= code_context %>

  Relationship Context:
  <%= graph_context %>

  Question: <%= question %>

  Answer:
  """

  @default_config %{
    max_results: 5,
    max_graph_depth: 2,
    include_callees: true,
    include_callers: true
  }

  @doc """
  Create a new graph-aware QA instance.

  ## Options

    * `:max_results` - Maximum search results (default: 5)
    * `:max_graph_depth` - Depth for graph traversal (default: 2)
    * `:include_callees` - Include called functions (default: true)
    * `:include_callers` - Include calling functions (default: true)
    * `:llm_module` - LLM module for answer generation
  """
  @spec new(pid(), pid(), keyword()) :: t()
  def new(index, graph, opts \\ []) do
    %__MODULE__{
      index: index,
      graph: graph,
      llm_module: Keyword.get(opts, :llm_module),
      max_results: Keyword.get(opts, :max_results, 5),
      max_graph_depth: Keyword.get(opts, :max_graph_depth, 2),
      include_callees: Keyword.get(opts, :include_callees, true),
      include_callers: Keyword.get(opts, :include_callers, true),
      answer_prompt: Keyword.get(opts, :answer_prompt, @default_answer_prompt)
    }
  end

  @doc """
  Ask a question with graph-augmented context.

  Returns a result with:
    * `:question` - Original question
    * `:code_context` - Retrieved code snippets
    * `:graph_context` - Related module/function information
    * `:sources` - Source documents
    * `:answer` - Generated answer (if LLM configured)
  """
  @spec ask(t(), String.t(), keyword()) :: {:ok, map()}
  def ask(%__MODULE__{} = qa, question, opts \\ []) do
    # Step 1: Retrieve code context
    {:ok, search_results} = InMemorySearch.search(qa.index, question, limit: qa.max_results)

    code_context = format_code_context(search_results)

    # Step 2: Build graph context
    graph_context = build_graph_context(qa.graph, search_results, question)

    result = %{
      question: question,
      code_context: code_context,
      graph_context: graph_context,
      sources: prepare_sources(search_results)
    }

    # Step 3: Generate answer if LLM configured
    result =
      if qa.llm_module do
        prompt =
          qa.answer_prompt
          |> String.replace("<%= code_context %>", code_context)
          |> String.replace("<%= graph_context %>", graph_context)
          |> String.replace("<%= question %>", question)

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
  Build graph context from search results and question.
  """
  @spec build_graph_context(pid(), [map()], String.t()) :: String.t()
  def build_graph_context(graph, search_results, question) do
    # Extract modules from search results
    modules_from_results = extract_modules_from_results(search_results)

    # Extract modules mentioned in question
    modules_from_question = extract_modules_from_question(graph, question)

    target_modules = Enum.uniq(modules_from_results ++ modules_from_question)

    if Enum.empty?(target_modules) do
      "No specific module relationships found."
    else
      Enum.map_join(target_modules, "\n\n", fn mod_id ->
        context = get_module_context(graph, mod_id)
        format_module_context(mod_id, context)
      end)
    end
  end

  @doc """
  Extract module names from search results.
  """
  @spec extract_modules_from_results([map()]) :: [String.t()]
  def extract_modules_from_results(results) do
    results
    |> Enum.flat_map(fn r ->
      content = r.content

      Regex.scan(~r/defmodule\s+([A-Z][\w.]+)/, content)
      |> Enum.map(fn [_, name] -> name end)
    end)
    |> Enum.uniq()
  end

  @doc """
  Extract modules mentioned in the question by matching against graph.
  """
  @spec extract_modules_from_question(pid(), String.t()) :: [String.t()]
  def extract_modules_from_question(graph, question) do
    {:ok, modules} = InMemoryGraph.nodes_by_type(graph, :module)
    question_lower = String.downcase(question)

    modules
    |> Enum.filter(fn m ->
      short_name = m.name |> String.split(".") |> List.last()
      String.contains?(question_lower, String.downcase(short_name))
    end)
    |> Enum.map(& &1.id)
  end

  @doc """
  Get imports and functions for a module from the graph.
  """
  @spec get_module_context(pid(), String.t()) :: map()
  def get_module_context(graph, module_id) do
    {:ok, imports} = InMemoryGraph.imports_of(graph, module_id)
    {:ok, functions} = InMemoryGraph.functions_of(graph, module_id)

    %{
      imports: imports,
      functions: functions
    }
  end

  @doc """
  Format module context as a readable string.
  """
  @spec format_module_context(String.t(), map()) :: String.t()
  def format_module_context(module_id, context) do
    import_str =
      if Enum.empty?(context.imports) do
        "none"
      else
        context.imports |> Enum.take(5) |> Enum.join(", ")
      end

    function_str =
      if Enum.empty?(context.functions) do
        "none"
      else
        context.functions
        |> Enum.take(5)
        |> Enum.map_join(", ", &(&1 |> String.split("/") |> hd()))
      end

    "Module #{module_id}:\n  - Imports: #{import_str}\n  - Functions: #{function_str}"
  end

  @doc """
  Set graph traversal depth.
  """
  @spec with_graph_depth(t(), pos_integer()) :: t()
  def with_graph_depth(%__MODULE__{} = qa, depth) do
    %{qa | max_graph_depth: depth}
  end

  @doc """
  Enable/disable callee inclusion.
  """
  @spec with_callees(t(), boolean()) :: t()
  def with_callees(%__MODULE__{} = qa, include) do
    %{qa | include_callees: include}
  end

  @doc """
  Enable/disable caller inclusion.
  """
  @spec with_callers(t(), boolean()) :: t()
  def with_callers(%__MODULE__{} = qa, include) do
    %{qa | include_callers: include}
  end

  @doc """
  Set LLM module.
  """
  @spec with_llm(t(), module()) :: t()
  def with_llm(%__MODULE__{} = qa, llm_module) do
    %{qa | llm_module: llm_module}
  end

  @doc """
  Get default configuration.
  """
  @spec config() :: map()
  def config do
    @default_config
  end

  # Private functions

  defp format_code_context([]) do
    "No relevant code found."
  end

  defp format_code_context(results) do
    Enum.map_join(results, "\n---\n", fn r ->
      path = r.metadata[:path] || r.id
      start_line = r.metadata[:start_line] || 1

      """
      File: #{Path.basename(path)}:#{start_line}
      #{r.content}
      """
    end)
  end

  defp prepare_sources(results) do
    Enum.map(results, fn r ->
      %{
        id: r.id,
        path: r.metadata[:path] || r.id
      }
    end)
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
