defmodule PortfolioCoder.Tools do
  @moduledoc """
  Code-specific tools for the agent framework.

  Registers tools that can be used by agents for code-related tasks
  like searching, reading, and analyzing code.
  """

  alias PortfolioCoder.Tools.{AnalyzeCode, ListFiles, ReadFile, SearchCode}

  require Logger

  @doc """
  Register all code-specific tools with the agent framework.

  If PortfolioManager.Agent.ToolRegistry is available, registers the tools
  with it. Otherwise, logs a debug message and continues.
  """
  @spec register_all() :: :ok
  def register_all do
    case Code.ensure_loaded(PortfolioManager.Agent.ToolRegistry) do
      {:module, registry} ->
        register_with_registry(registry)

      {:error, _} ->
        Logger.debug("ToolRegistry not available, skipping tool registration")
        :ok
    end
  end

  defp register_with_registry(registry) do
    tools = [
      SearchCode.definition(),
      ReadFile.definition(),
      ListFiles.definition(),
      AnalyzeCode.definition()
    ]

    Enum.each(tools, fn tool ->
      case registry.register(tool) do
        :ok ->
          Logger.debug("Registered tool: #{tool.name}")

        {:error, reason} ->
          Logger.warning("Failed to register tool #{tool.name}: #{inspect(reason)}")
      end
    end)

    :ok
  rescue
    e ->
      Logger.warning("Tool registration failed: #{inspect(e)}")
      :ok
  end

  @doc """
  Get all available code tools.
  """
  @spec list_tools() :: [map()]
  def list_tools do
    [
      SearchCode.definition(),
      ReadFile.definition(),
      ListFiles.definition(),
      AnalyzeCode.definition()
    ]
  end

  @doc """
  Execute a tool by name with the given arguments.
  """
  @spec execute(String.t(), map()) :: {:ok, any()} | {:error, term()}
  def execute("search_code", args), do: SearchCode.execute(args)
  def execute("read_file", args), do: ReadFile.execute(args)
  def execute("list_files", args), do: ListFiles.execute(args)
  def execute("analyze_code", args), do: AnalyzeCode.execute(args)
  def execute(name, _args), do: {:error, {:unknown_tool, name}}
end
