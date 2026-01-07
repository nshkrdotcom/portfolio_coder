defmodule PortfolioCoder.Docs.GeneratorTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Docs.Generator
  alias PortfolioCoder.Graph.InMemoryGraph
  alias PortfolioCoder.Indexer.InMemorySearch

  @sample_docs [
    %{
      id: "parser.ex:1",
      content: """
      defmodule MyApp.Parser do
        @moduledoc "Parses source files"
        def parse(path), do: {:ok, %{}}
        defp internal_parse(content), do: content
      end
      """,
      metadata: %{path: "lib/my_app/parser.ex", language: :elixir, type: :module}
    }
  ]

  setup do
    {:ok, index} = InMemorySearch.new()
    :ok = InMemorySearch.add_all(index, @sample_docs)
    {:ok, graph} = InMemoryGraph.new()
    {:ok, index: index, graph: graph}
  end

  describe "new/2" do
    test "creates generator", %{index: index, graph: graph} do
      gen = Generator.new(index, graph)

      assert is_struct(gen, Generator)
    end

    test "accepts options", %{index: index, graph: graph} do
      gen = Generator.new(index, graph, format: :markdown, include_private: true)

      assert gen.format == :markdown
      assert gen.include_private == true
    end
  end

  describe "generate_module_doc/2" do
    test "generates documentation for a module", %{index: index, graph: graph} do
      gen = Generator.new(index, graph)

      {:ok, doc} = Generator.generate_module_doc(gen, "MyApp.Parser")

      assert is_binary(doc)
      assert String.contains?(doc, "MyApp.Parser")
    end
  end

  describe "generate_function_doc/3" do
    test "generates documentation for a function", %{index: index, graph: graph} do
      gen = Generator.new(index, graph)

      {:ok, doc} = Generator.generate_function_doc(gen, "MyApp.Parser", "parse")

      assert is_binary(doc)
    end
  end

  describe "generate_api_docs/2" do
    test "generates API documentation for multiple modules", %{index: index, graph: graph} do
      gen = Generator.new(index, graph)

      {:ok, docs} = Generator.generate_api_docs(gen, ["MyApp.Parser"])

      assert is_list(docs)
    end
  end

  describe "extract_type_specs/2" do
    test "extracts type specs from module", %{index: index, graph: graph} do
      gen = Generator.new(index, graph)

      {:ok, specs} = Generator.extract_type_specs(gen, "MyApp.Parser")

      assert is_list(specs)
    end
  end

  describe "generate_readme/1" do
    test "generates README template", %{index: index, graph: graph} do
      gen = Generator.new(index, graph)

      {:ok, readme} = Generator.generate_readme(gen)

      assert is_binary(readme)
      assert String.contains?(readme, "#")
    end
  end

  describe "generate_changelog_entry/2" do
    test "generates changelog entry", %{index: index, graph: graph} do
      gen = Generator.new(index, graph)
      changes = [%{type: :added, description: "New feature"}]

      {:ok, entry} = Generator.generate_changelog_entry(gen, changes)

      assert is_binary(entry)
    end
  end

  describe "format_output/2" do
    test "formats output as markdown" do
      content = %{title: "Test", body: "Content"}

      output = Generator.format_output(content, :markdown)

      assert is_binary(output)
    end

    test "formats output as html" do
      content = %{title: "Test", body: "Content"}

      output = Generator.format_output(content, :html)

      assert is_binary(output)
    end
  end

  describe "config/0" do
    test "returns default configuration" do
      config = Generator.config()

      assert is_map(config)
      assert Map.has_key?(config, :format)
    end
  end
end
