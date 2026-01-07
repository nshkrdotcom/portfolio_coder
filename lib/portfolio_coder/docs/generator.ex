defmodule PortfolioCoder.Docs.Generator do
  @moduledoc """
  Documentation generator for code.

  Generates documentation in various formats (Markdown, HTML) from
  source code, including module docs, function docs, and API references.

  ## Usage

      {:ok, index} = InMemorySearch.new()
      {:ok, graph} = InMemoryGraph.new()
      # ... populate index and graph ...

      gen = Generator.new(index, graph)

      # Generate module documentation
      {:ok, doc} = Generator.generate_module_doc(gen, "MyApp.Parser")

      # Generate API docs for multiple modules
      {:ok, docs} = Generator.generate_api_docs(gen, ["MyApp.Parser", "MyApp.Utils"])

      # Generate README template
      {:ok, readme} = Generator.generate_readme(gen)
  """

  alias PortfolioCoder.Indexer.InMemorySearch

  defstruct [
    :index,
    :graph,
    :format,
    :include_private,
    :include_examples,
    :project_name
  ]

  @type t :: %__MODULE__{
          index: pid(),
          graph: pid(),
          format: :markdown | :html | :text,
          include_private: boolean(),
          include_examples: boolean(),
          project_name: String.t()
        }

  @default_config %{
    format: :markdown,
    include_private: false,
    include_examples: true,
    project_name: "Project"
  }

  @doc """
  Create a new documentation generator.

  ## Options

    * `:format` - Output format (default: :markdown)
    * `:include_private` - Include private functions (default: false)
    * `:include_examples` - Include code examples (default: true)
    * `:project_name` - Project name for README (default: "Project")
  """
  @spec new(pid(), pid(), keyword()) :: t()
  def new(index, graph, opts \\ []) do
    %__MODULE__{
      index: index,
      graph: graph,
      format: Keyword.get(opts, :format, :markdown),
      include_private: Keyword.get(opts, :include_private, false),
      include_examples: Keyword.get(opts, :include_examples, true),
      project_name: Keyword.get(opts, :project_name, "Project")
    }
  end

  @doc """
  Generate documentation for a module.
  """
  @spec generate_module_doc(t(), String.t()) :: {:ok, String.t()}
  def generate_module_doc(%__MODULE__{} = gen, module_name) do
    {:ok, results} = InMemorySearch.search(gen.index, module_name, limit: 10)

    module_content =
      Enum.find(results, &String.contains?(&1.content, "defmodule #{module_name}"))

    if module_content do
      doc = build_module_doc(module_name, module_content.content, gen)
      {:ok, format_output(doc, gen.format)}
    else
      {:ok, "# #{module_name}\n\nNo documentation found."}
    end
  end

  @doc """
  Generate documentation for a specific function.
  """
  @spec generate_function_doc(t(), String.t(), String.t()) :: {:ok, String.t()}
  def generate_function_doc(%__MODULE__{} = gen, module_name, function_name) do
    {:ok, results} =
      InMemorySearch.search(gen.index, "#{module_name} #{function_name}", limit: 10)

    module_content =
      Enum.find(results, &String.contains?(&1.content, "defmodule #{module_name}"))

    if module_content do
      doc = build_function_doc(module_name, function_name, module_content.content)
      {:ok, format_output(doc, gen.format)}
    else
      {:ok, "## #{function_name}\n\nNo documentation found."}
    end
  end

  @doc """
  Generate API documentation for multiple modules.
  """
  @spec generate_api_docs(t(), [String.t()]) :: {:ok, [map()]}
  def generate_api_docs(%__MODULE__{} = gen, module_names) do
    docs =
      Enum.map(module_names, fn name ->
        {:ok, doc} = generate_module_doc(gen, name)
        %{module: name, doc: doc}
      end)

    {:ok, docs}
  end

  @doc """
  Extract type specifications from a module.
  """
  @spec extract_type_specs(t(), String.t()) :: {:ok, [map()]}
  def extract_type_specs(%__MODULE__{} = gen, module_name) do
    {:ok, results} = InMemorySearch.search(gen.index, module_name, limit: 10)

    module_content =
      Enum.find(results, &String.contains?(&1.content, "defmodule #{module_name}"))

    specs =
      if module_content do
        extract_specs(module_content.content)
      else
        []
      end

    {:ok, specs}
  end

  @doc """
  Generate a README template.
  """
  @spec generate_readme(t()) :: {:ok, String.t()}
  def generate_readme(%__MODULE__{} = gen) do
    readme = """
    # #{gen.project_name}

    ## Installation

    Add `#{String.downcase(gen.project_name)}` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [
        {:#{String.downcase(gen.project_name)}, "~> 0.1.0"}
      ]
    end
    ```

    ## Usage

    ```elixir
    # Add usage examples here
    ```

    ## Documentation

    Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc).

    ## License

    MIT
    """

    {:ok, readme}
  end

  @doc """
  Generate a changelog entry.
  """
  @spec generate_changelog_entry(t(), [map()]) :: {:ok, String.t()}
  def generate_changelog_entry(%__MODULE__{} = _gen, changes) do
    date = Date.utc_today() |> Date.to_string()

    sections =
      changes
      |> Enum.group_by(& &1.type)
      |> Enum.map_join("\n\n", fn {type, items} ->
        header = format_change_type(type)
        items_text = Enum.map_join(items, "\n", fn i -> "- #{i.description}" end)
        "### #{header}\n\n#{items_text}"
      end)

    entry = """
    ## [Unreleased] - #{date}

    #{sections}
    """

    {:ok, entry}
  end

  @doc """
  Format output content into specified format.
  """
  @spec format_output(map() | String.t(), atom()) :: String.t()
  def format_output(content, :markdown) when is_map(content) do
    """
    # #{content.title}

    #{content.body}
    """
  end

  def format_output(content, :html) when is_map(content) do
    """
    <!DOCTYPE html>
    <html>
    <head><title>#{content.title}</title></head>
    <body>
    <h1>#{content.title}</h1>
    #{content.body}
    </body>
    </html>
    """
  end

  def format_output(content, :text) when is_map(content) do
    """
    #{content.title}
    #{String.duplicate("=", String.length(content.title))}

    #{content.body}
    """
  end

  def format_output(content, _format) when is_binary(content) do
    content
  end

  @doc """
  Get default configuration.
  """
  @spec config() :: map()
  def config do
    @default_config
  end

  # Private functions

  defp build_module_doc(module_name, content, gen) do
    moduledoc = extract_moduledoc(content)
    functions = extract_public_functions(content, gen.include_private)

    functions_doc =
      if Enum.empty?(functions) do
        ""
      else
        """

        ## Functions

        #{Enum.map_join(functions, "\n", &format_function_summary/1)}
        """
      end

    """
    # #{module_name}

    #{moduledoc || "No module documentation."}
    #{functions_doc}
    """
  end

  defp build_function_doc(module_name, function_name, content) do
    # Find function definition
    case Regex.run(~r/def\s+#{function_name}\s*\(([^)]*)\)/, content) do
      [_, args] ->
        arity = count_args(args)

        """
        ## #{module_name}.#{function_name}/#{arity}

        ```elixir
        #{function_name}(#{args})
        ```
        """

      _ ->
        "## #{function_name}\n\nFunction not found."
    end
  end

  defp extract_moduledoc(content) do
    case Regex.run(~r/@moduledoc\s+(?:~[sS])?["']{3}([\s\S]*?)["']{3}/, content) do
      [_, doc] ->
        String.trim(doc)

      _ ->
        case Regex.run(~r/@moduledoc\s+"([^"]+)"/, content) do
          [_, doc] -> doc
          _ -> nil
        end
    end
  end

  defp extract_public_functions(content, include_private) do
    pattern =
      if include_private do
        ~r/def(p)?\s+(\w+)\s*\(([^)]*)\)/
      else
        ~r/def\s+(\w+)\s*\(([^)]*)\)/
      end

    Regex.scan(pattern, content)
    |> Enum.map(fn
      [_, name, args] ->
        %{name: name, arity: count_args(args), visibility: :public}

      [_, "p", name, args] ->
        %{name: name, arity: count_args(args), visibility: :private}
    end)
    |> Enum.uniq_by(&{&1.name, &1.arity})
  end

  defp extract_specs(content) do
    Regex.scan(~r/@spec\s+(\w+)\s*\(([^)]*)\)\s*::\s*([^\n]+)/, content)
    |> Enum.map(fn [_, name, args, return] ->
      %{
        function: name,
        args: String.trim(args),
        return: String.trim(return)
      }
    end)
  end

  defp format_function_summary(func) do
    visibility = if func.visibility == :private, do: " (private)", else: ""
    "- `#{func.name}/#{func.arity}`#{visibility}"
  end

  defp count_args(""), do: 0
  defp count_args(args), do: args |> String.split(",") |> Enum.count()

  defp format_change_type(:added), do: "Added"
  defp format_change_type(:changed), do: "Changed"
  defp format_change_type(:deprecated), do: "Deprecated"
  defp format_change_type(:removed), do: "Removed"
  defp format_change_type(:fixed), do: "Fixed"
  defp format_change_type(:security), do: "Security"
  defp format_change_type(other), do: to_string(other) |> String.capitalize()
end
