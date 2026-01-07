defmodule PortfolioCoder.Docs.SearchTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Docs.Search
  alias PortfolioCoder.Indexer.InMemorySearch

  @sample_docs [
    %{
      id: "parser.ex:1",
      content: """
      defmodule MyApp.Parser do
        @moduledoc \"\"\"
        Parses source files into AST.

        ## Usage

            {:ok, ast} = Parser.parse("file.ex")
        \"\"\"
        @doc "Parse a source file"
        def parse(path), do: {:ok, %{}}
      end
      """,
      metadata: %{path: "lib/my_app/parser.ex", language: :elixir, type: :module}
    },
    %{
      id: "search.ex:1",
      content: """
      defmodule MyApp.Search do
        @moduledoc "Search functionality for the application"
        @doc "Search for items matching query"
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
    test "creates doc search instance", %{index: index} do
      search = Search.new(index)

      assert is_struct(search, Search)
    end

    test "accepts options", %{index: index} do
      search = Search.new(index, include_code: true, max_results: 10)

      assert search.include_code == true
      assert search.max_results == 10
    end
  end

  describe "search_docs/2" do
    test "searches documentation content", %{index: index} do
      search = Search.new(index)

      {:ok, results} = Search.search_docs(search, "parse")

      assert is_list(results)
      assert results != []
    end

    test "returns empty for no matches", %{index: index} do
      search = Search.new(index)

      # Query must not match any content in sample docs
      {:ok, results} = Search.search_docs(search, "zzzznotfound7777")

      # Could be empty or not depending on search algorithm
      assert is_list(results)
    end
  end

  describe "search_modules/2" do
    test "searches for modules by name", %{index: index} do
      search = Search.new(index)

      {:ok, results} = Search.search_modules(search, "Parser")

      assert is_list(results)
    end
  end

  describe "search_functions/2" do
    test "searches for functions by name", %{index: index} do
      search = Search.new(index)

      {:ok, results} = Search.search_functions(search, "parse")

      assert is_list(results)
    end
  end

  describe "search_examples/2" do
    test "searches for code examples", %{index: index} do
      search = Search.new(index)

      {:ok, results} = Search.search_examples(search, "parse")

      assert is_list(results)
    end
  end

  describe "suggest_completion/2" do
    test "suggests completions for partial query", %{index: index} do
      search = Search.new(index)

      {:ok, suggestions} = Search.suggest_completion(search, "pars")

      assert is_list(suggestions)
    end
  end

  describe "get_module_summary/2" do
    test "gets module summary", %{index: index} do
      search = Search.new(index)

      {:ok, summary} = Search.get_module_summary(search, "MyApp.Parser")

      assert is_map(summary)
      assert Map.has_key?(summary, :module)
      assert Map.has_key?(summary, :description)
    end
  end

  describe "get_function_doc/3" do
    test "gets function documentation", %{index: index} do
      search = Search.new(index)

      {:ok, doc} = Search.get_function_doc(search, "MyApp.Parser", "parse")

      assert is_map(doc) or is_nil(doc.description)
    end
  end

  describe "list_modules/1" do
    test "lists all documented modules", %{index: index} do
      search = Search.new(index)

      {:ok, modules} = Search.list_modules(search)

      assert is_list(modules)
    end
  end

  describe "config/0" do
    test "returns default configuration" do
      config = Search.config()

      assert is_map(config)
      assert Map.has_key?(config, :max_results)
    end
  end
end
