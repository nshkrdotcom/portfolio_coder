defmodule PortfolioCoder.Parsers.Elixir do
  @moduledoc """
  Elixir source code parser using Sourceror.

  Extracts modules, functions, macros, and other structural elements
  from Elixir source code.
  """

  @doc """
  Parse Elixir source code and extract structure.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(content) do
    case Sourceror.parse_string(content) do
      {:ok, ast} ->
        result = %{
          modules: extract_modules(ast),
          functions: extract_functions(ast),
          macros: extract_macros(ast),
          imports: extract_imports(ast),
          aliases: extract_aliases(ast),
          uses: extract_uses(ast),
          module_attributes: extract_module_attributes(ast)
        }

        {:ok, result}

      {:error, error} ->
        {:error, {:parse_error, error}}
    end
  end

  @doc """
  Extract function signatures from Elixir code.
  """
  @spec extract_signatures(String.t()) :: {:ok, [map()]} | {:error, term()}
  def extract_signatures(content) do
    case Sourceror.parse_string(content) do
      {:ok, ast} ->
        signatures =
          ast
          |> extract_functions()
          |> Enum.map(fn func ->
            %{
              name: func.name,
              arity: func.arity,
              signature: "#{func.name}/#{func.arity}",
              visibility: func.visibility,
              line: func.line
            }
          end)

        {:ok, signatures}

      {:error, error} ->
        {:error, {:parse_error, error}}
    end
  end

  @doc """
  Extract module definitions from Elixir code.
  """
  @spec extract_definitions(String.t()) :: {:ok, [map()]} | {:error, term()}
  def extract_definitions(content) do
    case Sourceror.parse_string(content) do
      {:ok, ast} ->
        definitions = extract_modules(ast)
        {:ok, definitions}

      {:error, error} ->
        {:error, {:parse_error, error}}
    end
  end

  # Private functions
  # Using Macro.postwalk instead of Sourceror.postwalk for more reliable accumulator handling

  defp extract_modules(ast) do
    {_ast, acc} =
      Macro.postwalk(ast, [], fn
        {:defmodule, meta, [{:__aliases__, _, parts}, _body]} = node, acc ->
          module = %{
            name: Enum.join(parts, "."),
            line: Keyword.get(meta, :line, 0),
            type: :module
          }

          {node, [module | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  defp extract_functions(ast) do
    {_ast, acc} =
      Macro.postwalk(ast, [], fn
        {def_type, meta, [{name, _, args} | _]} = node, acc
        when def_type in [:def, :defp] and is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0

          func = %{
            name: name,
            arity: arity,
            visibility: if(def_type == :def, do: :public, else: :private),
            line: Keyword.get(meta, :line, 0),
            type: :function
          }

          {node, [func | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  defp extract_macros(ast) do
    {_ast, acc} =
      Macro.postwalk(ast, [], fn
        {def_type, meta, [{name, _, args} | _]} = node, acc
        when def_type in [:defmacro, :defmacrop] and is_atom(name) ->
          arity = if is_list(args), do: length(args), else: 0

          macro = %{
            name: name,
            arity: arity,
            visibility: if(def_type == :defmacro, do: :public, else: :private),
            line: Keyword.get(meta, :line, 0),
            type: :macro
          }

          {node, [macro | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  defp extract_imports(ast) do
    {_ast, acc} =
      Macro.postwalk(ast, [], fn
        {:import, meta, [{:__aliases__, _, parts} | _]} = node, acc ->
          import_info = %{
            module: Enum.join(parts, "."),
            line: Keyword.get(meta, :line, 0),
            type: :import
          }

          {node, [import_info | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  defp extract_aliases(ast) do
    {_ast, acc} =
      Macro.postwalk(ast, [], fn
        {:alias, meta, [{:__aliases__, _, parts} | opts]} = node, acc ->
          as_name =
            case opts do
              [[as: {:__aliases__, _, as_parts}]] -> Enum.join(as_parts, ".")
              _ -> List.last(parts) |> to_string()
            end

          alias_info = %{
            module: Enum.join(parts, "."),
            as: as_name,
            line: Keyword.get(meta, :line, 0),
            type: :alias
          }

          {node, [alias_info | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  defp extract_uses(ast) do
    {_ast, acc} =
      Macro.postwalk(ast, [], fn
        {:use, meta, [{:__aliases__, _, parts} | _]} = node, acc ->
          use_info = %{
            module: Enum.join(parts, "."),
            line: Keyword.get(meta, :line, 0),
            type: :use
          }

          {node, [use_info | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  defp extract_module_attributes(ast) do
    {_ast, acc} =
      Macro.postwalk(ast, [], fn
        {:@, meta, [{name, _, [value]}]} = node, acc when is_atom(name) ->
          attr = %{
            name: name,
            value: extract_attribute_value(value),
            line: Keyword.get(meta, :line, 0),
            type: :module_attribute
          }

          {node, [attr | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(acc)
  end

  defp extract_attribute_value(value) when is_binary(value), do: value
  defp extract_attribute_value(value) when is_atom(value), do: value
  defp extract_attribute_value(value) when is_number(value), do: value
  defp extract_attribute_value(value) when is_list(value), do: value
  # Handle __block__ AST nodes (literal values from Sourceror)
  defp extract_attribute_value({:__block__, _meta, [value]}), do: extract_attribute_value(value)
  defp extract_attribute_value(_), do: :complex
end
