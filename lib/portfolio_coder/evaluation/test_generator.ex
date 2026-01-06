defmodule PortfolioCoder.Evaluation.TestGenerator do
  @moduledoc """
  Generate evaluation test cases for RAG systems.

  Creates question-context-answer triples for evaluating:
  - Retrieval quality (are the right documents retrieved?)
  - Answer quality (are answers correct and grounded?)
  - System robustness (edge cases and adversarial inputs)

  ## Usage

      # Generate from code
      {:ok, test_cases} = TestGenerator.from_code(code_content, language: :elixir)

      # Generate from documentation
      {:ok, test_cases} = TestGenerator.from_docs(markdown_content)

      # Generate adversarial cases
      {:ok, test_cases} = TestGenerator.adversarial(base_cases)

      # Export for golden dataset
      TestGenerator.export(test_cases, "test_data.json")
  """

  alias PortfolioCoder.Indexer.Parser

  @type test_case :: %{
          question: String.t(),
          context: String.t(),
          expected_answer: String.t(),
          metadata: map()
        }

  @doc """
  Generate test cases from source code.

  Analyzes code to create questions about:
  - Function behavior
  - Module structure
  - Dependencies and calls
  """
  @spec from_code(String.t(), keyword()) :: {:ok, [test_case()]} | {:error, String.t()}
  def from_code(code, opts \\ []) do
    language = Keyword.get(opts, :language, :elixir)
    max_cases = Keyword.get(opts, :max_cases, 10)

    case Parser.parse_string(code, language) do
      {:ok, result} ->
        test_cases = generate_code_questions(result, code, language)
        {:ok, Enum.take(test_cases, max_cases)}

      {:error, reason} ->
        {:error, "Failed to parse code: #{inspect(reason)}"}
    end
  end

  @doc """
  Generate test cases from markdown documentation.

  Creates questions from:
  - Headers as topics
  - Code blocks as context
  - Prose as answers
  """
  @spec from_docs(String.t(), keyword()) :: {:ok, [test_case()]}
  def from_docs(markdown, opts \\ []) do
    max_cases = Keyword.get(opts, :max_cases, 10)

    test_cases = generate_doc_questions(markdown)
    {:ok, Enum.take(test_cases, max_cases)}
  end

  @doc """
  Generate adversarial test cases from base cases.

  Creates variations to test robustness:
  - Paraphrased questions
  - Irrelevant context injection
  - Misleading similar content
  """
  @spec adversarial([test_case()], keyword()) :: {:ok, [test_case()]}
  def adversarial(base_cases, opts \\ []) do
    include_types = Keyword.get(opts, :types, [:paraphrase, :irrelevant, :misleading])

    adversarial_cases =
      base_cases
      |> Enum.flat_map(fn case ->
        generate_adversarial_variants(case, include_types)
      end)

    {:ok, adversarial_cases}
  end

  @doc """
  Generate edge case tests for boundary conditions.
  """
  @spec edge_cases(keyword()) :: {:ok, [test_case()]}
  def edge_cases(opts \\ []) do
    count = Keyword.get(opts, :count, 10)

    cases = [
      # Empty inputs
      %{
        question: "",
        context: "Some context about functions",
        expected_answer: "",
        metadata: %{type: :edge_case, subtype: :empty_question}
      },
      %{
        question: "What does this do?",
        context: "",
        expected_answer: "Unable to answer without context",
        metadata: %{type: :edge_case, subtype: :empty_context}
      },
      # Very long inputs
      %{
        question: "What is the purpose of this module?",
        context: String.duplicate("def func#{:rand.uniform(1000)}, do: :ok\n", 100),
        expected_answer: "The module contains multiple function definitions",
        metadata: %{type: :edge_case, subtype: :long_context}
      },
      # Special characters
      %{
        question: "What does `@spec` mean?",
        context: "@spec add(integer(), integer()) :: integer()",
        expected_answer: "@spec defines type specifications for functions",
        metadata: %{type: :edge_case, subtype: :special_chars}
      },
      # Multi-language
      %{
        question: "What language is this code?",
        context: "def add(a, b):\n    return a + b",
        expected_answer: "This is Python code",
        metadata: %{type: :edge_case, subtype: :language_detection}
      },
      # Ambiguous
      %{
        question: "What does foo do?",
        context: "def foo, do: :bar\ndef foo(x), do: x",
        expected_answer: "There are multiple foo functions with different arities",
        metadata: %{type: :edge_case, subtype: :ambiguous}
      },
      # Non-code context
      %{
        question: "How do I install dependencies?",
        context: "Run `mix deps.get` in the project directory",
        expected_answer: "Run mix deps.get to install dependencies",
        metadata: %{type: :edge_case, subtype: :non_code}
      },
      # Multiple files context
      %{
        question: "How are User and Account related?",
        context: """
        # File: user.ex
        defmodule User do
          has_one :account
        end

        # File: account.ex
        defmodule Account do
          belongs_to :user
        end
        """,
        expected_answer: "User has one Account, and Account belongs to User",
        metadata: %{type: :edge_case, subtype: :multi_file}
      },
      # Error handling questions
      %{
        question: "What happens if the file doesn't exist?",
        context: "def read(path), do: File.read!(path)",
        expected_answer: "File.read! raises an error if the file doesn't exist",
        metadata: %{type: :edge_case, subtype: :error_handling}
      },
      # Meta questions
      %{
        question: "Is this code well-documented?",
        context: "defmodule Foo do\n  def bar, do: :baz\nend",
        expected_answer: "No, the code lacks documentation",
        metadata: %{type: :edge_case, subtype: :meta_question}
      }
    ]

    {:ok, Enum.take(cases, count)}
  end

  @doc """
  Export test cases to JSON file.
  """
  @spec export([test_case()], String.t()) :: :ok | {:error, String.t()}
  def export(test_cases, path) do
    json = Jason.encode!(test_cases, pretty: true)

    case File.write(path, json) do
      :ok -> :ok
      {:error, reason} -> {:error, "Failed to write: #{reason}"}
    end
  end

  @doc """
  Import test cases from JSON file.
  """
  @spec import(String.t()) :: {:ok, [test_case()]} | {:error, String.t()}
  def import(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content, keys: :atoms) do
          {:ok, cases} -> {:ok, cases}
          {:error, reason} -> {:error, "Invalid JSON: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to read: #{reason}"}
    end
  end

  @doc """
  Generate a golden dataset combining all generation methods.
  """
  @spec golden_dataset(String.t(), keyword()) :: {:ok, [test_case()]}
  def golden_dataset(code_content, opts \\ []) do
    language = Keyword.get(opts, :language, :elixir)

    with {:ok, code_cases} <- from_code(code_content, language: language, max_cases: 5),
         {:ok, edge} <- edge_cases(count: 5),
         {:ok, adversarial} <- adversarial(code_cases, types: [:irrelevant]) do
      all_cases =
        (code_cases ++ edge ++ adversarial)
        |> Enum.with_index()
        |> Enum.map(fn {case, idx} -> Map.put(case, :id, idx + 1) end)

      {:ok, all_cases}
    end
  end

  # Private helpers

  defp generate_code_questions(result, code, language) do
    symbols = result.symbols

    modules = Enum.filter(symbols, &(&1.type == :module))
    functions = Enum.filter(symbols, &(&1.type == :function))

    module_questions =
      Enum.map(modules, fn mod ->
        %{
          question: "What is the purpose of the #{mod.name} module?",
          context: extract_module_code(code, mod.name),
          expected_answer: "Module #{mod.name} #{describe_module(mod)}",
          metadata: %{type: :module, language: language, name: mod.name}
        }
      end)

    function_questions =
      Enum.map(functions, fn func ->
        # Extract name and arity from the symbol name (e.g., "add/2")
        {name, arity} = parse_function_name(func.name)

        %{
          question: "What does the #{func.name} function do?",
          context: code,
          expected_answer: "The #{name} function #{describe_function(func)}",
          metadata: %{type: :function, language: language, name: name, arity: arity}
        }
      end)

    module_questions ++ function_questions
  end

  defp parse_function_name(full_name) do
    case String.split(full_name, "/") do
      [name, arity] -> {name, String.to_integer(arity)}
      [name] -> {name, 0}
    end
  end

  defp generate_doc_questions(markdown) do
    sections = String.split(markdown, ~r/^##?\s+/m, trim: true)

    sections
    |> Enum.flat_map(fn section ->
      lines = String.split(section, "\n", trim: true)
      header = List.first(lines) || ""
      content = Enum.join(Enum.drop(lines, 1), "\n")

      if String.length(content) > 50 do
        [
          %{
            question: "What is #{String.trim(header)}?",
            context: content,
            expected_answer: summarize_section(content),
            metadata: %{type: :documentation, section: header}
          }
        ]
      else
        []
      end
    end)
  end

  defp generate_adversarial_variants(base_case, types) do
    variants = []

    variants =
      if :paraphrase in types do
        [
          %{
            base_case
            | question: paraphrase_question(base_case.question),
              metadata: Map.put(base_case.metadata, :adversarial, :paraphrase)
          }
          | variants
        ]
      else
        variants
      end

    variants =
      if :irrelevant in types do
        [
          %{
            base_case
            | context: base_case.context <> "\n\n# Unrelated code\ndef foo, do: :bar",
              metadata: Map.put(base_case.metadata, :adversarial, :irrelevant_context)
          }
          | variants
        ]
      else
        variants
      end

    variants =
      if :misleading in types do
        [
          %{
            base_case
            | context: inject_misleading_content(base_case.context),
              metadata: Map.put(base_case.metadata, :adversarial, :misleading)
          }
          | variants
        ]
      else
        variants
      end

    variants
  end

  defp extract_module_code(code, module_name) do
    # Simple extraction - find defmodule block
    case Regex.run(~r/defmodule #{module_name}.*?(?=defmodule|\z)/s, code) do
      [match] -> String.slice(match, 0, 500)
      nil -> code |> String.slice(0, 500)
    end
  end

  defp describe_module(_mod), do: "provides functionality"
  defp describe_function(_func), do: "performs an operation"

  defp summarize_section(content) do
    content
    |> String.split("\n")
    |> Enum.take(2)
    |> Enum.join(" ")
    |> String.slice(0, 200)
  end

  defp paraphrase_question(question) do
    replacements = [
      {"What does", "Can you explain what"},
      {"How do I", "What's the way to"},
      {"What is", "Please describe"},
      {"does the", "is the purpose of the"}
    ]

    Enum.reduce(replacements, question, fn {from, to}, q ->
      if String.contains?(q, from), do: String.replace(q, from, to), else: q
    end)
  end

  defp inject_misleading_content(context) do
    misleading = """
    # Note: The above code is deprecated.
    # Consider using the new API instead.
    """

    context <> "\n\n" <> misleading
  end
end
