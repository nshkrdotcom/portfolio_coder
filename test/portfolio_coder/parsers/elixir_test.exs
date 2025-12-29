defmodule PortfolioCoder.Parsers.ElixirTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Parsers.Elixir, as: ElixirParser

  @sample_module """
  defmodule MyApp.User do
    @moduledoc "User module"

    alias MyApp.Repo
    import Ecto.Query
    use GenServer

    @default_role :user

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    defp validate(user) do
      # validation logic
      user
    end

    defmacro is_admin(user) do
      quote do
        unquote(user).role == :admin
      end
    end
  end
  """

  describe "parse/1" do
    test "extracts module information" do
      {:ok, result} = ElixirParser.parse(@sample_module)

      assert length(result.modules) == 1
      [module] = result.modules
      assert module.name == "MyApp.User"
      assert module.type == :module
    end

    test "extracts public functions" do
      {:ok, result} = ElixirParser.parse(@sample_module)

      public_funcs = Enum.filter(result.functions, &(&1.visibility == :public))
      assert length(public_funcs) == 1
      assert hd(public_funcs).name == :start_link
      assert hd(public_funcs).arity == 1
    end

    test "extracts private functions" do
      {:ok, result} = ElixirParser.parse(@sample_module)

      private_funcs = Enum.filter(result.functions, &(&1.visibility == :private))
      assert length(private_funcs) == 1
      assert hd(private_funcs).name == :validate
    end

    test "extracts macros" do
      {:ok, result} = ElixirParser.parse(@sample_module)

      assert length(result.macros) == 1
      [macro] = result.macros
      assert macro.name == :is_admin
      assert macro.arity == 1
    end

    test "extracts imports" do
      {:ok, result} = ElixirParser.parse(@sample_module)

      assert length(result.imports) == 1
      [imp] = result.imports
      assert imp.module == "Ecto.Query"
    end

    test "extracts aliases" do
      {:ok, result} = ElixirParser.parse(@sample_module)

      assert length(result.aliases) == 1
      [al] = result.aliases
      assert al.module == "MyApp.Repo"
    end

    test "extracts uses" do
      {:ok, result} = ElixirParser.parse(@sample_module)

      assert length(result.uses) == 1
      [use] = result.uses
      assert use.module == "GenServer"
    end

    test "extracts module attributes" do
      {:ok, result} = ElixirParser.parse(@sample_module)

      # Filter out moduledoc which is also an attribute
      attrs = Enum.filter(result.module_attributes, &(&1.name == :default_role))
      assert length(attrs) == 1
      assert hd(attrs).value == :user
    end

    test "returns error for invalid syntax" do
      invalid = "defmodule Invalid do def broken("
      result = ElixirParser.parse(invalid)
      assert {:error, {:parse_error, _}} = result
    end
  end

  describe "extract_signatures/1" do
    test "extracts function signatures" do
      {:ok, signatures} = ElixirParser.extract_signatures(@sample_module)

      assert signatures != []
      start_link = Enum.find(signatures, &(&1.name == :start_link))
      assert start_link.signature == "start_link/1"
      assert start_link.visibility == :public
    end
  end

  describe "extract_definitions/1" do
    test "extracts module definitions" do
      {:ok, definitions} = ElixirParser.extract_definitions(@sample_module)

      assert length(definitions) == 1
      assert hd(definitions).name == "MyApp.User"
    end
  end
end
