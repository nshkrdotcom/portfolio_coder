defmodule PortfolioCoder.Agent.Session do
  @moduledoc """
  Agent session management for maintaining conversation state.

  A session tracks:
  - Conversation history (messages)
  - Tool context (index, graph)
  - Session metadata
  """

  @type message :: %{
          role: :user | :assistant | :tool_call | :tool_result,
          content: String.t() | map()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          messages: [message()],
          context: map(),
          metadata: map(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    messages: [],
    context: %{},
    metadata: %{},
    created_at: nil,
    updated_at: nil
  ]

  @doc """
  Create a new session.

  Options:
    - `:index` - The search index to use
    - `:graph` - The code graph to use
    - `:cwd` - Current working directory
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      id: generate_id(),
      messages: [],
      context: %{
        index: opts[:index],
        graph: opts[:graph],
        cwd: opts[:cwd] || File.cwd!()
      },
      metadata: %{
        tool_calls: 0,
        tokens_used: 0
      },
      created_at: now,
      updated_at: now
    }
  end

  @doc """
  Add a user message to the session.
  """
  @spec add_user_message(t(), String.t()) :: t()
  def add_user_message(session, content) do
    message = %{role: :user, content: content}
    add_message(session, message)
  end

  @doc """
  Add an assistant message to the session.
  """
  @spec add_assistant_message(t(), String.t()) :: t()
  def add_assistant_message(session, content) do
    message = %{role: :assistant, content: content}
    add_message(session, message)
  end

  @doc """
  Add a tool call to the session.
  """
  @spec add_tool_call(t(), atom(), map()) :: t()
  def add_tool_call(session, tool_name, params) do
    message = %{role: :tool_call, content: %{tool: tool_name, params: params}}

    session
    |> add_message(message)
    |> update_metadata(:tool_calls, &(&1 + 1))
  end

  @doc """
  Add a tool result to the session.
  """
  @spec add_tool_result(t(), atom(), term()) :: t()
  def add_tool_result(session, tool_name, result) do
    message = %{role: :tool_result, content: %{tool: tool_name, result: result}}
    add_message(session, message)
  end

  @doc """
  Get the conversation history formatted for LLM.
  """
  @spec get_history(t()) :: [map()]
  def get_history(session) do
    session.messages
    |> Enum.map(fn msg ->
      case msg.role do
        :user ->
          %{role: "user", content: msg.content}

        :assistant ->
          %{role: "assistant", content: msg.content}

        :tool_call ->
          %{role: "assistant", content: "[Tool call: #{msg.content.tool}]"}

        :tool_result ->
          %{role: "assistant", content: "[Tool result: #{inspect(msg.content.result)}]"}
      end
    end)
  end

  @doc """
  Get the tool context for tool execution.
  """
  @spec get_tool_context(t()) :: map()
  def get_tool_context(session) do
    Map.merge(session.context, %{metadata: session.metadata})
  end

  @doc """
  Update the session context (index, graph, etc).
  """
  @spec update_context(t(), atom(), term()) :: t()
  def update_context(session, key, value) do
    context = Map.put(session.context, key, value)
    %{session | context: context, updated_at: DateTime.utc_now()}
  end

  @doc """
  Get the last N messages.
  """
  @spec recent_messages(t(), non_neg_integer()) :: [message()]
  def recent_messages(session, n) do
    session.messages
    |> Enum.reverse()
    |> Enum.take(n)
    |> Enum.reverse()
  end

  # Private helpers

  defp add_message(session, message) do
    %{session | messages: session.messages ++ [message], updated_at: DateTime.utc_now()}
  end

  defp update_metadata(session, key, fun) do
    value = Map.get(session.metadata, key, 0)
    metadata = Map.put(session.metadata, key, fun.(value))
    %{session | metadata: metadata}
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
