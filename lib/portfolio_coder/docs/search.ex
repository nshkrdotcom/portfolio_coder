defmodule PortfolioCoder.Docs.Search do
  @moduledoc """
  Documentation search functionality.

  Provides specialized search for documentation content, including
  module docs, function docs, and code examples.

  ## Usage

      {:ok, index} = InMemorySearch.new()
      # ... populate index ...

      search = Search.new(index)

      # Search documentation
      {:ok, results} = Search.search_docs(search, "authentication")

      # Search for modules
      {:ok, modules} = Search.search_modules(search, "Parser")

      # Get module summary
      {:ok, summary} = Search.get_module_summary(search, "MyApp.Parser")
  """

  alias PortfolioCoder.Indexer.InMemorySearch

  defstruct [
    :index,
    :max_results,
    :include_code,
    :include_private
  ]

  @type t :: %__MODULE__{
          index: pid(),
          max_results: pos_integer(),
          include_code: boolean(),
          include_private: boolean()
        }

  @default_config %{
    max_results: 20,
    include_code: true,
    include_private: false
  }

  @doc """
  Create a new documentation search instance.

  ## Options

    * `:max_results` - Maximum results to return (default: 20)
    * `:include_code` - Include code snippets (default: true)
    * `:include_private` - Include private functions (default: false)
  """
  @spec new(pid(), keyword()) :: t()
  def new(index, opts \\ []) do
    %__MODULE__{
      index: index,
      max_results: Keyword.get(opts, :max_results, 20),
      include_code: Keyword.get(opts, :include_code, true),
      include_private: Keyword.get(opts, :include_private, false)
    }
  end

  @doc """
  Search through all documentation content.
  """
  @spec search_docs(t(), String.t()) :: {:ok, [map()]}
  def search_docs(%__MODULE__{} = search, query) do
    {:ok, results} = InMemorySearch.search(search.index, query, limit: search.max_results)

    docs =
      results
      |> Enum.filter(&has_documentation?/1)
      |> Enum.map(&extract_doc_result/1)

    {:ok, docs}
  end

  @doc """
  Search for modules by name.
  """
  @spec search_modules(t(), String.t()) :: {:ok, [map()]}
  def search_modules(%__MODULE__{} = search, query) do
    {:ok, results} =
      InMemorySearch.search(search.index, "defmodule #{query}", limit: search.max_results)

    modules =
      results
      |> Enum.filter(&has_defmodule?/1)
      |> Enum.map(&extract_module_result/1)
      |> Enum.uniq_by(& &1.name)

    {:ok, modules}
  end

  @doc """
  Search for functions by name.
  """
  @spec search_functions(t(), String.t()) :: {:ok, [map()]}
  def search_functions(%__MODULE__{} = search, query) do
    {:ok, results} =
      InMemorySearch.search(search.index, "def #{query}", limit: search.max_results)

    functions =
      results
      |> Enum.flat_map(&extract_functions/1)
      |> Enum.filter(fn f -> String.contains?(f.name, query) end)
      |> Enum.uniq_by(&{&1.module, &1.name, &1.arity})

    {:ok, functions}
  end

  @doc """
  Search for code examples in documentation.
  """
  @spec search_examples(t(), String.t()) :: {:ok, [map()]}
  def search_examples(%__MODULE__{} = search, query) do
    {:ok, results} = InMemorySearch.search(search.index, query, limit: search.max_results)

    examples =
      results
      |> Enum.flat_map(&extract_examples/1)
      |> Enum.filter(fn e -> String.contains?(e.code, query) end)

    {:ok, examples}
  end

  @doc """
  Suggest completions for a partial query.
  """
  @spec suggest_completion(t(), String.t()) :: {:ok, [String.t()]}
  def suggest_completion(%__MODULE__{} = search, partial) do
    # Search for matching terms
    {:ok, results} = InMemorySearch.search(search.index, partial, limit: 50)

    suggestions =
      results
      |> Enum.flat_map(fn r ->
        # Extract words that start with the partial
        Regex.scan(~r/\b(#{Regex.escape(partial)}\w*)/i, r.content)
        |> Enum.map(fn [_, word] -> word end)
      end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_, count} -> -count end)
      |> Enum.take(10)
      |> Enum.map(fn {word, _} -> word end)

    {:ok, suggestions}
  end

  @doc """
  Get a summary of a module's documentation.
  """
  @spec get_module_summary(t(), String.t()) :: {:ok, map()}
  def get_module_summary(%__MODULE__{} = search, module_name) do
    {:ok, results} = InMemorySearch.search(search.index, module_name, limit: 10)

    module_content =
      Enum.find(results, &String.contains?(&1.content, "defmodule #{module_name}"))

    summary =
      if module_content do
        %{
          module: module_name,
          description: extract_moduledoc(module_content.content),
          path: module_content.metadata[:path] || module_content.id,
          functions: count_public_functions(module_content.content),
          has_examples: has_examples?(module_content.content)
        }
      else
        %{
          module: module_name,
          description: nil,
          path: nil,
          functions: 0,
          has_examples: false
        }
      end

    {:ok, summary}
  end

  @doc """
  Get documentation for a specific function.
  """
  @spec get_function_doc(t(), String.t(), String.t()) :: {:ok, map()}
  def get_function_doc(%__MODULE__{} = search, module_name, function_name) do
    {:ok, results} =
      InMemorySearch.search(search.index, "#{module_name} #{function_name}", limit: 10)

    module_content =
      Enum.find(results, &String.contains?(&1.content, "defmodule #{module_name}"))

    doc =
      if module_content do
        extract_function_doc(module_content.content, function_name)
      else
        %{
          function: function_name,
          module: module_name,
          description: nil,
          arity: nil
        }
      end

    {:ok, doc}
  end

  @doc """
  List all documented modules.
  """
  @spec list_modules(t()) :: {:ok, [map()]}
  def list_modules(%__MODULE__{} = search) do
    {:ok, results} = InMemorySearch.search(search.index, "defmodule", limit: 100)

    modules =
      results
      |> Enum.filter(&has_defmodule?/1)
      |> Enum.map(&extract_module_result/1)
      |> Enum.uniq_by(& &1.name)
      |> Enum.sort_by(& &1.name)

    {:ok, modules}
  end

  @doc """
  Get default configuration.
  """
  @spec config() :: map()
  def config do
    @default_config
  end

  # Private functions

  defp has_documentation?(result) do
    content = result.content
    String.contains?(content, "@moduledoc") or String.contains?(content, "@doc")
  end

  defp has_defmodule?(result) do
    String.contains?(result.content, "defmodule ")
  end

  defp extract_doc_result(result) do
    content = result.content

    %{
      path: result.metadata[:path] || result.id,
      type: result.metadata[:type],
      excerpt: extract_excerpt(content),
      has_moduledoc: String.contains?(content, "@moduledoc"),
      has_function_docs: String.contains?(content, "@doc")
    }
  end

  defp extract_module_result(result) do
    content = result.content

    module_name =
      case Regex.run(~r/defmodule\s+([A-Z][\w.]+)/, content) do
        [_, name] -> name
        _ -> "Unknown"
      end

    %{
      name: module_name,
      path: result.metadata[:path] || result.id,
      description: extract_moduledoc(content)
    }
  end

  defp extract_functions(result) do
    content = result.content
    module_name = extract_module_name(content)

    Regex.scan(~r/def\s+(\w+)\s*\(([^)]*)\)/, content)
    |> Enum.map(fn [_, name, args] ->
      %{
        name: name,
        module: module_name,
        arity: count_args(args),
        path: result.metadata[:path] || result.id
      }
    end)
  end

  defp extract_examples(result) do
    content = result.content
    path = result.metadata[:path] || result.id

    # Extract iex examples
    iex_examples =
      Regex.scan(~r/iex>\s*(.+)/, content)
      |> Enum.map(fn [_, code] -> %{type: :iex, code: code, path: path} end)

    # Extract code blocks
    code_blocks =
      Regex.scan(~r/```\w*\n([\s\S]*?)```/, content)
      |> Enum.map(fn [_, code] -> %{type: :code_block, code: String.trim(code), path: path} end)

    iex_examples ++ code_blocks
  end

  defp extract_moduledoc(content) do
    case Regex.run(~r/@moduledoc\s+(?:~[sS])?["']{3}([\s\S]*?)["']{3}/, content) do
      [_, doc] ->
        doc |> String.trim() |> String.split("\n") |> hd()

      _ ->
        case Regex.run(~r/@moduledoc\s+"([^"]+)"/, content) do
          [_, doc] -> doc
          _ -> nil
        end
    end
  end

  defp extract_module_name(content) do
    case Regex.run(~r/defmodule\s+([A-Z][\w.]+)/, content) do
      [_, name] -> name
      _ -> "Unknown"
    end
  end

  defp extract_function_doc(content, function_name) do
    # Try to find @doc before the function
    pattern = ~r/@doc\s+(?:~[sS])?["']{1,3}([^"']+)["']{1,3}\s*def\s+#{function_name}/

    description =
      case Regex.run(pattern, content) do
        [_, doc] -> String.trim(doc)
        _ -> nil
      end

    # Find function arity
    arity =
      case Regex.run(~r/def\s+#{function_name}\s*\(([^)]*)\)/, content) do
        [_, args] -> count_args(args)
        _ -> nil
      end

    %{
      function: function_name,
      description: description,
      arity: arity
    }
  end

  defp extract_excerpt(content) do
    content
    |> String.replace(~r/\s+/, " ")
    |> String.slice(0, 200)
  end

  defp count_public_functions(content) do
    length(Regex.scan(~r/def\s+\w+/, content))
  end

  defp has_examples?(content) do
    String.contains?(content, "iex>") or String.contains?(content, "```")
  end

  defp count_args(""), do: 0
  defp count_args(args), do: args |> String.split(",") |> Enum.count()
end
