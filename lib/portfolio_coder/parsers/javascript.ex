defmodule PortfolioCoder.Parsers.JavaScript do
  @moduledoc """
  JavaScript/TypeScript source code parser using regex-based extraction.

  Extracts classes, functions, imports, exports, and other structural
  elements from JavaScript and TypeScript source code.
  """

  @doc """
  Parse JavaScript/TypeScript source code and extract structure.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(content) do
    result = %{
      classes: extract_classes(content),
      functions: extract_functions(content),
      arrow_functions: extract_arrow_functions(content),
      imports: extract_imports(content),
      exports: extract_exports(content),
      interfaces: extract_interfaces(content),
      types: extract_type_aliases(content)
    }

    {:ok, result}
  rescue
    e -> {:error, {:parse_error, e}}
  end

  @doc """
  Extract function signatures from JavaScript code.
  """
  @spec extract_signatures(String.t()) :: {:ok, [map()]} | {:error, term()}
  def extract_signatures(content) do
    functions = extract_functions(content)
    arrows = extract_arrow_functions(content)

    signatures =
      (functions ++ arrows)
      |> Enum.map(fn func ->
        %{
          name: func.name,
          signature: func[:signature] || func.name,
          async: func[:async] || false,
          line: func.line
        }
      end)

    {:ok, signatures}
  rescue
    e -> {:error, {:parse_error, e}}
  end

  @doc """
  Extract class/interface definitions from JavaScript code.
  """
  @spec extract_definitions(String.t()) :: {:ok, [map()]} | {:error, term()}
  def extract_definitions(content) do
    classes = extract_classes(content)
    interfaces = extract_interfaces(content)
    {:ok, classes ++ interfaces}
  rescue
    e -> {:error, {:parse_error, e}}
  end

  # Private functions
  # Using numbered capture groups to avoid alphabetical ordering issues with named captures

  defp extract_classes(content) do
    # Match class definitions: class Name extends Base implements Interface
    ~r/(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+(\w+)(?:\s+extends\s+(\w+))?(?:\s+implements\s+([\w,\s]+))?/m
    |> Regex.scan(content)
    |> Enum.map(fn
      [_full, name] ->
        line = find_line_number(content, "class #{name}")
        %{name: name, extends: nil, implements: [], line: line, type: :class}

      [_full, name, extends] ->
        line = find_line_number(content, "class #{name}")
        %{name: name, extends: extends, implements: [], line: line, type: :class}

      [_full, name, extends, implements] ->
        line = find_line_number(content, "class #{name}")

        impl_list =
          implements
          |> String.split(",")
          |> Enum.map(&String.trim/1)

        %{name: name, extends: extends, implements: impl_list, line: line, type: :class}
    end)
  end

  defp extract_functions(content) do
    # Match function declarations: function name(args) or async function name(args)
    ~r/(?:export\s+)?(?:default\s+)?(async\s+)?function\s*(\*)?(\w+)\s*\(([^)]*)\)/m
    |> Regex.scan(content)
    |> Enum.map(fn
      [_full, async, generator, name, args] ->
        line = find_line_number(content, "function #{name}")
        is_async = async != nil and async != ""
        is_generator = generator == "*"

        %{
          name: name,
          args: parse_args(args),
          signature: "#{name}(#{args})",
          async: is_async,
          generator: is_generator,
          line: line,
          type: :function
        }

      [_full, generator_or_name, name_or_args, args] when is_binary(args) ->
        # Handle case without async: function *name(args) or function name(args)
        {name, is_generator} =
          if generator_or_name == "*" do
            {name_or_args, true}
          else
            {generator_or_name, false}
          end

        line = find_line_number(content, "function #{name}")

        %{
          name: name,
          args: parse_args(args),
          signature: "#{name}(#{args})",
          async: false,
          generator: is_generator,
          line: line,
          type: :function
        }

      [_full, name, args] ->
        line = find_line_number(content, "function #{name}")

        %{
          name: name,
          args: parse_args(args),
          signature: "#{name}(#{args})",
          async: false,
          generator: false,
          line: line,
          type: :function
        }
    end)
  end

  defp extract_arrow_functions(content) do
    # Match arrow function assignments: const name = (args) => or const name = async (args) =>
    ~r/(?:const|let|var)\s+(\w+)\s*=\s*(async\s+)?\(?([^)=]*)\)?\s*=>/m
    |> Regex.scan(content)
    |> Enum.map(fn
      [_full, name, async, args] ->
        line = find_line_number(content, "#{name} =")
        is_async = async != nil and async != ""

        %{
          name: name,
          args: parse_args(args),
          async: is_async,
          line: line,
          type: :arrow_function
        }

      [_full, name, args] ->
        line = find_line_number(content, "#{name} =")

        %{
          name: name,
          args: parse_args(args),
          async: false,
          line: line,
          type: :arrow_function
        }
    end)
  end

  defp extract_imports(content) do
    imports = []

    # Named imports: import { a, b } from 'module'
    named =
      ~r/import\s+\{([^}]+)\}\s+from\s+['"]([^'"]+)['"]/m
      |> Regex.scan(content)
      |> Enum.map(fn [_full, names, module] ->
        line = find_line_number(content, "from '#{module}'")
        imported = parse_import_names(names)
        %{module: module, imports: imported, line: line, type: :named_import}
      end)

    # Default imports: import name from 'module'
    default =
      ~r/import\s+(\w+)\s+from\s+['"]([^'"]+)['"]/m
      |> Regex.scan(content)
      |> Enum.map(fn [_full, name, module] ->
        line = find_line_number(content, "import #{name}")
        %{name: name, module: module, line: line, type: :default_import}
      end)

    # Namespace imports: import * as name from 'module'
    namespace =
      ~r/import\s+\*\s+as\s+(\w+)\s+from\s+['"]([^'"]+)['"]/m
      |> Regex.scan(content)
      |> Enum.map(fn [_full, name, module] ->
        line = find_line_number(content, "import *")
        %{name: name, module: module, line: line, type: :namespace_import}
      end)

    # Side-effect imports: import 'module'
    side_effect =
      ~r/import\s+['"]([^'"]+)['"]/m
      |> Regex.scan(content)
      |> Enum.reject(fn [_full, module] ->
        # Exclude modules already captured by other patterns
        String.contains?(content, "from '#{module}'") or
          String.contains?(content, "from \"#{module}\"")
      end)
      |> Enum.map(fn [_full, module] ->
        line = find_line_number(content, "import '#{module}'")
        %{module: module, line: line, type: :side_effect_import}
      end)

    imports ++ named ++ default ++ namespace ++ side_effect
  end

  defp extract_exports(content) do
    exports = []

    # Named exports: export { a, b }
    named =
      ~r/export\s+\{([^}]+)\}/m
      |> Regex.scan(content)
      |> Enum.map(fn [_full, names] ->
        line = find_line_number(content, "export {")

        exported =
          names
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        %{exports: exported, line: line, type: :named_export}
      end)

    # Default export: export default
    default =
      ~r/export\s+default\s+(?:class|function)?\s*(\w+)?/m
      |> Regex.scan(content)
      |> Enum.map(fn
        [_full, name] ->
          line = find_line_number(content, "export default")
          %{name: if(name == "", do: nil, else: name), line: line, type: :default_export}

        [_full] ->
          line = find_line_number(content, "export default")
          %{name: nil, line: line, type: :default_export}
      end)

    exports ++ named ++ default
  end

  defp extract_interfaces(content) do
    # Match TypeScript interfaces: interface Name extends Base
    ~r/(?:export\s+)?interface\s+(\w+)(?:\s+extends\s+([\w,\s]+))?/m
    |> Regex.scan(content)
    |> Enum.map(fn
      [_full, name] ->
        line = find_line_number(content, "interface #{name}")
        %{name: name, extends: [], line: line, type: :interface}

      [_full, name, extends] ->
        line = find_line_number(content, "interface #{name}")

        ext_list =
          extends
          |> String.split(",")
          |> Enum.map(&String.trim/1)

        %{name: name, extends: ext_list, line: line, type: :interface}
    end)
  end

  defp extract_type_aliases(content) do
    # Match TypeScript type aliases: type Name = ...
    ~r/(?:export\s+)?type\s+(\w+)(?:<[^>]+>)?\s*=/m
    |> Regex.scan(content)
    |> Enum.map(fn [_full, name] ->
      line = find_line_number(content, "type #{name}")
      %{name: name, line: line, type: :type_alias}
    end)
  end

  defp parse_args(args) do
    args
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn arg ->
      # Handle TypeScript type annotations and defaults
      arg = String.replace(arg, ~r/:\s*[^=,]+/, "")

      case String.split(arg, "=", parts: 2) do
        [name, default] ->
          %{name: String.trim(name), default: String.trim(default)}

        [name] ->
          %{name: String.trim(name), default: nil}
      end
    end)
  end

  defp parse_import_names(names) do
    names
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_import_name/1)
  end

  defp parse_import_name(name) do
    case String.split(name, ~r/\s+as\s+/) do
      [orig, alias_name] -> %{name: orig, alias: alias_name}
      [orig] -> %{name: orig, alias: nil}
    end
  end

  defp find_line_number(content, pattern) do
    content
    |> String.split("\n")
    |> Enum.find_index(&String.contains?(&1, pattern))
    |> case do
      nil -> 0
      idx -> idx + 1
    end
  end
end
