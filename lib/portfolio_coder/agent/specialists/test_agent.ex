defmodule PortfolioCoder.Agent.Specialists.TestAgent do
  @moduledoc """
  Specialist agent for test analysis and coverage.

  Provides tools for:
  - Finding test files and untested modules
  - Analyzing test coverage
  - Extracting test cases
  - Suggesting tests for uncovered code
  - Evaluating test quality

  ## Usage

      {:ok, index} = InMemorySearch.new()
      {:ok, graph} = InMemoryGraph.new()
      # ... populate index and graph ...

      agent = TestAgent.new(index, graph)

      # Find untested modules
      {:ok, untested} = TestAgent.find_untested_modules(agent)

      # Analyze coverage
      {:ok, coverage} = TestAgent.analyze_test_coverage(agent, "MyApp.Parser")

      # Generate report
      {:ok, report} = TestAgent.generate_test_report(agent)
  """

  alias PortfolioCoder.Indexer.InMemorySearch

  defstruct [
    :index,
    :graph,
    :test_framework,
    :test_dir,
    :source_dir
  ]

  @type t :: %__MODULE__{
          index: pid(),
          graph: pid(),
          test_framework: :ex_unit | :rspec | :jest,
          test_dir: String.t(),
          source_dir: String.t()
        }

  @default_config %{
    test_framework: :ex_unit,
    test_dir: "test",
    source_dir: "lib"
  }

  @doc """
  Create a new test agent.

  ## Options

    * `:test_framework` - Test framework (default: :ex_unit)
    * `:test_dir` - Test directory (default: "test")
    * `:source_dir` - Source directory (default: "lib")
  """
  @spec new(pid(), pid(), keyword()) :: t()
  def new(index, graph, opts \\ []) do
    %__MODULE__{
      index: index,
      graph: graph,
      test_framework: Keyword.get(opts, :test_framework, :ex_unit),
      test_dir: Keyword.get(opts, :test_dir, "test"),
      source_dir: Keyword.get(opts, :source_dir, "lib")
    }
  end

  @doc """
  Find all test files.
  """
  @spec find_tests(t()) :: {:ok, [map()]}
  def find_tests(%__MODULE__{} = agent) do
    {:ok, results} = InMemorySearch.search(agent.index, "ExUnit.Case test", limit: 100)

    tests =
      results
      |> Enum.filter(&test_file?/1)
      |> Enum.map(&extract_test_info/1)
      |> Enum.uniq_by(& &1.path)

    {:ok, tests}
  end

  @doc """
  Find modules that don't have corresponding tests.
  """
  @spec find_untested_modules(t()) :: {:ok, [map()]}
  def find_untested_modules(%__MODULE__{} = agent) do
    {:ok, tests} = find_tests(agent)
    test_modules = MapSet.new(Enum.map(tests, & &1.tests_module))

    {:ok, results} = InMemorySearch.search(agent.index, "defmodule", limit: 100)

    untested =
      results
      |> Enum.filter(&source_module?/1)
      |> Enum.map(&extract_module_info/1)
      |> Enum.reject(fn mod ->
        MapSet.member?(test_modules, mod.name) or
          MapSet.member?(test_modules, "#{mod.name}Test")
      end)
      |> Enum.uniq_by(& &1.name)

    {:ok, untested}
  end

  @doc """
  Analyze test coverage for a specific module.
  """
  @spec analyze_test_coverage(t(), String.t()) :: {:ok, map()}
  def analyze_test_coverage(%__MODULE__{} = agent, module_name) do
    # Find tests for this module
    {:ok, related_tests} = find_related_tests(agent, module_name)

    # Count test cases
    test_count =
      related_tests
      |> Enum.map(fn t -> t.test_count end)
      |> Enum.sum()

    # Find module functions
    {:ok, module_results} = InMemorySearch.search(agent.index, module_name, limit: 10)

    module_content =
      module_results
      |> Enum.find(&String.contains?(&1.content, "defmodule #{module_name}"))

    functions =
      if module_content do
        extract_functions(module_content.content)
      else
        []
      end

    # Check which functions are mentioned in tests
    covered_functions =
      case related_tests do
        [] ->
          []

        _ ->
          test_contents = Enum.map_join(related_tests, "\n", & &1.content)

          Enum.filter(functions, fn func ->
            String.contains?(test_contents, func.name)
          end)
      end

    function_count = length(functions)

    coverage_pct =
      if function_count == 0 do
        0.0
      else
        length(covered_functions) / function_count * 100
      end

    {:ok,
     %{
       module: module_name,
       test_count: test_count,
       total_functions: length(functions),
       covered_functions: covered_functions,
       coverage_percentage: Float.round(coverage_pct, 1)
     }}
  end

  @doc """
  Extract test cases from a test file/module.
  """
  @spec extract_test_cases(t(), String.t()) :: {:ok, [map()]}
  def extract_test_cases(%__MODULE__{} = agent, test_module_name) do
    {:ok, results} = InMemorySearch.search(agent.index, test_module_name, limit: 10)

    test_file =
      Enum.find(results, fn r ->
        String.contains?(r.content, "defmodule #{test_module_name}")
      end)

    cases =
      if test_file do
        extract_tests_from_content(test_file.content)
      else
        []
      end

    {:ok, cases}
  end

  @doc """
  Find tests related to a specific module.
  """
  @spec find_related_tests(t(), String.t()) :: {:ok, [map()]}
  def find_related_tests(%__MODULE__{} = agent, module_name) do
    # Search for the module name in test files
    {:ok, results} = InMemorySearch.search(agent.index, module_name, limit: 50)

    related =
      results
      |> Enum.filter(&test_file?/1)
      |> Enum.map(fn r ->
        %{
          path: r.metadata[:path] || r.id,
          test_count: count_tests(r.content),
          content: r.content
        }
      end)

    {:ok, related}
  end

  @doc """
  Suggest tests for untested code.
  """
  @spec suggest_tests(t(), String.t()) :: {:ok, [map()]}
  def suggest_tests(%__MODULE__{} = agent, module_name) do
    {:ok, results} = InMemorySearch.search(agent.index, module_name, limit: 10)

    module_content =
      Enum.find(results, &String.contains?(&1.content, "defmodule #{module_name}"))

    suggestions =
      if module_content do
        functions = extract_functions(module_content.content)

        Enum.map(functions, fn func ->
          %{
            function: func.name,
            arity: func.arity,
            suggestion: "Add test for #{func.name}/#{func.arity}",
            template: generate_test_template(module_name, func)
          }
        end)
      else
        []
      end

    {:ok, suggestions}
  end

  @doc """
  Check test quality metrics.
  """
  @spec check_test_quality(t()) :: {:ok, map()}
  def check_test_quality(%__MODULE__{} = agent) do
    {:ok, tests} = find_tests(agent)

    total_tests = Enum.sum(Enum.map(tests, & &1.test_count))
    describe_blocks = Enum.sum(Enum.map(tests, & &1.describe_count))
    setup_usage = Enum.count(tests, & &1.has_setup)
    test_file_count = length(tests)

    {:ok,
     %{
       total_test_files: test_file_count,
       total_tests: total_tests,
       describe_blocks: describe_blocks,
       tests_with_setup: setup_usage,
       avg_tests_per_file:
         if test_file_count == 0 do
           0.0
         else
           Float.round(total_tests / test_file_count, 1)
         end
     }}
  end

  @doc """
  Generate a comprehensive test coverage report.
  """
  @spec generate_test_report(t()) :: {:ok, map()}
  def generate_test_report(%__MODULE__{} = agent) do
    {:ok, tests} = find_tests(agent)
    {:ok, untested} = find_untested_modules(agent)
    {:ok, quality} = check_test_quality(agent)

    total_modules = length(untested) + length(tests)

    coverage_pct =
      if total_modules > 0 do
        length(tests) / total_modules * 100
      else
        0.0
      end

    {:ok,
     %{
       summary: %{
         total_test_files: length(tests),
         total_tests: quality.total_tests,
         untested_modules: length(untested),
         coverage_percentage: Float.round(coverage_pct, 1)
       },
       quality: quality,
       tests: tests,
       untested: untested
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

  defp test_file?(result) do
    path = result.metadata[:path] || result.id

    String.contains?(path, "test") and
      (String.ends_with?(path, "_test.exs") or
         String.ends_with?(path, "_test.ex") or
         String.ends_with?(path, ".test.js") or
         String.ends_with?(path, "_spec.rb"))
  end

  defp source_module?(result) do
    path = result.metadata[:path] || result.id
    content = result.content

    not test_file?(result) and
      String.contains?(content, "defmodule ") and
      (String.contains?(path, "lib/") or String.contains?(path, "src/"))
  end

  defp extract_test_info(result) do
    content = result.content
    path = result.metadata[:path] || result.id

    module_name =
      case Regex.run(~r/defmodule\s+([A-Z][\w.]+)/, content) do
        [_, name] -> name
        _ -> "Unknown"
      end

    # Derive tested module name
    tests_module = String.replace_suffix(module_name, "Test", "")

    %{
      module: module_name,
      tests_module: tests_module,
      path: path,
      test_count: count_tests(content),
      describe_count: count_describe_blocks(content),
      has_setup: String.contains?(content, "setup")
    }
  end

  defp extract_module_info(result) do
    content = result.content
    path = result.metadata[:path] || result.id

    module_name =
      case Regex.run(~r/defmodule\s+([A-Z][\w.]+)/, content) do
        [_, name] -> name
        _ -> "Unknown"
      end

    %{
      name: module_name,
      path: path
    }
  end

  defp extract_functions(content) do
    # Match def/defp function definitions
    Regex.scan(~r/\bdef(p)?\s+(\w+)\s*\(([^)]*)\)/, content)
    |> Enum.map(fn
      [_, visibility, name, args] ->
        arity = count_args(args)

        %{
          name: name,
          arity: arity,
          visibility: if(visibility == "p", do: :private, else: :public)
        }
    end)
    |> Enum.uniq_by(&{&1.name, &1.arity})
  end

  defp count_args(""), do: 0

  defp count_args(args) do
    args
    |> String.split(",")
    |> Enum.count()
  end

  defp count_tests(content) do
    length(Regex.scan(~r/\btest\s+"[^"]+"\s+do/, content))
  end

  defp count_describe_blocks(content) do
    length(Regex.scan(~r/\bdescribe\s+"[^"]+"\s+do/, content))
  end

  defp extract_tests_from_content(content) do
    Regex.scan(~r/test\s+"([^"]+)"\s+do/, content)
    |> Enum.map(fn [_, name] ->
      %{
        name: name,
        type: :test
      }
    end)
  end

  defp generate_test_template(module_name, func) do
    """
    test "#{func.name}/#{func.arity} returns expected result" do
      result = #{module_name}.#{func.name}(#{generate_args(func.arity)})
      assert result == :expected
    end
    """
  end

  defp generate_args(0), do: ""

  defp generate_args(arity) do
    1..arity
    |> Enum.map_join(", ", fn n -> "arg#{n}" end)
  end
end
