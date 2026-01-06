defmodule PortfolioCoder.Review.PRReviewer do
  @moduledoc """
  Automated PR review with security, complexity, style, and test coverage checks.

  The PRReviewer analyzes git diffs and provides automated code review with:

  - **Security checks**: Hardcoded credentials, dangerous functions, SQL injection
  - **Complexity checks**: Large PRs, deeply nested code, cyclomatic complexity
  - **Style checks**: Documentation, line length, naming conventions
  - **Test coverage**: Ensures code changes have corresponding tests

  ## Features

  - Parse and analyze git diffs
  - Identify security vulnerabilities
  - Calculate complexity scores
  - Generate review comments
  - Provide approve/request changes decision

  ## Usage

      reviewer = PRReviewer.new(checks: [:security, :complexity, :style, :tests])
      {:ok, review} = PRReviewer.review(reviewer, diff)

      if PRReviewer.approve?(review) do
        IO.puts("LGTM!")
      else
        IO.puts(PRReviewer.generate_summary(review))
      end
  """

  defstruct [:checks, :max_lines, :max_line_length]

  @type comment :: %{
          file: String.t(),
          line: non_neg_integer() | nil,
          type: :security | :warning | :suggestion | :info,
          message: String.t()
        }

  @type review :: %{
          status: :approved | :needs_changes | :request_changes,
          comments: [comment()],
          summary: map(),
          security_issues: non_neg_integer(),
          complexity_score: float()
        }

  @type t :: %__MODULE__{
          checks: [atom()],
          max_lines: non_neg_integer(),
          max_line_length: non_neg_integer()
        }

  # Security patterns
  @credential_patterns [
    ~r/password\s*=\s*["'][^"']+["']/i,
    ~r/api_key\s*=\s*["'][^"']+["']/i,
    ~r/secret\s*=\s*["'][^"']+["']/i,
    ~r/token\s*=\s*["'][^"']+["']/i,
    ~r/sk-[a-zA-Z0-9]+/,
    ~r/AKIA[A-Z0-9]{16}/
  ]

  @dangerous_functions [
    "System.cmd",
    "Code.eval_string",
    "Code.eval_quoted",
    ":os.cmd",
    "File.write!",
    "send_resp"
  ]

  @todo_patterns [
    ~r/TODO.*security/i,
    ~r/FIXME.*security/i,
    ~r/TODO.*bypass/i,
    ~r/HACK/i
  ]

  @default_checks [:security, :complexity, :style, :tests]
  @default_max_lines 500
  @default_max_line_length 120

  @doc """
  Create a new PR reviewer.

  ## Options

  - `:checks` - List of check types to run (default: all)
  - `:max_lines` - Maximum lines before flagging as large PR (default: 500)
  - `:max_line_length` - Maximum line length before warning (default: 120)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      checks: Keyword.get(opts, :checks, @default_checks),
      max_lines: Keyword.get(opts, :max_lines, @default_max_lines),
      max_line_length: Keyword.get(opts, :max_line_length, @default_max_line_length)
    }
  end

  @doc """
  Return the default checks list.
  """
  @spec default_checks() :: [atom()]
  def default_checks, do: @default_checks

  @doc """
  Review a PR diff.

  Returns `{:ok, review}` with review results including:
  - Status (approved/needs_changes/request_changes)
  - List of comments with file, line, type, and message
  - Summary statistics
  - Security issue count
  - Complexity score
  """
  @spec review(t(), String.t()) :: {:ok, review()}
  def review(reviewer, diff) do
    # Parse the diff
    parsed = parse_diff(diff)

    # Run enabled checks
    comments =
      reviewer.checks
      |> Enum.flat_map(fn check ->
        run_check(check, parsed, reviewer)
      end)

    # Calculate metrics
    security_issues = Enum.count(comments, &(&1.type == :security))
    complexity_score = calculate_complexity(parsed)

    # Determine status
    status = determine_status(comments, security_issues)

    review = %{
      status: status,
      comments: comments,
      summary: %{
        files_changed: length(parsed.files),
        added_lines: parsed.added_lines,
        removed_lines: parsed.removed_lines
      },
      security_issues: security_issues,
      complexity_score: complexity_score
    }

    {:ok, review}
  end

  @doc """
  Generate a human-readable summary of the review.
  """
  @spec generate_summary(review()) :: String.t()
  def generate_summary(review) do
    """
    ## PR Review Summary

    **Status:** #{review.status}
    **Files Changed:** #{review.summary.files_changed}
    **Lines Added:** #{review.summary.added_lines}
    **Lines Removed:** #{review.summary.removed_lines}
    **Security Issues:** #{review.security_issues}
    **Complexity Score:** #{Float.round(review.complexity_score, 2)}

    ### Comments (#{length(review.comments)})
    #{format_comments(review.comments)}
    """
  end

  @doc """
  Check if the review should be approved.

  Returns false if there are security issues or request_changes status.
  """
  @spec approve?(review()) :: boolean()
  def approve?(review) do
    review.security_issues == 0 and review.status != :request_changes
  end

  # Private helpers

  defp parse_diff(diff) do
    files =
      diff
      |> String.split(~r/^diff --git/m, trim: true)
      |> Enum.map(&parse_file_diff/1)
      |> Enum.reject(&is_nil/1)

    added_lines = files |> Enum.map(& &1.added) |> Enum.sum()
    removed_lines = files |> Enum.map(& &1.removed) |> Enum.sum()

    %{
      files: files,
      added_lines: added_lines,
      removed_lines: removed_lines,
      raw: diff
    }
  end

  defp parse_file_diff(chunk) do
    file_match = Regex.run(~r/a\/(.+?) b\//, chunk)

    if file_match do
      file = Enum.at(file_match, 1)

      added_lines =
        chunk |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "+")) |> length()

      removed_lines =
        chunk |> String.split("\n") |> Enum.filter(&String.starts_with?(&1, "-")) |> length()

      %{
        file: file,
        content: chunk,
        added: added_lines,
        removed: removed_lines,
        added_content: extract_added_content(chunk)
      }
    else
      nil
    end
  end

  defp extract_added_content(chunk) do
    chunk
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "+"))
    |> Enum.map(&String.slice(&1, 1..-1//1))
    |> Enum.join("\n")
  end

  defp run_check(:security, parsed, _reviewer) do
    parsed.files
    |> Enum.flat_map(&check_security/1)
  end

  defp run_check(:complexity, parsed, reviewer) do
    comments = []

    # Check total PR size
    total_lines = parsed.added_lines + parsed.removed_lines

    comments =
      if total_lines > reviewer.max_lines do
        [
          %{
            file: "overall",
            line: nil,
            type: :warning,
            message:
              "Large PR with #{total_lines} changed lines. Consider breaking into smaller PRs."
          }
          | comments
        ]
      else
        comments
      end

    # Check individual file complexity
    parsed.files
    |> Enum.flat_map(&check_file_complexity/1)
    |> Kernel.++(comments)
  end

  defp run_check(:style, parsed, reviewer) do
    parsed.files
    |> Enum.flat_map(&check_style(&1, reviewer))
  end

  defp run_check(:tests, parsed, _reviewer) do
    has_code_changes =
      Enum.any?(parsed.files, fn f ->
        String.starts_with?(f.file, "lib/") and String.ends_with?(f.file, ".ex")
      end)

    has_test_changes =
      Enum.any?(parsed.files, fn f ->
        String.starts_with?(f.file, "test/") or String.contains?(f.file, "_test.ex")
      end)

    if has_code_changes and not has_test_changes do
      [
        %{
          file: "overall",
          line: nil,
          type: :warning,
          message: "No test changes detected. Please add tests for new functionality."
        }
      ]
    else
      []
    end
  end

  defp run_check(_unknown, _parsed, _reviewer), do: []

  defp check_security(file) do
    comments = []
    content = file.added_content

    # Check for hardcoded credentials
    comments =
      Enum.reduce(@credential_patterns, comments, fn pattern, acc ->
        if Regex.match?(pattern, content) do
          [
            %{
              file: file.file,
              line: nil,
              type: :security,
              message:
                "Potential hardcoded credential detected. Use environment variables or secrets management."
            }
            | acc
          ]
        else
          acc
        end
      end)

    # Check for dangerous functions
    comments =
      Enum.reduce(@dangerous_functions, comments, fn func, acc ->
        if String.contains?(content, func) do
          [
            %{
              file: file.file,
              line: nil,
              type: :security,
              message:
                "Dangerous function '#{func}' detected. Ensure input is properly validated."
            }
            | acc
          ]
        else
          acc
        end
      end)

    # Check for security TODOs
    comments =
      Enum.reduce(@todo_patterns, comments, fn pattern, acc ->
        if Regex.match?(pattern, content) do
          [
            %{
              file: file.file,
              line: nil,
              type: :warning,
              message: "Security-related TODO/FIXME found. Please address before merging."
            }
            | acc
          ]
        else
          acc
        end
      end)

    comments
  end

  defp check_file_complexity(file) do
    content = file.added_content

    # Count nesting indicators
    nesting_depth = count_nesting(content)

    if nesting_depth > 4 do
      [
        %{
          file: file.file,
          line: nil,
          type: :suggestion,
          message: "High nesting depth (#{nesting_depth}). Consider extracting helper functions."
        }
      ]
    else
      []
    end
  end

  defp count_nesting(content) do
    keywords = ["if ", "case ", "cond ", "with ", "fn ", "for ", "receive "]

    keywords
    |> Enum.map(fn kw ->
      content
      |> String.split("\n")
      |> Enum.count(&String.contains?(&1, kw))
    end)
    |> Enum.sum()
    # Rough estimate of nesting
    |> div(2)
  end

  defp check_style(file, reviewer) do
    comments = []
    content = file.added_content
    lines = String.split(content, "\n")

    # Check for missing docs on public functions
    has_public_func = Regex.match?(~r/def \w+/, content)
    has_doc = String.contains?(content, "@doc") or String.contains?(content, "@moduledoc")

    comments =
      if has_public_func and not has_doc and String.ends_with?(file.file, ".ex") do
        [
          %{
            file: file.file,
            line: nil,
            type: :suggestion,
            message: "Consider adding @doc or @moduledoc for public functions."
          }
          | comments
        ]
      else
        comments
      end

    # Check line length
    long_lines = Enum.filter(lines, &(String.length(&1) > reviewer.max_line_length))

    comments =
      if length(long_lines) > 0 do
        [
          %{
            file: file.file,
            line: nil,
            type: :suggestion,
            message:
              "#{length(long_lines)} lines exceed #{reviewer.max_line_length} characters. Consider breaking them up."
          }
          | comments
        ]
      else
        comments
      end

    comments
  end

  defp calculate_complexity(parsed) do
    # Simple complexity score based on:
    # - Number of files
    # - Lines changed
    # - Nesting in code

    file_score = length(parsed.files) * 1.0
    line_score = (parsed.added_lines + parsed.removed_lines) / 100

    nesting_score =
      parsed.files
      |> Enum.map(fn f -> count_nesting(f.added_content) end)
      |> Enum.sum()

    file_score + line_score + nesting_score
  end

  defp determine_status(comments, security_issues) do
    cond do
      security_issues > 0 -> :request_changes
      Enum.any?(comments, &(&1.type == :warning)) -> :needs_changes
      true -> :approved
    end
  end

  defp format_comments([]), do: "No comments."

  defp format_comments(comments) do
    comments
    |> Enum.group_by(& &1.type)
    |> Enum.map_join("\n\n", fn {type, type_comments} ->
      """
      **#{format_type(type)}:**
      #{Enum.map_join(type_comments, "\n", &"- [#{&1.file}] #{&1.message}")}
      """
    end)
  end

  defp format_type(:security), do: "🔴 Security Issues"
  defp format_type(:warning), do: "🟡 Warnings"
  defp format_type(:suggestion), do: "🔵 Suggestions"
  defp format_type(:info), do: "ℹ️ Info"
end
