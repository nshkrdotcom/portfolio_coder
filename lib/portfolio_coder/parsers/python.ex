defmodule PortfolioCoder.Parsers.Python do
  @moduledoc """
  Python source code parser using regex-based extraction.

  Extracts classes, functions, imports, and other structural elements
  from Python source code.
  """

  @doc """
  Parse Python source code and extract structure.
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, term()}
  def parse(content) do
    result = %{
      classes: extract_classes(content),
      functions: extract_functions(content),
      imports: extract_imports(content),
      from_imports: extract_from_imports(content),
      decorators: extract_decorators(content),
      docstrings: extract_docstrings(content)
    }

    {:ok, result}
  rescue
    e -> {:error, {:parse_error, e}}
  end

  @doc """
  Extract function signatures from Python code.
  """
  @spec extract_signatures(String.t()) :: {:ok, [map()]} | {:error, term()}
  def extract_signatures(content) do
    signatures =
      content
      |> extract_functions()
      |> Enum.map(fn func ->
        %{
          name: func.name,
          signature: func.signature,
          async: func.async,
          line: func.line
        }
      end)

    {:ok, signatures}
  rescue
    e -> {:error, {:parse_error, e}}
  end

  @doc """
  Extract class definitions from Python code.
  """
  @spec extract_definitions(String.t()) :: {:ok, [map()]} | {:error, term()}
  def extract_definitions(content) do
    definitions = extract_classes(content)
    {:ok, definitions}
  rescue
    e -> {:error, {:parse_error, e}}
  end

  # Private functions

  defp extract_classes(content) do
    # Match class definitions: class ClassName(bases):
    # Note: Using numbered groups to avoid alphabetical ordering issues with named captures
    ~r/^(\s*)class\s+(\w+)(?:\(([^)]*)\))?:/m
    |> Regex.scan(content)
    |> Enum.map(fn
      [_full, indent, name, bases] ->
        line = find_line_number(content, "class #{name}")

        %{
          name: name,
          bases: parse_bases(bases),
          indent: String.length(indent),
          line: line,
          type: :class
        }

      [_full, indent, name] ->
        line = find_line_number(content, "class #{name}")

        %{
          name: name,
          bases: [],
          indent: String.length(indent),
          line: line,
          type: :class
        }
    end)
  end

  defp extract_functions(content) do
    # Match function definitions: def func_name(args): or async def func_name(args):
    ~r/^(\s*)(async\s+)?def\s+(\w+)\(([^)]*)\)/m
    |> Regex.scan(content)
    |> Enum.map(fn
      [_full, indent, async, name, args] ->
        line = find_line_number(content, "def #{name}")
        is_async = async != nil and async != ""

        %{
          name: name,
          args: parse_args(args),
          signature: "#{name}(#{args})",
          async: is_async,
          indent: String.length(indent),
          visibility: if(String.starts_with?(name, "_"), do: :private, else: :public),
          line: line,
          type: :function
        }

      [_full, indent, name, args] ->
        line = find_line_number(content, "def #{name}")

        %{
          name: name,
          args: parse_args(args),
          signature: "#{name}(#{args})",
          async: false,
          indent: String.length(indent),
          visibility: if(String.starts_with?(name, "_"), do: :private, else: :public),
          line: line,
          type: :function
        }
    end)
  end

  defp extract_imports(content) do
    # Match import statements: import module or import module as alias
    ~r/^import\s+([\w.]+)(?:\s+as\s+(\w+))?/m
    |> Regex.scan(content)
    |> Enum.map(fn
      [_full, module] ->
        line = find_line_number(content, "import #{module}")
        %{module: module, alias: nil, line: line, type: :import}

      [_full, module, alias_name] ->
        line = find_line_number(content, "import #{module}")
        %{module: module, alias: alias_name, line: line, type: :import}
    end)
  end

  defp extract_from_imports(content) do
    # Match from imports: from module import name1, name2
    ~r/^from\s+([\w.]+)\s+import\s+(.+)$/m
    |> Regex.scan(content)
    |> Enum.map(fn [_full, module, names] ->
      line = find_line_number(content, "from #{module}")
      imported = parse_import_names(names)

      %{
        module: module,
        imports: imported,
        line: line,
        type: :from_import
      }
    end)
  end

  defp extract_decorators(content) do
    # Match decorators: @decorator or @decorator(args)
    ~r/^(\s*)@(\w+)(?:\(([^)]*)\))?/m
    |> Regex.scan(content)
    |> Enum.map(fn
      [_full, indent, name] ->
        line = find_line_number(content, "@#{name}")

        %{
          name: name,
          args: nil,
          indent: String.length(indent),
          line: line,
          type: :decorator
        }

      [_full, indent, name, args] ->
        line = find_line_number(content, "@#{name}")

        %{
          name: name,
          args: if(args == "", do: nil, else: args),
          indent: String.length(indent),
          line: line,
          type: :decorator
        }
    end)
  end

  defp extract_docstrings(content) do
    # Match docstrings (triple-quoted strings at the start of definitions)
    ~r/(?:class|def)\s+\w+[^:]*:\s*\n\s*"""(?<docstring>(?:[^"]|"(?!""))*)"""/m
    |> Regex.scan(content, capture: :all_names)
    |> Enum.map(fn [docstring] ->
      %{content: String.trim(docstring), type: :docstring}
    end)
  end

  defp parse_bases(nil), do: []
  defp parse_bases(""), do: []

  defp parse_bases(bases) do
    bases
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_args(args) do
    args
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn arg ->
      # Handle type hints and defaults
      case String.split(arg, "=", parts: 2) do
        [name_type, default] ->
          %{name: extract_param_name(name_type), default: String.trim(default)}

        [name_type] ->
          %{name: extract_param_name(name_type), default: nil}
      end
    end)
  end

  defp extract_param_name(name_type) do
    name_type
    |> String.split(":")
    |> List.first()
    |> String.trim()
    |> String.replace(~r/^\*+/, "")
  end

  defp parse_import_names(names) do
    # Handle multiline imports with parentheses
    names = String.replace(names, ~r/[()]/, "")

    names
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn name ->
      case String.split(name, ~r/\s+as\s+/) do
        [orig, alias_name] -> %{name: orig, alias: alias_name}
        [orig] -> %{name: orig, alias: nil}
      end
    end)
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
