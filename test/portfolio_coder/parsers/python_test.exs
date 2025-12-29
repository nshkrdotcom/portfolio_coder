defmodule PortfolioCoder.Parsers.PythonTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Parsers.Python, as: PythonParser

  @sample_code """
  import os
  import json as js
  from typing import List, Optional
  from dataclasses import dataclass

  @dataclass
  class User:
      \"\"\"User model.\"\"\"
      name: str
      email: str

  class Admin(User):
      \"\"\"Admin user with extra permissions.\"\"\"
      permissions: List[str]

      def __init__(self, name: str, email: str, permissions: List[str] = None):
          super().__init__(name, email)
          self.permissions = permissions or []

      def has_permission(self, perm: str) -> bool:
          return perm in self.permissions

      def _validate(self):
          # Private validation
          pass

  async def fetch_user(user_id: int) -> Optional[User]:
      \"\"\"Fetch a user by ID.\"\"\"
      pass

  def process_users(users: List[User]) -> None:
      for user in users:
          print(user.name)
  """

  describe "parse/1" do
    test "extracts class definitions" do
      {:ok, result} = PythonParser.parse(@sample_code)

      assert length(result.classes) == 2

      user_class = Enum.find(result.classes, &(&1.name == "User"))
      assert user_class != nil
      assert user_class.bases == []

      admin_class = Enum.find(result.classes, &(&1.name == "Admin"))
      assert admin_class != nil
      assert "User" in admin_class.bases
    end

    test "extracts function definitions" do
      {:ok, result} = PythonParser.parse(@sample_code)

      # Should find methods and top-level functions
      func_names = Enum.map(result.functions, & &1.name)
      assert "__init__" in func_names
      assert "has_permission" in func_names
      assert "_validate" in func_names
      assert "fetch_user" in func_names
      assert "process_users" in func_names
    end

    test "detects async functions" do
      {:ok, result} = PythonParser.parse(@sample_code)

      fetch_user = Enum.find(result.functions, &(&1.name == "fetch_user"))
      assert fetch_user.async == true

      process_users = Enum.find(result.functions, &(&1.name == "process_users"))
      assert process_users.async == false
    end

    test "detects private functions" do
      {:ok, result} = PythonParser.parse(@sample_code)

      validate = Enum.find(result.functions, &(&1.name == "_validate"))
      assert validate.visibility == :private

      has_permission = Enum.find(result.functions, &(&1.name == "has_permission"))
      assert has_permission.visibility == :public
    end

    test "extracts imports" do
      {:ok, result} = PythonParser.parse(@sample_code)

      import_modules = Enum.map(result.imports, & &1.module)
      assert "os" in import_modules
      assert "json" in import_modules

      json_import = Enum.find(result.imports, &(&1.module == "json"))
      assert json_import.alias == "js"
    end

    test "extracts from imports" do
      {:ok, result} = PythonParser.parse(@sample_code)

      from_modules = Enum.map(result.from_imports, & &1.module)
      assert "typing" in from_modules
      assert "dataclasses" in from_modules

      typing_import = Enum.find(result.from_imports, &(&1.module == "typing"))
      import_names = Enum.map(typing_import.imports, & &1.name)
      assert "List" in import_names
      assert "Optional" in import_names
    end

    test "extracts decorators" do
      {:ok, result} = PythonParser.parse(@sample_code)

      decorator_names = Enum.map(result.decorators, & &1.name)
      assert "dataclass" in decorator_names
    end
  end

  describe "extract_signatures/1" do
    test "extracts function signatures" do
      {:ok, signatures} = PythonParser.extract_signatures(@sample_code)

      fetch_user = Enum.find(signatures, &(&1.name == "fetch_user"))
      assert fetch_user != nil
      assert fetch_user.async == true
    end
  end

  describe "extract_definitions/1" do
    test "extracts class definitions" do
      {:ok, definitions} = PythonParser.extract_definitions(@sample_code)

      class_names = Enum.map(definitions, & &1.name)
      assert "User" in class_names
      assert "Admin" in class_names
    end
  end
end
