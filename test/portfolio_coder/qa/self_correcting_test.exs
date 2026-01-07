defmodule PortfolioCoder.QA.SelfCorrectingTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Indexer.InMemorySearch
  alias PortfolioCoder.QA.SelfCorrecting

  @sample_docs [
    %{
      id: "auth.ex:1",
      content: """
      defmodule MyApp.Auth do
        @moduledoc "Authentication module"
        def authenticate(user, password), do: {:ok, user}
        def logout(user), do: :ok
      end
      """,
      metadata: %{path: "lib/my_app/auth.ex", language: :elixir}
    },
    %{
      id: "session.ex:1",
      content: """
      defmodule MyApp.Session do
        @moduledoc "Session management"
        def create(user), do: {:ok, "token"}
        def destroy(token), do: :ok
      end
      """,
      metadata: %{path: "lib/my_app/session.ex", language: :elixir}
    }
  ]

  setup do
    {:ok, index} = InMemorySearch.new()
    :ok = InMemorySearch.add_all(index, @sample_docs)
    {:ok, index: index}
  end

  describe "new/1" do
    test "creates self-correcting QA instance", %{index: index} do
      qa = SelfCorrecting.new(index)

      assert is_struct(qa, SelfCorrecting)
      assert qa.index == index
      assert qa.max_iterations == 2
    end

    test "accepts configuration options", %{index: index} do
      qa =
        SelfCorrecting.new(index,
          max_iterations: 3,
          confidence_threshold: 0.9
        )

      assert qa.max_iterations == 3
      assert qa.confidence_threshold == 0.9
    end
  end

  describe "critique/2" do
    test "returns critique structure" do
      answer = "The authentication module handles user login."
      question = "How does authentication work?"

      critique = SelfCorrecting.critique(answer, question, context_summary: "auth.ex")

      assert is_map(critique)
      assert Map.has_key?(critique, :is_sufficient)
      assert Map.has_key?(critique, :confidence)
      assert Map.has_key?(critique, :missing_aspects)
      assert is_boolean(critique.is_sufficient)
      assert is_number(critique.confidence)
      assert is_list(critique.missing_aspects)
    end

    test "returns default critique without LLM" do
      critique = SelfCorrecting.critique("answer", "question")

      # Without LLM, should return conservative default
      assert critique.confidence >= 0.0
      assert critique.confidence <= 1.0
    end
  end

  describe "parse_critique_response/1" do
    test "parses valid JSON response" do
      response = """
      {"is_sufficient": true, "missing_aspects": [], "confidence": 0.9}
      """

      critique = SelfCorrecting.parse_critique_response(response)

      assert critique.is_sufficient == true
      assert critique.missing_aspects == []
      assert critique.confidence == 0.9
    end

    test "parses JSON embedded in text" do
      response = """
      Based on my analysis:
      {"is_sufficient": false, "missing_aspects": ["error handling"], "confidence": 0.6}
      The answer needs more detail.
      """

      critique = SelfCorrecting.parse_critique_response(response)

      assert critique.is_sufficient == false
      assert "error handling" in critique.missing_aspects
    end

    test "returns default for invalid JSON" do
      response = "not valid json"

      critique = SelfCorrecting.parse_critique_response(response)

      # Should return safe defaults
      assert is_boolean(critique.is_sufficient)
      assert is_number(critique.confidence)
      assert is_list(critique.missing_aspects)
    end
  end

  describe "should_refine?/2" do
    test "returns true for low confidence" do
      qa = SelfCorrecting.new(nil, confidence_threshold: 0.8)
      critique = %{is_sufficient: false, confidence: 0.5, missing_aspects: ["detail"]}

      assert SelfCorrecting.should_refine?(qa, critique) == true
    end

    test "returns false for high confidence" do
      qa = SelfCorrecting.new(nil, confidence_threshold: 0.8)
      critique = %{is_sufficient: true, confidence: 0.95, missing_aspects: []}

      assert SelfCorrecting.should_refine?(qa, critique) == false
    end

    test "returns true when not sufficient" do
      qa = SelfCorrecting.new(nil, confidence_threshold: 0.8)
      critique = %{is_sufficient: false, confidence: 0.85, missing_aspects: ["tests"]}

      assert SelfCorrecting.should_refine?(qa, critique) == true
    end
  end

  describe "retrieve_additional_context/3" do
    test "retrieves context for missing aspects", %{index: index} do
      qa = SelfCorrecting.new(index)
      missing = ["authentication", "session"]

      {:ok, context} = SelfCorrecting.retrieve_additional_context(qa, missing)

      assert is_list(context.documents)
    end

    test "handles empty missing aspects", %{index: index} do
      qa = SelfCorrecting.new(index)

      {:ok, context} = SelfCorrecting.retrieve_additional_context(qa, [])

      assert context.documents == []
    end
  end

  describe "ask/2 (without LLM)" do
    test "returns result with iteration info", %{index: index} do
      qa = SelfCorrecting.new(index, llm_module: nil)

      {:ok, result} = SelfCorrecting.ask(qa, "How does authentication work?")

      assert is_map(result)
      assert Map.has_key?(result, :question)
      assert Map.has_key?(result, :iterations)
      assert Map.has_key?(result, :final_confidence)
    end

    test "retrieves context", %{index: index} do
      qa = SelfCorrecting.new(index, llm_module: nil)

      {:ok, result} = SelfCorrecting.ask(qa, "auth module")

      assert Map.has_key?(result, :context)
      assert Map.has_key?(result, :sources)
    end
  end

  describe "config/0" do
    test "returns default configuration" do
      config = SelfCorrecting.config()

      assert is_map(config)
      assert Map.has_key?(config, :max_iterations)
      assert Map.has_key?(config, :confidence_threshold)
    end
  end

  describe "with_max_iterations/2" do
    test "sets max iterations", %{index: index} do
      qa =
        SelfCorrecting.new(index)
        |> SelfCorrecting.with_max_iterations(5)

      assert qa.max_iterations == 5
    end
  end

  describe "with_confidence_threshold/2" do
    test "sets confidence threshold", %{index: index} do
      qa =
        SelfCorrecting.new(index)
        |> SelfCorrecting.with_confidence_threshold(0.95)

      assert qa.confidence_threshold == 0.95
    end
  end
end
