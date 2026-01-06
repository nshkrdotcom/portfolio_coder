defmodule PortfolioCoder.Search.QueryEnhancerTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Search.QueryEnhancer

  # These tests use a mock LLM to avoid API calls during testing
  # The mock returns predictable responses based on the input

  defmodule MockLLM do
    @behaviour PortfolioCore.Ports.LLM

    @impl true
    def complete(messages, _opts) do
      # Extract the user message content
      user_msg = Enum.find(messages, fn m -> m.role == :user end)
      prompt = user_msg.content

      response =
        cond do
          # Query rewriting
          String.contains?(prompt, "rewrite") or String.contains?(prompt, "optimizer") ->
            cond do
              String.contains?(prompt, "Hey, how does Phoenix") ->
                "how Phoenix LiveView works"

              String.contains?(prompt, "Can you help me") ->
                "find auth code"

              String.contains?(prompt, "hello") ->
                "greeting test"

              true ->
                "rewritten query"
            end

          # Query expansion - the prompt contains the query in quotes
          String.contains?(prompt, "expand") or String.contains?(prompt, "synonyms") ->
            cond do
              String.contains?(prompt, "GenServer state") ->
                "GenServer gen_server OTP server state management Elixir"

              # The rewritten query gets passed to expand
              String.contains?(prompt, "how Phoenix LiveView works") or
                  String.contains?(prompt, "Phoenix LiveView") ->
                "how Phoenix LiveView real-time websocket interactive works"

              String.contains?(prompt, "auth middleware") ->
                "auth authentication middleware plug pipeline authorization"

              true ->
                "expanded query with synonyms"
            end

          # Query decomposition
          String.contains?(prompt, "decompose") or String.contains?(prompt, "sub-questions") ->
            cond do
              String.contains?(prompt, "Compare Elixir and Go") ->
                ~s({"sub_questions": ["What are Elixir's web service features?", "What are Go's web service features?", "How do they compare?"]})

              String.contains?(prompt, "What is pattern matching") ->
                ~s({"sub_questions": ["What is pattern matching?"]})

              String.contains?(prompt, "how Phoenix LiveView works") ->
                ~s({"sub_questions": ["how Phoenix LiveView works"]})

              true ->
                ~s({"sub_questions": ["sub question 1", "sub question 2"]})
            end

          # Code-specific rewrite
          String.contains?(prompt, "Transform") and String.contains?(prompt, "code search") ->
            "user login authentication handler"

          true ->
            "default response"
        end

      {:ok, %{content: response, model: "mock", usage: %{input_tokens: 10, output_tokens: 5}}}
    end

    @impl true
    def stream(_messages, _opts), do: {:error, :not_implemented}

    @impl true
    def supported_models, do: ["mock"]

    @impl true
    def model_info(_model), do: %{context_window: 4096, max_output: 1024, supports_tools: false}
  end

  setup do
    # Configure the mock LLM in the context
    context = %{adapters: %{llm: MockLLM}}
    %{opts: [context: context]}
  end

  describe "rewrite/2" do
    test "cleans conversational query", %{opts: opts} do
      {:ok, result} = QueryEnhancer.rewrite("Hey, how does Phoenix LiveView work?", opts)

      assert result.original == "Hey, how does Phoenix LiveView work?"
      assert result.rewritten == "how Phoenix LiveView works"
    end

    test "removes politeness markers", %{opts: opts} do
      {:ok, result} = QueryEnhancer.rewrite("Can you help me find the auth code?", opts)

      assert result.rewritten == "find auth code"
    end
  end

  describe "expand/2" do
    test "adds synonyms and related terms", %{opts: opts} do
      {:ok, result} = QueryEnhancer.expand("GenServer state", opts)

      assert result.original == "GenServer state"
      assert String.contains?(result.expanded, "OTP")
      assert String.contains?(result.expanded, "management")
      assert is_list(result.added_terms)
    end
  end

  describe "decompose/2" do
    test "breaks down comparison questions", %{opts: opts} do
      {:ok, result} = QueryEnhancer.decompose("Compare Elixir and Go for web services", opts)

      assert result.original == "Compare Elixir and Go for web services"
      assert length(result.sub_questions) > 1
      assert result.is_complex == true
    end

    test "leaves simple questions unchanged", %{opts: opts} do
      {:ok, result} = QueryEnhancer.decompose("What is pattern matching?", opts)

      assert result.sub_questions == ["What is pattern matching?"]
      assert result.is_complex == false
    end
  end

  describe "enhance/2" do
    test "runs full enhancement pipeline", %{opts: opts} do
      {:ok, result} = QueryEnhancer.enhance("Hey, how does Phoenix LiveView work?", opts)

      assert result.original == "Hey, how does Phoenix LiveView work?"
      assert result.rewritten == "how Phoenix LiveView works"
      # Verify pipeline produced an expanded result
      assert is_binary(result.expanded)
      assert result.expanded != ""
      assert is_list(result.sub_queries)
      assert is_boolean(result.is_complex)
      assert is_list(result.changes)
      assert is_list(result.added_terms)
    end

    test "can skip individual steps", %{opts: opts} do
      opts_skip = opts ++ [skip_rewrite: true, skip_expand: true]
      {:ok, result} = QueryEnhancer.enhance("test query", opts_skip)

      # Rewrite skipped - original preserved
      assert result.rewritten == "test query"
      # Expand skipped - no added terms
      assert result.expanded == "test query"
      assert result.added_terms == []
    end
  end

  describe "rewrite_for_code/2" do
    test "transforms natural language to code search terms", %{opts: opts} do
      result = QueryEnhancer.rewrite_for_code("how do we handle user login?", opts)

      assert is_binary(result)
      # The mock should return something code-relevant
      assert String.contains?(result, "login") or String.contains?(result, "user") or
               String.contains?(result, "authentication")
    end
  end

  describe "expand_with_code_terms/2" do
    test "adds programming-specific synonyms", %{opts: opts} do
      result = QueryEnhancer.expand_with_code_terms("auth middleware", opts)

      assert is_binary(result)
      # Should expand with related terms
      assert String.contains?(result, "auth")
    end
  end
end
