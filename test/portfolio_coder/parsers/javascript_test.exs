defmodule PortfolioCoder.Parsers.JavaScriptTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Parsers.JavaScript, as: JSParser

  @sample_code """
  import React from 'react';
  import { useState, useEffect } from 'react';
  import * as utils from './utils';
  import './styles.css';

  interface User {
    id: number;
    name: string;
  }

  type UserRole = 'admin' | 'user' | 'guest';

  class UserService {
    constructor(private api: ApiClient) {}

    async getUser(id: number): Promise<User> {
      return this.api.get(`/users/${id}`);
    }
  }

  export class AdminService extends UserService {
    getAdmins() {
      return this.api.get('/admins');
    }
  }

  function processUser(user: User): void {
    console.log(user.name);
  }

  async function fetchUsers(): Promise<User[]> {
    const response = await fetch('/api/users');
    return response.json();
  }

  const getUserName = (user: User) => user.name;

  const asyncFetch = async (url: string) => {
    return await fetch(url);
  };

  export { processUser };
  export default UserService;
  """

  describe "parse/1" do
    test "extracts class definitions" do
      {:ok, result} = JSParser.parse(@sample_code)

      assert length(result.classes) >= 2

      user_service = Enum.find(result.classes, &(&1.name == "UserService"))
      assert user_service != nil

      admin_service = Enum.find(result.classes, &(&1.name == "AdminService"))
      assert admin_service != nil
      assert admin_service.extends == "UserService"
    end

    test "extracts function definitions" do
      {:ok, result} = JSParser.parse(@sample_code)

      func_names = Enum.map(result.functions, & &1.name)
      assert "processUser" in func_names
      assert "fetchUsers" in func_names
    end

    test "detects async functions" do
      {:ok, result} = JSParser.parse(@sample_code)

      fetch_users = Enum.find(result.functions, &(&1.name == "fetchUsers"))
      assert fetch_users.async == true

      process_user = Enum.find(result.functions, &(&1.name == "processUser"))
      assert process_user.async == false
    end

    test "extracts arrow functions" do
      {:ok, result} = JSParser.parse(@sample_code)

      arrow_names = Enum.map(result.arrow_functions, & &1.name)
      assert "getUserName" in arrow_names
      assert "asyncFetch" in arrow_names

      async_fetch = Enum.find(result.arrow_functions, &(&1.name == "asyncFetch"))
      assert async_fetch.async == true
    end

    test "extracts named imports" do
      {:ok, result} = JSParser.parse(@sample_code)

      named_imports = Enum.filter(result.imports, &(&1.type == :named_import))
      assert named_imports != []

      react_imports = Enum.find(named_imports, &(&1.module == "react"))
      assert react_imports != nil
      import_names = Enum.map(react_imports.imports, & &1.name)
      assert "useState" in import_names
      assert "useEffect" in import_names
    end

    test "extracts default imports" do
      {:ok, result} = JSParser.parse(@sample_code)

      default_imports = Enum.filter(result.imports, &(&1.type == :default_import))
      react_import = Enum.find(default_imports, &(&1.module == "react"))
      assert react_import != nil
      assert react_import.name == "React"
    end

    test "extracts namespace imports" do
      {:ok, result} = JSParser.parse(@sample_code)

      namespace_imports = Enum.filter(result.imports, &(&1.type == :namespace_import))
      utils_import = Enum.find(namespace_imports, &(&1.module == "./utils"))
      assert utils_import != nil
      assert utils_import.name == "utils"
    end

    test "extracts exports" do
      {:ok, result} = JSParser.parse(@sample_code)

      export_types = Enum.map(result.exports, & &1.type)
      assert :named_export in export_types
      assert :default_export in export_types
    end

    test "extracts TypeScript interfaces" do
      {:ok, result} = JSParser.parse(@sample_code)

      interface_names = Enum.map(result.interfaces, & &1.name)
      assert "User" in interface_names
    end

    test "extracts TypeScript type aliases" do
      {:ok, result} = JSParser.parse(@sample_code)

      type_names = Enum.map(result.types, & &1.name)
      assert "UserRole" in type_names
    end
  end

  describe "extract_signatures/1" do
    test "extracts function signatures" do
      {:ok, signatures} = JSParser.extract_signatures(@sample_code)

      func_names = Enum.map(signatures, & &1.name)
      assert "processUser" in func_names
      assert "fetchUsers" in func_names
      assert "getUserName" in func_names
    end
  end

  describe "extract_definitions/1" do
    test "extracts class and interface definitions" do
      {:ok, definitions} = JSParser.extract_definitions(@sample_code)

      names = Enum.map(definitions, & &1.name)
      assert "UserService" in names
      assert "AdminService" in names
      assert "User" in names
    end
  end
end
