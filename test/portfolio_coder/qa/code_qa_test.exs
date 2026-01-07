defmodule PortfolioCoder.QA.CodeQATest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.QA.CodeQA

  @sample_docs [
    %{
      id: "parser.ex:1",
      content: """
      defmodule MyApp.Parser do
        @moduledoc "Parses source files"
        def parse(path), do: {:ok, %{}}
      end
      """,
      metadata: %{path: "lib/my_app/parser.ex", language: :elixir, type: :module}
    },
    %{
      id: "search.ex:1",
      content: """
      defmodule MyApp.Search do
        @moduledoc "Search functionality"
        def search(query), do: []
      end
      """,
      metadata: %{path: "lib/my_app/search.ex", language: :elixir, type: :module}
    }
  ]

  setup do
    {:ok, index} = InMemorySearch.new()
    :ok = InMemorySearch.add_all(index, @sample_docs)
    {:ok, index: index}
  end

  describe "new/1" do
    test "creates a new QA instance with index", %{index: index} do
      qa = CodeQA.new(index)

      assert is_struct(qa, CodeQA)
      assert qa.index == index
    end

    test "creates QA with options", %{index: index} do
      qa = CodeQA.new(index, max_results: 5, answer_prompt: "custom prompt")

      assert qa.max_results == 5
      assert qa.answer_prompt == "custom prompt"
    end
  end

  describe "retrieve_context/2" do
    test "retrieves relevant documents", %{index: index} do
      qa = CodeQA.new(index)

      {:ok, context} = CodeQA.retrieve_context(qa, "parser module")

      assert is_list(context.documents)
      assert context.documents != []
      assert is_binary(context.formatted)
    end

    test "returns empty when no matches", %{index: index} do
      qa = CodeQA.new(index)

      {:ok, context} = CodeQA.retrieve_context(qa, "nonexistent xyz123")

      assert context.documents == []
    end
  end

  describe "format_context/1" do
    test "formats documents into context string" do
      documents = @sample_docs

      formatted = CodeQA.format_context(documents)

      assert is_binary(formatted)
      assert String.contains?(formatted, "parser.ex")
      assert String.contains?(formatted, "defmodule")
    end

    test "handles empty documents" do
      formatted = CodeQA.format_context([])

      assert formatted == "No relevant code found."
    end
  end

  describe "build_prompt/3" do
    test "builds prompt with context and question" do
      context = "defmodule Test do end"
      question = "What does Test do?"

      prompt = CodeQA.build_prompt(context, question)

      assert is_binary(prompt)
      assert String.contains?(prompt, context)
      assert String.contains?(prompt, question)
    end

    test "accepts custom template" do
      context = "code here"
      question = "question here"
      template = "Context: <%= context %>\nQ: <%= question %>"

      prompt = CodeQA.build_prompt(context, question, template: template)

      assert prompt == "Context: code here\nQ: question here"
    end
  end

  describe "ask/2 (mock LLM)" do
    test "returns answer structure without LLM", %{index: index} do
      # Without actual LLM, we test the retrieval and preparation
      qa = CodeQA.new(index, llm_module: nil)

      {:ok, result} = CodeQA.ask(qa, "What does Parser do?")

      assert is_map(result)
      assert Map.has_key?(result, :question)
      assert Map.has_key?(result, :context)
      assert Map.has_key?(result, :sources)
      assert result.question == "What does Parser do?"
    end

    test "includes source information", %{index: index} do
      qa = CodeQA.new(index, llm_module: nil)

      {:ok, result} = CodeQA.ask(qa, "parser")

      assert is_list(result.sources)
    end
  end

  describe "prepare_sources/1" do
    test "extracts source information from documents" do
      documents = @sample_docs

      sources = CodeQA.prepare_sources(documents)

      assert is_list(sources)
      assert length(sources) == 2

      first = hd(sources)
      assert Map.has_key?(first, :path)
      assert Map.has_key?(first, :id)
    end
  end

  describe "with_query_enhancement/2" do
    test "enables query enhancement", %{index: index} do
      qa = CodeQA.new(index)

      enhanced_qa = CodeQA.with_query_enhancement(qa, true)

      assert enhanced_qa.query_enhancement == true
    end
  end

  describe "config/0" do
    test "returns default configuration" do
      config = CodeQA.config()

      assert is_map(config)
      assert Map.has_key?(config, :max_results)
      assert Map.has_key?(config, :answer_prompt)
    end
  end
end
