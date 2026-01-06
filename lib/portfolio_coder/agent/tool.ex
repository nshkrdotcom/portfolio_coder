defmodule PortfolioCoder.Agent.Tool do
  @moduledoc """
  Tool behavior and registry for code agent.

  Tools are functions that the agent can invoke to gather information
  or perform actions. Each tool has:
  - A name (atom)
  - A description (for the LLM)
  - Parameter specs
  - An execution function

  ## Example

      defmodule MyTool do
        @behaviour PortfolioCoder.Agent.Tool

        @impl true
        def name, do: :my_tool

        @impl true
        def description, do: "Does something useful"

        @impl true
        def parameters do
          [
            %{name: :query, type: :string, required: true, description: "Search query"}
          ]
        end

        @impl true
        def execute(params, context) do
          {:ok, "result"}
        end
      end
  """

  @type param_spec :: %{
          name: atom(),
          type: :string | :integer | :boolean | :list,
          required: boolean(),
          description: String.t()
        }

  @type context :: %{
          graph: pid() | nil,
          index: pid() | nil,
          cwd: String.t(),
          metadata: map()
        }

  @type tool_result :: {:ok, term()} | {:error, term()}

  @callback name() :: atom()
  @callback description() :: String.t()
  @callback parameters() :: [param_spec()]
  @callback execute(params :: map(), context :: context()) :: tool_result()

  @doc """
  Convert a tool module to a map representation for LLM function calling.
  """
  @spec to_function_spec(module()) :: map()
  def to_function_spec(tool_module) do
    %{
      name: tool_module.name(),
      description: tool_module.description(),
      parameters: %{
        type: "object",
        properties:
          tool_module.parameters()
          |> Enum.map(fn p ->
            {p.name, %{type: type_to_json(p.type), description: p.description}}
          end)
          |> Map.new(),
        required:
          tool_module.parameters()
          |> Enum.filter(& &1.required)
          |> Enum.map(& &1.name)
      }
    }
  end

  defp type_to_json(:string), do: "string"
  defp type_to_json(:integer), do: "integer"
  defp type_to_json(:boolean), do: "boolean"
  defp type_to_json(:list), do: "array"
end
