# examples/10_agent_debug_demo.exs
#
# Demonstrates: Debug Agent for Code Analysis
# Modules Used: LLM, Parser, Graph
# Prerequisites: GEMINI_API_KEY
#
# Usage: mix run examples/10_agent_debug_demo.exs [file_to_analyze]
#
# A specialized agent focused on debugging and code quality analysis.

alias PortfolioCoder.Indexer.Parser

defmodule DebugAgentDemo do
  @analysis_prompt """
  You are a code debugging assistant. Analyze this code for potential issues.

  Code:
  ```<%= language %>
  <%= code %>
  ```

  Check for:
  1. Potential bugs or logic errors
  2. Missing error handling
  3. Code smells
  4. Potential performance issues
  5. Security concerns

  Provide a structured analysis with severity levels (info, warning, error).
  """

  @fix_prompt """
  Based on this analysis:
  <%= analysis %>

  For issue: <%= issue %>

  Suggest a fix with code example.
  """

  def run(file_path \\ nil) do
    print_header("Debug Agent Demo")

    check_api_key()

    path = file_path || find_sample_file()

    if path && File.exists?(path) do
      IO.puts("Analyzing: #{path}\n")
      analyze_file(path)
    else
      IO.puts("No file specified. Running demo analysis...\n")
      demo_analysis()
    end
  end

  defp find_sample_file do
    # Find a sample file to analyze
    Path.expand("lib/portfolio_coder")
    |> Path.join("**/*.ex")
    |> Path.wildcard()
    |> Enum.find(&String.contains?(&1, "parser"))
  end

  defp analyze_file(path) do
    code = File.read!(path)
    language = detect_language(path)

    print_section("Code Analysis")

    case Parser.parse(path) do
      {:ok, parsed} ->
        IO.puts("Language: #{parsed.language}")
        IO.puts("Symbols: #{length(parsed.symbols)}")
        IO.puts("References: #{length(parsed.references)}")
        IO.puts("")

      {:error, _} ->
        :ok
    end

    # Truncate long files for analysis
    code_sample = String.slice(code, 0, 3000)

    print_section("Issue Detection")
    analysis = analyze_code(code_sample, language)
    IO.puts(analysis)

    print_section("Interactive Debug")
    IO.puts("Ask questions about this code (type 'quit' to exit):\n")
    interactive_debug(code_sample, language)
  end

  defp demo_analysis do
    # Demo with a sample code snippet
    sample_code = """
    defmodule Example do
      def process(data) do
        result = data |> parse() |> transform()
        result
      end

      def parse(str) do
        String.to_integer(str)
      end

      def transform(num) do
        num * 2
      end
    end
    """

    print_section("Sample Code")
    IO.puts(sample_code)

    print_section("Analysis")
    analysis = analyze_code(sample_code, "elixir")
    IO.puts(analysis)
  end

  defp analyze_code(code, language) do
    prompt =
      @analysis_prompt
      |> String.replace("<%= language %>", language)
      |> String.replace("<%= code %>", code)

    messages = [%{role: :user, content: prompt}]

    case PortfolioIndex.Adapters.LLM.Gemini.complete(messages, max_tokens: 1500) do
      {:ok, %{content: analysis}} ->
        String.trim(analysis)

      {:error, reason} ->
        "Error analyzing code: #{inspect(reason)}"
    end
  end

  defp interactive_debug(code, language) do
    case IO.gets("> ") do
      :eof ->
        IO.puts("\nGoodbye!")

      {:error, _} ->
        IO.puts("\nGoodbye!")

      input ->
        question = String.trim(input)

        cond do
          question in ["quit", "exit", "q"] ->
            IO.puts("Goodbye!")

          question == "" ->
            interactive_debug(code, language)

          true ->
            answer = debug_question(code, language, question)
            IO.puts("\n#{answer}\n")
            interactive_debug(code, language)
        end
    end
  end

  defp debug_question(code, language, question) do
    prompt = """
    Code under analysis (#{language}):
    ```
    #{String.slice(code, 0, 2000)}
    ```

    User question: #{question}

    Provide a helpful debugging-focused answer.
    """

    messages = [%{role: :user, content: prompt}]

    case PortfolioIndex.Adapters.LLM.Gemini.complete(messages, max_tokens: 1000) do
      {:ok, %{content: answer}} ->
        String.trim(answer)

      {:error, reason} ->
        "Error: #{inspect(reason)}"
    end
  end

  defp detect_language(path) do
    case Path.extname(path) do
      ".ex" -> "elixir"
      ".exs" -> "elixir"
      ".py" -> "python"
      ".js" -> "javascript"
      ".ts" -> "typescript"
      _ -> "unknown"
    end
  end

  defp check_api_key do
    if System.get_env("GEMINI_API_KEY") do
      IO.puts("Using Gemini API\n")
    else
      IO.puts(:stderr, "Warning: GEMINI_API_KEY not set\n")
    end
  end

  defp print_header(text) do
    IO.puts(String.duplicate("=", 70))
    IO.puts(text)
    IO.puts(String.duplicate("=", 70))
    IO.puts("")
  end

  defp print_section(text) do
    IO.puts(String.duplicate("-", 70))
    IO.puts(text)
    IO.puts(String.duplicate("-", 70))
    IO.puts("")
  end
end

# Main execution
file_path =
  case System.argv() do
    [path | _] -> Path.expand(path)
    [] -> nil
  end

DebugAgentDemo.run(file_path)
