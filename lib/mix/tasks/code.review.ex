defmodule Mix.Tasks.Code.Review do
  @moduledoc """
  Perform automated code review.

  ## Usage

      mix code.review [path]
      mix code.review --security
      mix code.review --complexity

  ## Options

    * `--security` - Focus on security checks
    * `--complexity` - Focus on complexity checks
    * `--style` - Focus on style checks
    * `--all` - Run all checks (default)
    * `--output` - Output format (text, json)

  ## Examples

      # Review all code
      mix code.review lib

      # Security-focused review
      mix code.review --security lib

      # Output as JSON
      mix code.review --output json lib
  """

  use Mix.Task

  alias PortfolioCoder.Review.PRReviewer

  @shortdoc "Perform automated code review"

  @switches [
    security: :boolean,
    complexity: :boolean,
    style: :boolean,
    all: :boolean,
    output: :string
  ]

  @impl Mix.Task
  def run(args) do
    {opts, paths, _} = OptionParser.parse(args, switches: @switches)

    path = List.first(paths) || "lib"
    output_format = Keyword.get(opts, :output, "text")

    # Determine which checks to run
    checks = determine_checks(opts)

    Mix.shell().info("Code Review")
    Mix.shell().info(String.duplicate("=", 60))
    Mix.shell().info("Reviewing: #{path}")
    Mix.shell().info("Checks: #{Enum.join(checks, ", ")}\n")

    # Collect files
    files = scan_files(path)
    Mix.shell().info("Found #{length(files)} files to review\n")

    # Run review
    issues = review_files(files, checks)

    # Output results
    case output_format do
      "json" ->
        output_json(issues)

      _ ->
        output_text(issues)
    end
  end

  defp determine_checks(opts) do
    cond do
      Keyword.get(opts, :security) ->
        [:security]

      Keyword.get(opts, :complexity) ->
        [:complexity]

      Keyword.get(opts, :style) ->
        [:style]

      true ->
        [:security, :complexity, :style]
    end
  end

  defp scan_files(path) do
    path
    |> Path.join("**/*.{ex,exs}")
    |> Path.wildcard()
    |> Enum.filter(fn file ->
      not String.contains?(file, ["deps/", "_build/", ".git/"])
    end)
  end

  defp review_files(files, checks) do
    # Create reviewer with selected checks
    reviewer = PRReviewer.new(checks: checks)

    files
    |> Enum.flat_map(fn file ->
      case File.read(file) do
        {:ok, content} ->
          review_file(file, content, reviewer)

        {:error, _} ->
          []
      end
    end)
  end

  defp review_file(path, content, reviewer) do
    diff = build_diff(path, content)

    # Use the public review API
    {:ok, review_result} = PRReviewer.review(reviewer, diff)

    # Map comments to issues format expected by output functions
    review_result.comments
    |> Enum.map(fn comment ->
      %{
        path: path,
        message: comment.message,
        line: comment[:line],
        severity: type_to_severity(comment.type)
      }
    end)
  end

  defp type_to_severity(:security), do: :critical
  defp type_to_severity(:warning), do: :high
  defp type_to_severity(:suggestion), do: :medium
  defp type_to_severity(:info), do: :low
  defp type_to_severity(_), do: :medium

  defp build_diff(path, content) do
    rel_path = Path.relative_to_cwd(path)
    lines = String.split(content, "\n", trim: false)

    [
      "diff --git a/#{rel_path} b/#{rel_path}",
      "@@ -0,0 +1,#{length(lines)} @@"
    ]
    |> Enum.concat(Enum.map(lines, &"+#{&1}"))
    |> Enum.join("\n")
  end

  defp output_text(issues) do
    if Enum.empty?(issues) do
      Mix.shell().info("✓ No issues found")
    else
      grouped = Enum.group_by(issues, & &1.severity)

      for {severity, items} <- grouped do
        Mix.shell().info("\n#{severity_label(severity)} (#{length(items)}):")

        for issue <- items do
          Mix.shell().info("  #{issue.path}")
          Mix.shell().info("    #{issue.message}")

          if issue[:line] do
            Mix.shell().info("    Line: #{issue.line}")
          end
        end
      end

      Mix.shell().info("\n---")
      Mix.shell().info("Total issues: #{length(issues)}")

      critical = Enum.count(issues, &(&1.severity == :critical))
      high = Enum.count(issues, &(&1.severity == :high))

      if critical > 0 or high > 0 do
        Mix.shell().info("⚠ #{critical} critical, #{high} high severity issues require attention")
      end
    end
  end

  defp output_json(issues) do
    json =
      Jason.encode!(
        %{
          issues: issues,
          summary: %{
            total: length(issues),
            critical: Enum.count(issues, &(&1.severity == :critical)),
            high: Enum.count(issues, &(&1.severity == :high)),
            medium: Enum.count(issues, &(&1.severity == :medium)),
            low: Enum.count(issues, &(&1.severity == :low))
          }
        },
        pretty: true
      )

    IO.puts(json)
  end

  defp severity_label(:critical), do: "🔴 CRITICAL"
  defp severity_label(:high), do: "🟠 HIGH"
  defp severity_label(:medium), do: "🟡 MEDIUM"
  defp severity_label(:low), do: "🔵 LOW"
  defp severity_label(other), do: to_string(other)
end
