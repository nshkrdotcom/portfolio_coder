defmodule PortfolioCoder.Tools.AnalyzeCode do
  @moduledoc """
  Code analysis tool for agents.

  Provides structural analysis of code files including
  function extraction, dependency analysis, and complexity metrics.
  """

  alias PortfolioCoder.Parsers

  @doc """
  Get the tool definition for agent registration.
  """
  @spec definition() :: map()
  def definition do
    %{
      name: "analyze_code",
      description: """
      Analyze code structure and extract information like functions,
      classes, imports, and dependencies.
      """,
      parameters: %{
        type: "object",
        properties: %{
          path: %{
            type: "string",
            description: "Path to file or directory to analyze"
          },
          analysis_type: %{
            type: "string",
            description: "Type of analysis to perform",
            enum: ["structure", "dependencies", "complexity", "all"],
            default: "structure"
          },
          language: %{
            type: "string",
            description: "Programming language (auto-detected if not specified)",
            enum: ["elixir", "python", "javascript", "typescript"]
          }
        },
        required: ["path"]
      },
      handler: &__MODULE__.execute/1
    }
  end

  @doc """
  Execute the analyze_code tool.
  """
  @spec execute(map()) :: {:ok, map()} | {:error, term()}
  def execute(args) do
    path = Map.fetch!(args, "path")
    analysis_type = Map.get(args, "analysis_type", "structure")
    language = Map.get(args, "language")

    with :ok <- validate_path(path) do
      if File.dir?(path) do
        analyze_directory(path, analysis_type, language)
      else
        analyze_file(path, analysis_type, language)
      end
    end
  end

  defp validate_path(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, :path_not_found}
    end
  end

  defp analyze_file(path, analysis_type, language) do
    language_atom = resolve_language(path, language)

    with {:ok, content} <- File.read(path),
         {:ok, analysis} <- run_analysis(content, analysis_type, language_atom) do
      {:ok,
       %{
         path: path,
         language: language_atom,
         analysis_type: analysis_type,
         result: analysis
       }}
    end
  end

  defp resolve_language(path, nil), do: detect_language(path)

  defp resolve_language(_path, language) when is_binary(language),
    do: String.to_existing_atom(language)

  defp resolve_language(_path, language), do: language

  defp run_analysis(content, "structure", lang), do: analyze_structure(content, lang)
  defp run_analysis(content, "dependencies", lang), do: analyze_file_dependencies(content, lang)
  defp run_analysis(content, "complexity", lang), do: analyze_complexity(content, lang)
  defp run_analysis(content, "all", lang), do: analyze_all(content, lang)
  defp run_analysis(_content, _type, _lang), do: {:error, :unknown_analysis_type}

  defp analyze_directory(path, analysis_type, language) do
    files =
      path
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(fn f -> File.regular?(f) and code_file?(f) end)
      |> Enum.take(50)

    results =
      Enum.map(files, fn file ->
        case analyze_file(file, analysis_type, language) do
          {:ok, result} -> result
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    summary = summarize_results(results)

    {:ok,
     %{
       path: path,
       analysis_type: analysis_type,
       files_analyzed: length(results),
       summary: summary,
       files: results
     }}
  end

  defp analyze_structure(content, language) do
    Parsers.parse(content, language)
  end

  defp analyze_file_dependencies(content, :elixir) do
    case Parsers.parse(content, :elixir) do
      {:ok, parsed} ->
        deps = %{
          imports: parsed[:imports] || [],
          aliases: parsed[:aliases] || [],
          uses: parsed[:uses] || []
        }

        {:ok, deps}

      error ->
        error
    end
  end

  defp analyze_file_dependencies(content, :python) do
    case Parsers.parse(content, :python) do
      {:ok, parsed} ->
        deps = %{
          imports: parsed[:imports] || [],
          from_imports: parsed[:from_imports] || []
        }

        {:ok, deps}

      error ->
        error
    end
  end

  defp analyze_file_dependencies(content, language) when language in [:javascript, :typescript] do
    case Parsers.parse(content, language) do
      {:ok, parsed} ->
        deps = %{
          imports: parsed[:imports] || [],
          exports: parsed[:exports] || []
        }

        {:ok, deps}

      error ->
        error
    end
  end

  defp analyze_file_dependencies(_content, language) do
    {:error, {:unsupported_language, language}}
  end

  defp analyze_complexity(content, language) do
    case Parsers.parse(content, language) do
      {:ok, parsed} ->
        {:ok, build_complexity_metrics(content, parsed, language)}

      error ->
        error
    end
  end

  defp build_complexity_metrics(content, parsed, language) do
    functions = parsed[:functions] || []
    classes = parsed[:classes] || parsed[:modules] || []
    lines = String.split(content, "\n")
    line_metrics = calculate_line_metrics(lines, language)

    Map.merge(line_metrics, %{
      function_count: length(functions),
      class_count: length(classes),
      avg_function_length: calculate_avg_function_length(functions, content)
    })
  end

  defp calculate_line_metrics(lines, language) do
    total_lines = length(lines)
    code_lines = Enum.count(lines, &(String.trim(&1) != ""))
    comment_pattern = comment_pattern_for(language)
    comment_lines = Enum.count(lines, &Regex.match?(comment_pattern, &1))

    %{
      total_lines: total_lines,
      code_lines: code_lines,
      comment_lines: comment_lines,
      blank_lines: total_lines - code_lines
    }
  end

  defp comment_pattern_for(:elixir), do: ~r/^\s*#/
  defp comment_pattern_for(:python), do: ~r/^\s*#/

  defp comment_pattern_for(lang) when lang in [:javascript, :typescript],
    do: ~r/^\s*(\/\/|\/\*|\*)/

  defp comment_pattern_for(_), do: ~r/^\s*#/

  defp analyze_all(content, language) do
    with {:ok, structure} <- analyze_structure(content, language),
         {:ok, deps} <- analyze_file_dependencies(content, language),
         {:ok, complexity} <- analyze_complexity(content, language) do
      {:ok,
       %{
         structure: structure,
         dependencies: deps,
         complexity: complexity
       }}
    end
  end

  defp calculate_avg_function_length([], _content), do: 0

  defp calculate_avg_function_length(functions, content) when functions != [] do
    lines = String.split(content, "\n")
    total_lines = length(lines)
    # Estimate function length by dividing code by function count
    div(total_lines, length(functions))
  end

  defp summarize_results(results) do
    %{
      total_files: length(results),
      by_language:
        results
        |> Enum.group_by(& &1.language)
        |> Map.new(fn {lang, files} -> {lang, length(files)} end),
      total_functions:
        results
        |> Enum.map(&get_function_count/1)
        |> Enum.sum(),
      total_classes:
        results
        |> Enum.map(&get_class_count/1)
        |> Enum.sum()
    }
  end

  defp get_function_count(%{result: %{functions: funcs}}) when is_list(funcs), do: length(funcs)

  defp get_function_count(%{result: %{complexity: %{function_count: count}}}), do: count
  defp get_function_count(_), do: 0

  defp get_class_count(%{result: %{classes: classes}}) when is_list(classes), do: length(classes)
  defp get_class_count(%{result: %{modules: mods}}) when is_list(mods), do: length(mods)
  defp get_class_count(%{result: %{complexity: %{class_count: count}}}), do: count
  defp get_class_count(_), do: 0

  defp code_file?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in [".ex", ".exs", ".py", ".js", ".jsx", ".ts", ".tsx", ".mjs"]
  end

  @extension_to_language %{
    ".ex" => :elixir,
    ".exs" => :elixir,
    ".py" => :python,
    ".pyw" => :python,
    ".js" => :javascript,
    ".jsx" => :javascript,
    ".mjs" => :javascript,
    ".ts" => :typescript,
    ".tsx" => :typescript
  }

  defp detect_language(path) do
    ext = Path.extname(path) |> String.downcase()
    Map.get(@extension_to_language, ext, :unknown)
  end
end
