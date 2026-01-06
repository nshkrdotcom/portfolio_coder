defmodule PortfolioCoder.Agent.SessionTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Agent.Session

  describe "new/1" do
    test "creates a new session with default values" do
      session = Session.new()

      assert is_binary(session.id)
      assert session.messages == []
      assert session.context.cwd != nil
      assert session.metadata.tool_calls == 0
      assert session.created_at != nil
      assert session.updated_at != nil
    end

    test "accepts index and graph options" do
      session = Session.new(index: :my_index, graph: :my_graph, cwd: "/test")

      assert session.context.index == :my_index
      assert session.context.graph == :my_graph
      assert session.context.cwd == "/test"
    end
  end

  describe "add_user_message/2" do
    test "adds a user message to the session" do
      session =
        Session.new()
        |> Session.add_user_message("Hello")

      assert length(session.messages) == 1
      assert hd(session.messages).role == :user
      assert hd(session.messages).content == "Hello"
    end
  end

  describe "add_assistant_message/2" do
    test "adds an assistant message to the session" do
      session =
        Session.new()
        |> Session.add_assistant_message("Hi there!")

      assert length(session.messages) == 1
      assert hd(session.messages).role == :assistant
      assert hd(session.messages).content == "Hi there!"
    end
  end

  describe "add_tool_call/3" do
    test "adds a tool call and increments counter" do
      session =
        Session.new()
        |> Session.add_tool_call(:search_code, %{query: "test"})

      assert length(session.messages) == 1
      assert hd(session.messages).role == :tool_call
      assert hd(session.messages).content.tool == :search_code
      assert session.metadata.tool_calls == 1
    end

    test "increments tool call counter on multiple calls" do
      session =
        Session.new()
        |> Session.add_tool_call(:search_code, %{})
        |> Session.add_tool_call(:get_callers, %{})

      assert session.metadata.tool_calls == 2
    end
  end

  describe "add_tool_result/3" do
    test "adds a tool result to the session" do
      session =
        Session.new()
        |> Session.add_tool_result(:search_code, [%{path: "test.ex"}])

      assert length(session.messages) == 1
      assert hd(session.messages).role == :tool_result
      assert hd(session.messages).content.tool == :search_code
    end
  end

  describe "get_history/1" do
    test "formats messages for LLM" do
      session =
        Session.new()
        |> Session.add_user_message("Find auth code")
        |> Session.add_assistant_message("Here are the results")

      history = Session.get_history(session)

      assert length(history) == 2
      assert Enum.at(history, 0).role == "user"
      assert Enum.at(history, 1).role == "assistant"
    end
  end

  describe "get_tool_context/1" do
    test "returns context for tool execution" do
      session = Session.new(index: :my_index, graph: :my_graph)
      context = Session.get_tool_context(session)

      assert context.index == :my_index
      assert context.graph == :my_graph
      assert is_map(context.metadata)
    end
  end

  describe "update_context/3" do
    test "updates context values" do
      session =
        Session.new()
        |> Session.update_context(:index, :new_index)

      assert session.context.index == :new_index
    end
  end

  describe "recent_messages/2" do
    test "returns last N messages" do
      session =
        Session.new()
        |> Session.add_user_message("First")
        |> Session.add_assistant_message("Second")
        |> Session.add_user_message("Third")

      recent = Session.recent_messages(session, 2)

      assert length(recent) == 2
      assert Enum.at(recent, 0).content == "Second"
      assert Enum.at(recent, 1).content == "Third"
    end
  end
end
