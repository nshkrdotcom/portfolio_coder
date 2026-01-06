defmodule PortfolioCoder.Review.PRReviewerTest do
  use ExUnit.Case, async: true

  alias PortfolioCoder.Review.PRReviewer

  @simple_diff """
  diff --git a/lib/module.ex b/lib/module.ex
  --- a/lib/module.ex
  +++ b/lib/module.ex
  @@ -1,5 +1,7 @@
   defmodule Module do
  +  @moduledoc "Added docs"
  +
     def hello do
       :world
     end
  end
  """

  @security_issue_diff """
  diff --git a/lib/auth.ex b/lib/auth.ex
  --- a/lib/auth.ex
  +++ b/lib/auth.ex
  @@ -1,5 +1,8 @@
   defmodule Auth do
     def check_password(password) do
  -    password == "secret"
  +    # TODO: Fix this hardcoded password
  +    password == "admin123"
     end
  +
  +  def execute_command(cmd), do: System.cmd(cmd, [])
   end
  """

  @large_diff """
              diff --git a/lib/module.ex b/lib/module.ex
              """ <> (1..200 |> Enum.map(fn i -> "+def func#{i}, do: :ok\n" end) |> Enum.join())

  describe "new/1" do
    test "creates a PR reviewer" do
      reviewer = PRReviewer.new()

      assert %PRReviewer{} = reviewer
      assert reviewer.checks == PRReviewer.default_checks()
    end

    test "accepts custom checks" do
      reviewer = PRReviewer.new(checks: [:security, :complexity])

      assert reviewer.checks == [:security, :complexity]
    end
  end

  describe "review/2" do
    test "reviews a simple diff" do
      reviewer = PRReviewer.new()

      {:ok, review} = PRReviewer.review(reviewer, @simple_diff)

      assert review.status in [:approved, :needs_changes, :request_changes]
      assert is_list(review.comments)
      assert is_map(review.summary)
    end

    test "detects security issues" do
      reviewer = PRReviewer.new(checks: [:security])

      {:ok, review} = PRReviewer.review(reviewer, @security_issue_diff)

      # Should flag hardcoded password and system command
      assert review.security_issues > 0
      assert Enum.any?(review.comments, fn c -> c.type == :security end)
    end

    test "calculates complexity score" do
      reviewer = PRReviewer.new(checks: [:complexity])

      {:ok, review} = PRReviewer.review(reviewer, @large_diff)

      assert review.complexity_score > 0
    end

    test "counts changes" do
      reviewer = PRReviewer.new()

      {:ok, review} = PRReviewer.review(reviewer, @simple_diff)

      assert review.summary.added_lines > 0
      assert review.summary.files_changed >= 1
    end
  end

  describe "security checks" do
    test "detects hardcoded credentials" do
      diff = """
      diff --git a/config.ex b/config.ex
      +password = "secret123"
      +api_key = "sk-abc123"
      """

      reviewer = PRReviewer.new(checks: [:security])
      {:ok, review} = PRReviewer.review(reviewer, diff)

      assert review.security_issues > 0
      assert Enum.any?(review.comments, &String.contains?(&1.message, "credential"))
    end

    test "detects dangerous functions" do
      diff = """
      diff --git a/lib/cmd.ex b/lib/cmd.ex
      +System.cmd(user_input, [])
      +Code.eval_string(code)
      """

      reviewer = PRReviewer.new(checks: [:security])
      {:ok, review} = PRReviewer.review(reviewer, diff)

      assert review.security_issues > 0
    end

    test "detects TODO/FIXME with security implications" do
      diff = """
      diff --git a/lib/auth.ex b/lib/auth.ex
      +# TODO: remove this bypass
      +# FIXME: security vulnerability here
      """

      reviewer = PRReviewer.new(checks: [:security])
      {:ok, review} = PRReviewer.review(reviewer, diff)

      assert Enum.any?(review.comments, &(&1.type == :warning))
    end
  end

  describe "complexity checks" do
    test "flags large PRs" do
      reviewer = PRReviewer.new(checks: [:complexity], max_lines: 100)
      {:ok, review} = PRReviewer.review(reviewer, @large_diff)

      assert review.status == :request_changes or length(review.comments) > 0
      assert Enum.any?(review.comments, &String.contains?(&1.message, "Large PR"))
    end

    test "calculates file complexity" do
      diff = """
      diff --git a/lib/complex.ex b/lib/complex.ex
      +defmodule Complex do
      +  def nested do
      +    if x do
      +      case y do
      +        :a -> if z, do: :nested
      +        :b -> :ok
      +      end
      +    end
      +  end
      +end
      """

      reviewer = PRReviewer.new(checks: [:complexity])
      {:ok, review} = PRReviewer.review(reviewer, diff)

      assert review.complexity_score > 0
    end
  end

  describe "style checks" do
    test "detects missing docs on public functions" do
      diff = """
      diff --git a/lib/module.ex b/lib/module.ex
      +defmodule Module do
      +  def public_function do
      +    :ok
      +  end
      +end
      """

      reviewer = PRReviewer.new(checks: [:style])
      {:ok, review} = PRReviewer.review(reviewer, diff)

      assert Enum.any?(review.comments, &(&1.type == :suggestion))
    end

    test "flags long lines" do
      long_line = String.duplicate("x", 150)

      diff = """
      diff --git a/lib/module.ex b/lib/module.ex
      +#{long_line}
      """

      reviewer = PRReviewer.new(checks: [:style])
      {:ok, review} = PRReviewer.review(reviewer, diff)

      assert Enum.any?(review.comments, &String.contains?(&1.message, "exceed"))
    end
  end

  describe "test coverage checks" do
    test "flags changes without test changes" do
      diff = """
      diff --git a/lib/important.ex b/lib/important.ex
      +def critical_function, do: :important
      """

      reviewer = PRReviewer.new(checks: [:tests])
      {:ok, review} = PRReviewer.review(reviewer, diff)

      assert Enum.any?(review.comments, &String.contains?(&1.message, "test"))
    end

    test "passes when tests are included" do
      diff = """
      diff --git a/lib/module.ex b/lib/module.ex
      +def new_function, do: :ok
      diff --git a/test/module_test.exs b/test/module_test.exs
      +test "new_function works" do
      +  assert Module.new_function() == :ok
      +end
      """

      reviewer = PRReviewer.new(checks: [:tests])
      {:ok, review} = PRReviewer.review(reviewer, diff)

      # Should not have the "missing tests" warning
      refute Enum.any?(review.comments, fn c ->
               c.type == :warning and String.contains?(c.message, "No test")
             end)
    end
  end

  describe "generate_summary/1" do
    test "generates human-readable summary" do
      reviewer = PRReviewer.new()
      {:ok, review} = PRReviewer.review(reviewer, @simple_diff)

      summary = PRReviewer.generate_summary(review)

      assert is_binary(summary)
      assert String.contains?(summary, "Files Changed")
    end
  end

  describe "approve?/1" do
    test "approves clean PRs" do
      reviewer = PRReviewer.new()
      {:ok, review} = PRReviewer.review(reviewer, @simple_diff)

      # Simple diff with no issues should be approvable
      assert PRReviewer.approve?(review)
    end

    test "does not approve PRs with security issues" do
      reviewer = PRReviewer.new()
      {:ok, review} = PRReviewer.review(reviewer, @security_issue_diff)

      refute PRReviewer.approve?(review)
    end
  end
end
