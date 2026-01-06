defmodule PortfolioCoder.LLM.RouterTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.LLM.Router

  describe "new/1" do
    test "creates router with fallback strategy" do
      router = Router.new(strategy: :fallback, providers: [:claude, :gpt4, :gemini])

      assert router.strategy == :fallback
      assert router.providers == [:claude, :gpt4, :gemini]
    end

    test "creates router with specialist strategy" do
      router =
        Router.new(
          strategy: :specialist,
          routing_rules: %{code: :claude, quick: :gemini}
        )

      assert router.strategy == :specialist
      assert router.routing_rules.code == :claude
    end

    test "creates router with round_robin strategy" do
      router = Router.new(strategy: :round_robin, providers: [:claude, :gpt4])

      assert router.strategy == :round_robin
    end

    test "creates router with cost_optimized strategy" do
      router =
        Router.new(
          strategy: :cost_optimized,
          providers: [:claude, :gpt4, :gemini],
          budget_per_hour: 10.0
        )

      assert router.strategy == :cost_optimized
      assert router.budget_per_hour == 10.0
    end
  end

  describe "select_provider/3 with :fallback strategy" do
    test "returns first available provider" do
      router = Router.new(strategy: :fallback, providers: [:claude, :gpt4, :gemini])

      {:ok, provider} = Router.select_provider(router, "test message", [])

      assert provider == :claude
    end

    test "skips unavailable providers" do
      router = Router.new(strategy: :fallback, providers: [:claude, :gpt4, :gemini])
      health = %{claude: :unhealthy, gpt4: :healthy, gemini: :healthy}

      {:ok, provider} = Router.select_provider(router, "test", health: health)

      assert provider == :gpt4
    end

    test "returns error when all providers unavailable" do
      router = Router.new(strategy: :fallback, providers: [:claude])
      health = %{claude: :unhealthy}

      {:error, reason} = Router.select_provider(router, "test", health: health)

      assert reason =~ "No available provider"
    end
  end

  describe "select_provider/3 with :specialist strategy" do
    test "routes code tasks to code specialist" do
      router =
        Router.new(
          strategy: :specialist,
          routing_rules: %{code: :claude, quick: :gemini, default: :gpt4}
        )

      {:ok, provider} = Router.select_provider(router, "fix this bug", task_type: :code)

      assert provider == :claude
    end

    test "routes quick tasks to quick specialist" do
      router =
        Router.new(
          strategy: :specialist,
          routing_rules: %{code: :claude, quick: :gemini, default: :gpt4}
        )

      {:ok, provider} = Router.select_provider(router, "yes or no", task_type: :quick)

      assert provider == :gemini
    end

    test "uses default for unknown task types" do
      router =
        Router.new(
          strategy: :specialist,
          routing_rules: %{code: :claude, default: :gpt4}
        )

      {:ok, provider} = Router.select_provider(router, "general question", task_type: :general)

      assert provider == :gpt4
    end

    test "infers task type from message content" do
      router =
        Router.new(
          strategy: :specialist,
          routing_rules: %{code: :claude, default: :gpt4}
        )

      {:ok, provider} =
        Router.select_provider(router, "debug this function and fix the error", [])

      # Should infer :code task type from keywords
      assert provider == :claude
    end
  end

  describe "select_provider/3 with :round_robin strategy" do
    test "cycles through providers" do
      router = Router.new(strategy: :round_robin, providers: [:a, :b, :c])

      {:ok, p1, router} = Router.select_provider_with_state(router, "msg1", [])
      {:ok, p2, router} = Router.select_provider_with_state(router, "msg2", [])
      {:ok, p3, router} = Router.select_provider_with_state(router, "msg3", [])
      {:ok, p4, _router} = Router.select_provider_with_state(router, "msg4", [])

      assert p1 == :a
      assert p2 == :b
      assert p3 == :c
      # Cycles back
      assert p4 == :a
    end
  end

  describe "select_provider/3 with :cost_optimized strategy" do
    test "prefers cheaper providers" do
      router =
        Router.new(
          strategy: :cost_optimized,
          providers: [:expensive, :cheap, :medium],
          costs: %{expensive: 0.10, cheap: 0.01, medium: 0.05}
        )

      {:ok, provider} = Router.select_provider(router, "test", [])

      assert provider == :cheap
    end

    test "respects quality threshold" do
      router =
        Router.new(
          strategy: :cost_optimized,
          providers: [:expensive, :cheap],
          costs: %{expensive: 0.10, cheap: 0.01},
          quality: %{expensive: 0.95, cheap: 0.6},
          min_quality: 0.8
        )

      {:ok, provider} = Router.select_provider(router, "test", [])

      # Cheap provider doesn't meet quality threshold
      assert provider == :expensive
    end
  end

  describe "record_result/3" do
    test "updates provider health on success" do
      router = Router.new(strategy: :fallback, providers: [:claude])

      router = Router.record_result(router, :claude, {:ok, "response"})

      assert Router.provider_healthy?(router, :claude)
    end

    test "marks provider unhealthy on repeated failures" do
      router = Router.new(strategy: :fallback, providers: [:claude])

      router =
        router
        |> Router.record_result(:claude, {:error, "fail1"})
        |> Router.record_result(:claude, {:error, "fail2"})
        |> Router.record_result(:claude, {:error, "fail3"})

      refute Router.provider_healthy?(router, :claude)
    end

    test "tracks latency for providers" do
      router = Router.new(strategy: :fallback, providers: [:claude])

      router = Router.record_result(router, :claude, {:ok, "response"}, latency_ms: 100)

      assert Router.get_stats(router, :claude).avg_latency > 0
    end
  end

  describe "get_stats/2" do
    test "returns provider statistics" do
      router = Router.new(strategy: :fallback, providers: [:claude])

      router =
        router
        |> Router.record_result(:claude, {:ok, "r1"}, latency_ms: 100)
        |> Router.record_result(:claude, {:ok, "r2"}, latency_ms: 200)

      stats = Router.get_stats(router, :claude)

      assert stats.success_count == 2
      assert stats.failure_count == 0
      assert stats.avg_latency == 150
    end
  end

  describe "infer_task_type/1" do
    test "detects code-related tasks" do
      assert Router.infer_task_type("fix this bug in the code") == :code
      assert Router.infer_task_type("debug this function") == :code
      assert Router.infer_task_type("refactor the module") == :code
      assert Router.infer_task_type("implement a new feature") == :code
    end

    test "detects quick tasks" do
      assert Router.infer_task_type("yes or no?") == :quick
      assert Router.infer_task_type("true or false") == :quick
      assert Router.infer_task_type("is this correct?") == :quick
    end

    test "detects reasoning tasks" do
      assert Router.infer_task_type("explain why this happens") == :reasoning
      assert Router.infer_task_type("analyze the algorithm") == :reasoning
      assert Router.infer_task_type("compare these approaches") == :reasoning
    end

    test "defaults to general" do
      assert Router.infer_task_type("hello world") == :general
    end
  end
end
