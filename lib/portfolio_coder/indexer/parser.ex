defmodule PortfolioCoder.Indexer.Parser do
  @moduledoc """
  Multi-language AST parsing using Sourceror (Elixir) and regex-based parsing (others).
  Extracts: modules, functions, classes, methods, imports, exports.

  This module provides a unified API for parsing source code files across multiple
  languages and extracting structured information about the code.

  ## Supported Languages

  - **Elixir**: Full AST parsing via Sourceror
  - **Python**: Regex-based extraction
  - **JavaScript/TypeScript**: Regex-based extraction

  ## Usage

      # Parse a file
      {:ok, result} = Parser.parse("/path/to/file.ex", :elixir)

      # Extract symbols from parsed result
      symbols = Parser.extract_symbols(result)

      # Extract references (imports, uses, etc.)
      references = Parser.extract_references(result)
  """

  alias PortfolioCoder.Parsers

  @type symbol :: %{
          name: String.t(),
          type: :module | :function | :class | :method | :macro | :type | :interface,
          line: non_neg_integer(),
          visibility: :public | :private,
          arity: non_neg_integer() | nil,
          metadata: map()
        }

  @type code_reference :: %{
          type: :import | :use | :alias | :require | :from_import,
          module: String.t(),
          line: non_neg_integer(),
          metadata: map()
        }

  @type ast_result :: %{
          symbols: [symbol()],
          references: [code_reference()],
          language: atom(),
          raw: map()
        }

  @doc """
  Parse a file and extract structured information.

  ## Parameters

    - `path` - Path to the source file
    - `language` - Language atom (`:elixir`, `:python`, `:javascript`, `:typescript`)
                   If not provided, detected from file extension.

  ## Returns

    - `{:ok, ast_result()}` on success
    - `{:error, reason}` on failure
  """
  @spec parse(String.t(), atom() | nil) :: {:ok, ast_result()} | {:error, term()}
  def parse(path, language \\ nil) do
    lang = language || detect_language(path)

    with {:ok, content} <- File.read(path),
         {:ok, raw} <- Parsers.parse(content, lang) do
      result = %{
        symbols: extract_symbols(raw, lang),
        references: extract_references(raw, lang),
        language: lang,
        raw: raw
      }

      {:ok, result}
    end
  end

  @doc """
  Parse source code content directly.

  ## Parameters

    - `content` - Source code as a string
    - `language` - Language atom

  ## Returns

    - `{:ok, ast_result()}` on success
    - `{:error, reason}` on failure
  """
  @spec parse_string(String.t(), atom()) :: {:ok, ast_result()} | {:error, term()}
  def parse_string(content, language) do
    case Parsers.parse(content, language) do
      {:ok, raw} ->
        result = %{
          symbols: extract_symbols(raw, language),
          references: extract_references(raw, language),
          language: language,
          raw: raw
        }

        {:ok, result}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Extract symbols from a parsed AST result.

  Symbols include:
  - Modules (Elixir)
  - Functions/methods
  - Classes (Python, JS)
  - Macros (Elixir)
  - Interfaces (TypeScript)
  - Type aliases (TypeScript)
  """
  @spec extract_symbols(map(), atom()) :: [symbol()]
  def extract_symbols(raw, language) when is_map(raw) do
    case language do
      :elixir -> extract_elixir_symbols(raw)
      :python -> extract_python_symbols(raw)
      :javascript -> extract_js_symbols(raw)
      :typescript -> extract_js_symbols(raw)
      _ -> []
    end
  end

  def extract_symbols(result) when is_map(result) do
    extract_symbols(result.raw, result.language)
  end

  @doc """
  Extract references from a parsed AST result.

  References include:
  - Imports
  - Uses (Elixir)
  - Aliases (Elixir)
  - Requires (Elixir)
  - From imports (Python)
  """
  @spec extract_references(map(), atom()) :: [code_reference()]
  def extract_references(raw, language) when is_map(raw) do
    case language do
      :elixir -> extract_elixir_references(raw)
      :python -> extract_python_references(raw)
      :javascript -> extract_js_references(raw)
      :typescript -> extract_js_references(raw)
      _ -> []
    end
  end

  def extract_references(result) when is_map(result) do
    extract_references(result.raw, result.language)
  end

  # Elixir symbol extraction

  defp extract_elixir_symbols(raw) do
    modules = Map.get(raw, :modules, [])
    functions = Map.get(raw, :functions, [])
    macros = Map.get(raw, :macros, [])

    module_symbols =
      Enum.map(modules, fn m ->
        %{
          name: m.name,
          type: :module,
          line: m.line,
          visibility: :public,
          arity: nil,
          metadata: %{}
        }
      end)

    function_symbols =
      Enum.map(functions, fn f ->
        %{
          name: "#{f.name}/#{f.arity}",
          type: :function,
          line: f.line,
          visibility: f.visibility,
          arity: f.arity,
          metadata: %{name: f.name}
        }
      end)

    macro_symbols =
      Enum.map(macros, fn m ->
        %{
          name: "#{m.name}/#{m.arity}",
          type: :macro,
          line: m.line,
          visibility: m.visibility,
          arity: m.arity,
          metadata: %{name: m.name}
        }
      end)

    module_symbols ++ function_symbols ++ macro_symbols
  end

  defp extract_elixir_references(raw) do
    imports = Map.get(raw, :imports, [])
    uses = Map.get(raw, :uses, [])
    aliases = Map.get(raw, :aliases, [])

    import_refs =
      Enum.map(imports, fn i ->
        %{
          type: :import,
          module: i.module,
          line: i.line,
          metadata: %{}
        }
      end)

    use_refs =
      Enum.map(uses, fn u ->
        %{
          type: :use,
          module: u.module,
          line: u.line,
          metadata: %{}
        }
      end)

    alias_refs =
      Enum.map(aliases, fn a ->
        %{
          type: :alias,
          module: a.module,
          line: a.line,
          metadata: %{as: a.as}
        }
      end)

    import_refs ++ use_refs ++ alias_refs
  end

  # Python symbol extraction

  defp extract_python_symbols(raw) do
    classes = Map.get(raw, :classes, [])
    functions = Map.get(raw, :functions, [])

    class_symbols =
      Enum.map(classes, fn c ->
        %{
          name: c.name,
          type: :class,
          line: c.line,
          visibility: :public,
          arity: nil,
          metadata: %{bases: c.bases}
        }
      end)

    function_symbols =
      Enum.map(functions, fn f ->
        %{
          name: f.name,
          type: :function,
          line: f.line,
          visibility: f.visibility,
          arity: length(f.args),
          metadata: %{args: f.args, async: f.async}
        }
      end)

    class_symbols ++ function_symbols
  end

  defp extract_python_references(raw) do
    imports = Map.get(raw, :imports, [])
    from_imports = Map.get(raw, :from_imports, [])

    import_refs =
      Enum.map(imports, fn i ->
        %{
          type: :import,
          module: i.module,
          line: i.line,
          metadata: %{alias: i.alias}
        }
      end)

    from_import_refs =
      Enum.map(from_imports, fn fi ->
        %{
          type: :from_import,
          module: fi.module,
          line: fi.line,
          metadata: %{imports: fi.imports}
        }
      end)

    import_refs ++ from_import_refs
  end

  # JavaScript/TypeScript symbol extraction

  defp extract_js_symbols(raw) do
    classes = Map.get(raw, :classes, [])
    functions = Map.get(raw, :functions, [])
    arrow_functions = Map.get(raw, :arrow_functions, [])
    interfaces = Map.get(raw, :interfaces, [])
    types = Map.get(raw, :types, [])

    class_symbols =
      Enum.map(classes, fn c ->
        %{
          name: c.name,
          type: :class,
          line: c.line,
          visibility: :public,
          arity: nil,
          metadata: %{extends: c.extends, implements: c.implements}
        }
      end)

    function_symbols =
      Enum.map(functions, fn f ->
        %{
          name: f.name,
          type: :function,
          line: f.line,
          visibility: :public,
          arity: length(f.args),
          metadata: %{args: f.args, async: f.async, generator: Map.get(f, :generator, false)}
        }
      end)

    arrow_symbols =
      Enum.map(arrow_functions, fn f ->
        %{
          name: f.name,
          type: :function,
          line: f.line,
          visibility: :public,
          arity: length(f.args),
          metadata: %{args: f.args, async: f.async, arrow: true}
        }
      end)

    interface_symbols =
      Enum.map(interfaces, fn i ->
        %{
          name: i.name,
          type: :interface,
          line: i.line,
          visibility: :public,
          arity: nil,
          metadata: %{extends: i.extends}
        }
      end)

    type_symbols =
      Enum.map(types, fn t ->
        %{
          name: t.name,
          type: :type,
          line: t.line,
          visibility: :public,
          arity: nil,
          metadata: %{}
        }
      end)

    class_symbols ++ function_symbols ++ arrow_symbols ++ interface_symbols ++ type_symbols
  end

  defp extract_js_references(raw) do
    imports = Map.get(raw, :imports, [])

    Enum.flat_map(imports, fn i ->
      case i.type do
        :named_import ->
          [
            %{
              type: :import,
              module: i.module,
              line: i.line,
              metadata: %{imports: i.imports}
            }
          ]

        :default_import ->
          [
            %{
              type: :import,
              module: i.module,
              line: i.line,
              metadata: %{default: i.name}
            }
          ]

        :namespace_import ->
          [
            %{
              type: :import,
              module: i.module,
              line: i.line,
              metadata: %{namespace: i.name}
            }
          ]

        :side_effect_import ->
          [
            %{
              type: :import,
              module: i.module,
              line: i.line,
              metadata: %{side_effect: true}
            }
          ]

        _ ->
          []
      end
    end)
  end

  # Language detection

  @extension_to_language %{
    ".ex" => :elixir,
    ".exs" => :elixir,
    ".py" => :python,
    ".pyw" => :python,
    ".js" => :javascript,
    ".jsx" => :javascript,
    ".mjs" => :javascript,
    ".ts" => :typescript,
    ".tsx" => :typescript
  }

  defp detect_language(path) do
    ext = Path.extname(path) |> String.downcase()
    Map.get(@extension_to_language, ext, :unknown)
  end
end
