defmodule PortfolioCoder.Agent.Specialists.DocsAgent do
  @moduledoc """
  Specialist agent for documentation analysis and generation.

  Provides tools for:
  - Finding documented/undocumented modules
  - Analyzing documentation completeness
  - Extracting code examples
  - Generating documentation suggestions
  - Validating documentation quality

  ## Usage

      {:ok, index} = InMemorySearch.new()
      {:ok, graph} = InMemoryGraph.new()
      # ... populate index and graph ...

      agent = DocsAgent.new(index, graph)

      # Check documentation coverage
      {:ok, coverage} = DocsAgent.check_doc_coverage(agent)

      # Analyze specific module
      {:ok, analysis} = DocsAgent.analyze_documentation(agent, "MyApp.Parser")

      # Generate report
      {:ok, report} = DocsAgent.generate_doc_report(agent)
  """

  alias PortfolioCoder.Indexer.InMemorySearch

  defstruct [
    :index,
    :graph,
    :doc_style,
    :include_private,
    :min_doc_length
  ]

  @type t :: %__MODULE__{
          index: pid(),
          graph: pid(),
          doc_style: :ex_doc | :yard | :jsdoc,
          include_private: boolean(),
          min_doc_length: pos_integer()
        }

  @default_config %{
    doc_style: :ex_doc,
    include_private: false,
    min_doc_length: 20
  }

  @doc """
  Create a new docs agent.

  ## Options

    * `:doc_style` - Documentation style (default: :ex_doc)
    * `:include_private` - Include private modules (default: false)
    * `:min_doc_length` - Minimum characters for valid doc (default: 20)
  """
  @spec new(pid(), pid(), keyword()) :: t()
  def new(index, graph, opts \\ []) do
    %__MODULE__{
      index: index,
      graph: graph,
      doc_style: Keyword.get(opts, :doc_style, :ex_doc),
      include_private: Keyword.get(opts, :include_private, false),
      min_doc_length: Keyword.get(opts, :min_doc_length, 20)
    }
  end

  @doc """
  Find modules that have documentation.
  """
  @spec find_documented_modules(t()) :: {:ok, [map()]}
  def find_documented_modules(%__MODULE__{} = agent) do
    {:ok, results} = InMemorySearch.search(agent.index, "@moduledoc", limit: 100)

    modules =
      results
      |> Enum.filter(&has_real_documentation?/1)
      |> Enum.map(&extract_module_info/1)
      |> Enum.uniq_by(& &1.name)

    {:ok, modules}
  end

  @doc """
  Find modules that lack documentation.
  """
  @spec find_undocumented_modules(t()) :: {:ok, [map()]}
  def find_undocumented_modules(%__MODULE__{} = agent) do
    {:ok, results} = InMemorySearch.search(agent.index, "defmodule", limit: 100)

    undocumented =
      results
      |> Enum.filter(fn r ->
        has_defmodule?(r.content) and not has_real_documentation?(r)
      end)
      |> Enum.map(&extract_module_info/1)
      |> Enum.uniq_by(& &1.name)

    {:ok, undocumented}
  end

  @doc """
  Analyze documentation for a specific module.
  """
  @spec analyze_documentation(t(), String.t()) :: {:ok, map()}
  def analyze_documentation(%__MODULE__{} = agent, module_name) do
    {:ok, results} = InMemorySearch.search(agent.index, module_name, limit: 10)

    # Find the module definition
    module_doc =
      Enum.find(results, fn r ->
        String.contains?(r.content, "defmodule #{module_name}")
      end)

    analysis =
      if module_doc do
        content = module_doc.content

        %{
          module: module_name,
          has_moduledoc: has_moduledoc?(content),
          moduledoc_false: has_moduledoc_false?(content),
          has_examples: has_examples?(content),
          has_usage_section: has_section?(content, "Usage"),
          has_options_section: has_section?(content, "Options"),
          example_count: count_examples(content),
          function_docs: count_function_docs(content),
          completeness_score: calculate_completeness(content)
        }
      else
        %{
          module: module_name,
          has_moduledoc: false,
          moduledoc_false: false,
          has_examples: false,
          has_usage_section: false,
          has_options_section: false,
          example_count: 0,
          function_docs: 0,
          completeness_score: 0.0
        }
      end

    {:ok, analysis}
  end

  @doc """
  Extract code examples from module documentation.
  """
  @spec extract_examples(t(), String.t()) :: {:ok, [map()]}
  def extract_examples(%__MODULE__{} = agent, module_name) do
    {:ok, results} = InMemorySearch.search(agent.index, module_name, limit: 10)

    examples =
      results
      |> Enum.flat_map(fn r ->
        extract_code_examples(r.content)
      end)

    {:ok, examples}
  end

  @doc """
  Suggest documentation for undocumented code.
  """
  @spec suggest_documentation(t(), String.t()) :: {:ok, [map()]}
  def suggest_documentation(%__MODULE__{} = agent, module_name) do
    {:ok, analysis} = analyze_documentation(agent, module_name)
    suggestions = build_suggestions(analysis)
    {:ok, suggestions}
  end

  @doc """
  Calculate documentation coverage for the codebase.
  """
  @spec check_doc_coverage(t()) :: {:ok, map()}
  def check_doc_coverage(%__MODULE__{} = agent) do
    {:ok, documented} = find_documented_modules(agent)
    {:ok, undocumented} = find_undocumented_modules(agent)

    total = length(documented) + length(undocumented)

    coverage =
      if total > 0 do
        length(documented) / total * 100
      else
        0.0
      end

    {:ok,
     %{
       total_modules: total,
       documented_modules: length(documented),
       undocumented_modules: length(undocumented),
       coverage_percentage: Float.round(coverage, 1),
       documented: documented,
       undocumented: undocumented
     }}
  end

  @doc """
  Validate documentation quality.
  """
  @spec validate_docs(t()) :: {:ok, [map()]}
  def validate_docs(%__MODULE__{} = agent) do
    {:ok, documented} = find_documented_modules(agent)

    issues =
      documented
      |> Enum.flat_map(fn mod ->
        {:ok, analysis} = analyze_documentation(agent, mod.name)
        validate_module_docs(mod.name, analysis)
      end)

    {:ok, issues}
  end

  @doc """
  Generate a comprehensive documentation report.
  """
  @spec generate_doc_report(t()) :: {:ok, map()}
  def generate_doc_report(%__MODULE__{} = agent) do
    {:ok, coverage} = check_doc_coverage(agent)
    {:ok, issues} = validate_docs(agent)

    module_analyses =
      (coverage.documented ++ coverage.undocumented)
      |> Enum.take(20)
      |> Enum.map(fn mod ->
        {:ok, analysis} = analyze_documentation(agent, mod.name)
        analysis
      end)

    analysis_count = length(module_analyses)

    summary = %{
      total_modules: coverage.total_modules,
      coverage: coverage.coverage_percentage,
      issue_count: length(issues),
      avg_completeness:
        if analysis_count == 0 do
          0.0
        else
          module_analyses
          |> Enum.map(& &1.completeness_score)
          |> Enum.sum()
          |> then(&(&1 / analysis_count))
          |> Float.round(2)
        end
    }

    {:ok,
     %{
       summary: summary,
       coverage: coverage,
       modules: module_analyses,
       issues: issues
     }}
  end

  @doc """
  Get default configuration.
  """
  @spec config() :: map()
  def config do
    @default_config
  end

  # Private functions

  defp has_real_documentation?(result) do
    content = result.content
    has_moduledoc?(content) and not has_moduledoc_false?(content)
  end

  defp has_moduledoc?(content) do
    String.contains?(content, "@moduledoc")
  end

  defp has_moduledoc_false?(content) do
    String.contains?(content, "@moduledoc false")
  end

  defp has_defmodule?(content) do
    String.contains?(content, "defmodule ")
  end

  defp has_examples?(content) do
    # Check for iex examples or code blocks in docs
    String.contains?(content, "iex>") or
      String.contains?(content, "```") or
      Regex.match?(~r/@doc\s+["']{3}[\s\S]*?(?:iex>|```|^\s{4}[a-z])/, content)
  end

  defp has_section?(content, section_name) do
    Regex.match?(~r/##\s+#{section_name}/i, content)
  end

  defp count_examples(content) do
    iex_count = length(Regex.scan(~r/iex>/, content))
    code_block_count = length(Regex.scan(~r/```\w*\n/, content))
    iex_count + code_block_count
  end

  defp count_function_docs(content) do
    length(Regex.scan(~r/@doc\s+["']{3}/, content)) +
      length(Regex.scan(~r/@doc\s+"[^"]+"/, content))
  end

  defp calculate_completeness(content) do
    scores = [
      {has_moduledoc?(content), 30},
      {not has_moduledoc_false?(content), 10},
      {has_examples?(content), 20},
      {has_section?(content, "Usage"), 15},
      {has_section?(content, "Options"), 10},
      {count_function_docs(content) > 0, 15}
    ]

    scores
    |> Enum.filter(fn {condition, _weight} -> condition end)
    |> Enum.map(fn {_, weight} -> weight end)
    |> Enum.sum()
    |> then(&(&1 / 100))
  end

  defp extract_module_info(result) do
    content = result.content

    module_name =
      case Regex.run(~r/defmodule\s+([A-Z][\w.]+)/, content) do
        [_, name] -> name
        _ -> "Unknown"
      end

    %{
      name: module_name,
      path: result.metadata[:path] || result.id,
      has_docs: has_moduledoc?(content) and not has_moduledoc_false?(content)
    }
  end

  defp extract_code_examples(content) do
    # Extract iex examples
    iex_examples =
      Regex.scan(~r/iex>\s*(.+)/, content)
      |> Enum.map(fn [_, code] -> %{type: :iex, code: code} end)

    # Extract code blocks
    code_blocks =
      Regex.scan(~r/```\w*\n([\s\S]*?)```/, content)
      |> Enum.map(fn [_, code] -> %{type: :code_block, code: String.trim(code)} end)

    iex_examples ++ code_blocks
  end

  defp build_suggestions(analysis) do
    suggestions = []

    suggestions =
      if analysis.has_moduledoc do
        suggestions
      else
        [
          %{type: :missing_moduledoc, message: "Add @moduledoc to document this module"}
          | suggestions
        ]
      end

    suggestions =
      if analysis.moduledoc_false do
        [
          %{
            type: :moduledoc_false,
            message: "Consider adding documentation instead of @moduledoc false"
          }
          | suggestions
        ]
      else
        suggestions
      end

    suggestions =
      if analysis.has_examples do
        suggestions
      else
        [%{type: :missing_examples, message: "Add usage examples to help users"} | suggestions]
      end

    suggestions =
      if analysis.has_usage_section do
        suggestions
      else
        [%{type: :missing_usage, message: "Add a ## Usage section"} | suggestions]
      end

    suggestions
  end

  defp validate_module_docs(module_name, analysis) do
    issues = []

    issues =
      if analysis.has_moduledoc and analysis.completeness_score < 0.3 do
        [
          %{
            module: module_name,
            type: :incomplete_docs,
            message:
              "Documentation exists but is incomplete (#{Float.round(analysis.completeness_score * 100, 1)}%)"
          }
          | issues
        ]
      else
        issues
      end

    issues =
      if analysis.has_moduledoc and not analysis.has_examples do
        [
          %{
            module: module_name,
            type: :no_examples,
            message: "Module documentation has no usage examples"
          }
          | issues
        ]
      else
        issues
      end

    issues
  end
end
