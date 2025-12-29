defmodule PortfolioCoder.ParsersTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Parsers

  describe "parse/2" do
    test "delegates to Elixir parser" do
      code = "defmodule Test do end"
      {:ok, result} = Parsers.parse(code, :elixir)
      assert is_map(result)
      assert Map.has_key?(result, :modules)
    end

    test "delegates to Python parser" do
      code = "class Test: pass"
      {:ok, result} = Parsers.parse(code, :python)
      assert is_map(result)
      assert Map.has_key?(result, :classes)
    end

    test "delegates to JavaScript parser" do
      code = "class Test {}"
      {:ok, result} = Parsers.parse(code, :javascript)
      assert is_map(result)
      assert Map.has_key?(result, :classes)
    end

    test "handles TypeScript via JavaScript parser" do
      code = "interface User { name: string }"
      {:ok, result} = Parsers.parse(code, :typescript)
      assert is_map(result)
      assert Map.has_key?(result, :interfaces)
    end

    test "returns error for unsupported language" do
      result = Parsers.parse("code", :ruby)
      assert {:error, {:unsupported_language, :ruby}} = result
    end
  end

  describe "extract_signatures/2" do
    test "extracts Elixir function signatures" do
      code = "defmodule Test do def hello(name), do: name end"
      {:ok, signatures} = Parsers.extract_signatures(code, :elixir)
      assert signatures != []
    end

    test "extracts Python function signatures" do
      code = "def hello(name): return name"
      {:ok, signatures} = Parsers.extract_signatures(code, :python)
      assert signatures != []
    end

    test "extracts JavaScript function signatures" do
      code = "function hello(name) { return name; }"
      {:ok, signatures} = Parsers.extract_signatures(code, :javascript)
      assert signatures != []
    end
  end

  describe "extract_definitions/2" do
    test "extracts Elixir module definitions" do
      code = "defmodule MyApp.User do end"
      {:ok, definitions} = Parsers.extract_definitions(code, :elixir)
      assert length(definitions) == 1
      assert hd(definitions).name == "MyApp.User"
    end

    test "extracts Python class definitions" do
      code = "class User: pass"
      {:ok, definitions} = Parsers.extract_definitions(code, :python)
      assert length(definitions) == 1
      assert hd(definitions).name == "User"
    end

    test "extracts JavaScript class definitions" do
      code = "class User {}"
      {:ok, definitions} = Parsers.extract_definitions(code, :javascript)
      class_defs = Enum.filter(definitions, &(&1.type == :class))
      assert class_defs != []
    end
  end
end
