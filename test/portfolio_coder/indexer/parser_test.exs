defmodule PortfolioCoder.Indexer.ParserTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Indexer.Parser

  describe "parse_string/2" do
    test "parses Elixir code and extracts symbols" do
      code = """
      defmodule MyApp.User do
        @moduledoc "User module"

        import Ecto.Query
        alias MyApp.Repo

        def get(id), do: Repo.get(__MODULE__, id)
        defp validate(user), do: user
      end
      """

      {:ok, result} = Parser.parse_string(code, :elixir)

      assert result.language == :elixir
      assert is_list(result.symbols)
      assert is_list(result.references)

      # Should have module and functions
      module = Enum.find(result.symbols, &(&1.type == :module))
      assert module != nil
      assert module.name == "MyApp.User"

      functions = Enum.filter(result.symbols, &(&1.type == :function))
      assert length(functions) == 2
    end

    test "parses Python code and extracts symbols" do
      code = """
      import os
      from typing import List

      class User:
          def __init__(self, name):
              self.name = name

          def greet(self):
              return f"Hello, {self.name}"
      """

      {:ok, result} = Parser.parse_string(code, :python)

      assert result.language == :python
      assert is_list(result.symbols)
      assert is_list(result.references)

      # Should have class and functions
      class = Enum.find(result.symbols, &(&1.type == :class))
      assert class != nil
      assert class.name == "User"

      functions = Enum.filter(result.symbols, &(&1.type == :function))
      assert length(functions) >= 2
    end

    test "parses JavaScript code and extracts symbols" do
      code = """
      import { Component } from 'react';

      class UserList extends Component {
        constructor(props) {
          super(props);
        }

        render() {
          return <div />;
        }
      }

      function formatUser(user) {
        return user.name;
      }

      const getAge = (user) => user.age;
      """

      {:ok, result} = Parser.parse_string(code, :javascript)

      assert result.language == :javascript
      assert is_list(result.symbols)
      assert is_list(result.references)

      class = Enum.find(result.symbols, &(&1.type == :class))
      assert class != nil
      assert class.name == "UserList"
    end

    test "parses TypeScript with interfaces" do
      code = """
      interface User {
        name: string;
        age: number;
      }

      type UserList = User[];

      class UserService {
        getUser(id: number): User {
          return { name: 'test', age: 0 };
        }
      }
      """

      {:ok, result} = Parser.parse_string(code, :typescript)

      assert result.language == :typescript

      interface = Enum.find(result.symbols, &(&1.type == :interface))
      assert interface != nil
      assert interface.name == "User"

      type_alias = Enum.find(result.symbols, &(&1.type == :type))
      assert type_alias != nil
      assert type_alias.name == "UserList"
    end

    test "returns error for unsupported language" do
      {:error, {:unsupported_language, :ruby}} = Parser.parse_string("class Foo; end", :ruby)
    end
  end

  describe "extract_symbols/2" do
    test "extracts all Elixir symbols" do
      code = """
      defmodule MyApp.Math do
        defmacro add(a, b), do: quote(do: unquote(a) + unquote(b))

        def multiply(a, b), do: a * b
        defp divide(a, b), do: a / b
      end
      """

      {:ok, result} = Parser.parse_string(code, :elixir)
      symbols = Parser.extract_symbols(result)

      # Module
      modules = Enum.filter(symbols, &(&1.type == :module))
      assert length(modules) == 1

      # Functions
      functions = Enum.filter(symbols, &(&1.type == :function))
      assert length(functions) == 2

      public_fn = Enum.find(functions, &(&1.visibility == :public))
      private_fn = Enum.find(functions, &(&1.visibility == :private))

      assert public_fn != nil
      assert private_fn != nil

      # Macros
      macros = Enum.filter(symbols, &(&1.type == :macro))
      assert length(macros) == 1
    end
  end

  describe "extract_references/2" do
    test "extracts Elixir references" do
      code = """
      defmodule MyApp.Controller do
        use Phoenix.Controller
        import Ecto.Query
        alias MyApp.User
        alias MyApp.Repo

        def index(conn, _), do: conn
      end
      """

      {:ok, result} = Parser.parse_string(code, :elixir)
      refs = Parser.extract_references(result)

      uses = Enum.filter(refs, &(&1.type == :use))
      imports = Enum.filter(refs, &(&1.type == :import))
      aliases = Enum.filter(refs, &(&1.type == :alias))

      assert length(uses) == 1
      assert hd(uses).module == "Phoenix.Controller"

      assert length(imports) == 1
      assert hd(imports).module == "Ecto.Query"

      assert length(aliases) == 2
    end

    test "extracts Python references" do
      code = """
      import os
      import sys as system
      from typing import List, Optional
      from collections.abc import Mapping

      def main():
          pass
      """

      {:ok, result} = Parser.parse_string(code, :python)
      refs = Parser.extract_references(result)

      imports = Enum.filter(refs, &(&1.type == :import))
      from_imports = Enum.filter(refs, &(&1.type == :from_import))

      assert length(imports) == 2
      assert length(from_imports) == 2
    end

    test "extracts JavaScript/TypeScript references" do
      code = """
      import React from 'react';
      import { useState, useEffect } from 'react';
      import * as utils from './utils';
      """

      {:ok, result} = Parser.parse_string(code, :javascript)
      refs = Parser.extract_references(result)

      assert length(refs) >= 3

      default_import = Enum.find(refs, &(&1.metadata[:default] != nil))
      assert default_import != nil

      named_import = Enum.find(refs, &(&1.metadata[:imports] != nil))
      assert named_import != nil

      namespace_import = Enum.find(refs, &(&1.metadata[:namespace] != nil))
      assert namespace_import != nil
    end
  end
end
