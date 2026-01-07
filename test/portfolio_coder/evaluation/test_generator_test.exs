defmodule PortfolioCoder.Evaluation.TestGeneratorTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Evaluation.TestGenerator

  @sample_code """
  defmodule Calculator do
    @moduledoc "A simple calculator module"

    def add(a, b), do: a + b
    def subtract(a, b), do: a - b
    defp validate(x), do: is_number(x)
  end
  """

  @sample_markdown """
  # Getting Started

  This guide shows how to use the calculator module.

  ## Installation

  Add the dependency to your mix.exs file:

  ```elixir
  {:calculator, "~> 1.0"}
  ```

  Then run `mix deps.get` to install.

  ## Usage

  The calculator provides basic arithmetic operations.

  ```elixir
  Calculator.add(1, 2)
  # => 3
  ```
  """

  describe "from_code/2" do
    test "generates test cases from Elixir code" do
      {:ok, test_cases} = TestGenerator.from_code(@sample_code, language: :elixir)

      assert test_cases != []
      assert Enum.all?(test_cases, &Map.has_key?(&1, :question))
      assert Enum.all?(test_cases, &Map.has_key?(&1, :context))
      assert Enum.all?(test_cases, &Map.has_key?(&1, :expected_answer))
    end

    test "respects max_cases option" do
      {:ok, test_cases} = TestGenerator.from_code(@sample_code, max_cases: 2)

      assert length(test_cases) <= 2
    end

    test "includes metadata about source" do
      {:ok, test_cases} = TestGenerator.from_code(@sample_code, language: :elixir)

      assert Enum.all?(test_cases, &Map.has_key?(&1, :metadata))
      assert Enum.any?(test_cases, &(&1.metadata.type in [:module, :function]))
    end

    test "generates module questions" do
      {:ok, test_cases} = TestGenerator.from_code(@sample_code)

      module_cases = Enum.filter(test_cases, &(&1.metadata.type == :module))
      assert module_cases != []

      calc_case = Enum.find(module_cases, &String.contains?(&1.question, "Calculator"))
      assert calc_case != nil
    end

    test "generates function questions" do
      {:ok, test_cases} = TestGenerator.from_code(@sample_code)

      function_cases = Enum.filter(test_cases, &(&1.metadata.type == :function))
      assert function_cases != []
    end
  end

  describe "from_docs/2" do
    test "generates test cases from markdown" do
      {:ok, test_cases} = TestGenerator.from_docs(@sample_markdown)

      assert test_cases != []
      assert Enum.all?(test_cases, &(&1.metadata.type == :documentation))
    end

    test "respects max_cases option" do
      {:ok, test_cases} = TestGenerator.from_docs(@sample_markdown, max_cases: 1)

      assert length(test_cases) <= 1
    end

    test "extracts sections from headers" do
      {:ok, test_cases} = TestGenerator.from_docs(@sample_markdown)

      sections = Enum.map(test_cases, & &1.metadata.section)

      assert Enum.any?(sections, &String.contains?(&1, "Installation")) or
               Enum.any?(sections, &String.contains?(&1, "Usage"))
    end
  end

  describe "adversarial/2" do
    test "generates adversarial variants" do
      base_cases = [
        %{
          question: "What does add do?",
          context: "def add(a, b), do: a + b",
          expected_answer: "Adds two numbers",
          metadata: %{type: :function}
        }
      ]

      {:ok, adversarial_cases} = TestGenerator.adversarial(base_cases)

      assert adversarial_cases != []
    end

    test "generates paraphrased questions" do
      base_cases = [
        %{
          question: "What does add do?",
          context: "def add(a, b), do: a + b",
          expected_answer: "Adds two numbers",
          metadata: %{type: :function}
        }
      ]

      {:ok, adversarial_cases} = TestGenerator.adversarial(base_cases, types: [:paraphrase])

      paraphrased = Enum.find(adversarial_cases, &(&1.metadata.adversarial == :paraphrase))
      assert paraphrased != nil
      assert paraphrased.question != "What does add do?"
    end

    test "injects irrelevant context" do
      base_cases = [
        %{
          question: "What does add do?",
          context: "def add(a, b), do: a + b",
          expected_answer: "Adds two numbers",
          metadata: %{type: :function}
        }
      ]

      {:ok, adversarial_cases} = TestGenerator.adversarial(base_cases, types: [:irrelevant])

      irrelevant = Enum.find(adversarial_cases, &(&1.metadata.adversarial == :irrelevant_context))
      assert irrelevant != nil
      assert String.contains?(irrelevant.context, "foo")
    end

    test "generates misleading variants" do
      base_cases = [
        %{
          question: "How do I use add?",
          context: "def add(a, b), do: a + b",
          expected_answer: "Call add with two arguments",
          metadata: %{type: :function}
        }
      ]

      {:ok, adversarial_cases} = TestGenerator.adversarial(base_cases, types: [:misleading])

      misleading = Enum.find(adversarial_cases, &(&1.metadata.adversarial == :misleading))
      assert misleading != nil
      assert String.contains?(misleading.context, "deprecated")
    end
  end

  describe "edge_cases/1" do
    test "generates edge case test cases" do
      {:ok, edge_cases} = TestGenerator.edge_cases()

      assert edge_cases != []
      assert Enum.all?(edge_cases, &(&1.metadata.type == :edge_case))
    end

    test "respects count option" do
      {:ok, edge_cases} = TestGenerator.edge_cases(count: 3)

      assert length(edge_cases) <= 3
    end

    test "includes empty input cases" do
      {:ok, edge_cases} = TestGenerator.edge_cases()

      empty_question = Enum.find(edge_cases, &(&1.metadata.subtype == :empty_question))
      empty_context = Enum.find(edge_cases, &(&1.metadata.subtype == :empty_context))

      assert empty_question != nil
      assert empty_context != nil
    end

    test "includes various edge case types" do
      {:ok, edge_cases} = TestGenerator.edge_cases(count: 10)

      subtypes = Enum.map(edge_cases, & &1.metadata.subtype)

      assert :empty_question in subtypes
      assert :empty_context in subtypes
      assert :special_chars in subtypes
    end
  end

  describe "export/2 and import/1" do
    @tag :tmp_dir
    test "exports and imports test cases", %{tmp_dir: tmp_dir} do
      test_cases = [
        %{
          question: "What is foo?",
          context: "def foo, do: :bar",
          expected_answer: "foo returns bar",
          metadata: %{type: :test}
        }
      ]

      path = Path.join(tmp_dir, "test_cases.json")

      assert :ok = TestGenerator.export(test_cases, path)
      assert {:ok, imported} = TestGenerator.import(path)

      assert length(imported) == 1
      assert hd(imported).question == "What is foo?"
    end

    test "returns error for invalid path" do
      assert {:error, _} = TestGenerator.export([], "/invalid/path/test.json")
    end

    test "returns error for missing file" do
      assert {:error, _} = TestGenerator.import("/nonexistent/file.json")
    end
  end

  describe "golden_dataset/2" do
    test "generates combined dataset" do
      {:ok, dataset} = TestGenerator.golden_dataset(@sample_code, language: :elixir)

      assert dataset != []

      # Should have IDs
      assert Enum.all?(dataset, &Map.has_key?(&1, :id))

      # Should have mix of types
      types = Enum.map(dataset, & &1.metadata.type) |> Enum.uniq()
      assert length(types) >= 2
    end

    test "includes code-derived cases" do
      {:ok, dataset} = TestGenerator.golden_dataset(@sample_code)

      code_cases = Enum.filter(dataset, &(&1.metadata.type in [:module, :function]))
      assert code_cases != []
    end

    test "includes edge cases" do
      {:ok, dataset} = TestGenerator.golden_dataset(@sample_code)

      edge_cases = Enum.filter(dataset, &(&1.metadata.type == :edge_case))
      assert edge_cases != []
    end
  end
end
