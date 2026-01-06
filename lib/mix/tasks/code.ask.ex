defmodule Mix.Tasks.Code.Ask do
  @moduledoc """
  Ask questions about indexed code using RAG.

  Retrieves relevant code from the index and uses an LLM to answer
  questions based on that context.

  Requires GEMINI_API_KEY, OPENAI_API_KEY, or ANTHROPIC_API_KEY.

  ## Usage

      mix code.ask QUESTION [OPTIONS]

  ## Options

    * `--index` - Name of the index to use (default: "default")
    * `--context` - Number of context chunks to retrieve (default: 5)

  ## Examples

      mix code.ask "How does authentication work?"
      mix code.ask "What patterns are used for error handling?"
      mix code.ask "Explain the main module" --context 10

  """
  use Mix.Task

  alias PortfolioCoder.Indexer.InMemorySearch

  @shortdoc "Ask questions about code"

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:portfolio_coder)

    {opts, question_parts, _} =
      OptionParser.parse(args,
        strict: [
          index: :string,
          context: :integer,
          help: :boolean
        ],
        aliases: [i: :index, c: :context, h: :help]
      )

    if opts[:help] do
      shell_info(@moduledoc)
    else
      question = Enum.join(question_parts, " ")

      if question == "" do
        shell_error("Error: Please provide a question")
        exit({:shutdown, 1})
      end

      ask_question(question, opts)
    end
  end

  defp ask_question(question, opts) do
    shell_info("Question: #{question}\n")

    index_name = opts[:index] || "default"
    context_count = opts[:context] || 5

    case get_index(index_name) do
      {:ok, index} ->
        # Retrieve relevant context
        shell_info("Retrieving context...")

        {:ok, results} = InMemorySearch.search(index, question, limit: context_count)

        if results == [] do
          shell_info("No relevant code found in the index.")
        else
          shell_info("Found #{length(results)} relevant chunks.\n")
          generate_answer(question, results)
        end

      {:error, :not_found} ->
        shell_error("""
        Error: Index '#{index_name}' not found.

        Run `mix code.index PATH` first to build the index.
        """)

        exit({:shutdown, 1})
    end
  end

  defp generate_answer(question, results) do
    # Format context from search results
    context =
      results
      |> Enum.with_index(1)
      |> Enum.map(fn {result, idx} ->
        path = result.metadata[:relative_path] || result.metadata[:path] || "unknown"
        name = result.metadata[:name]

        header =
          if name do
            "[#{idx}] #{name} (#{path})"
          else
            "[#{idx}] #{path}"
          end

        """
        #{header}
        ```
        #{String.slice(result.content, 0, 600)}
        ```
        """
      end)
      |> Enum.join("\n")

    # Try available LLM providers
    case get_llm_provider() do
      {:ok, provider, module} ->
        shell_info("Using #{provider} for answer generation...\n")

        prompt = """
        Based on the following code context, answer this question: #{question}

        Context:
        #{context}

        Provide a clear, concise answer that references the relevant code when appropriate.
        """

        messages = [%{role: :user, content: prompt}]

        case module.complete(messages, max_tokens: 1000) do
          {:ok, %{content: answer}} ->
            shell_info("Answer:\n")
            shell_info(answer)

          {:error, reason} ->
            shell_error("LLM error: #{inspect(reason)}")
            shell_info("\nContext retrieved (answer generation failed):")
            shell_info(context)
        end

      {:error, :no_provider} ->
        shell_info("""
        No LLM API key found. Set one of:
          - GEMINI_API_KEY
          - OPENAI_API_KEY
          - ANTHROPIC_API_KEY

        Showing retrieved context instead:

        #{context}
        """)
    end
  end

  defp get_llm_provider do
    cond do
      System.get_env("GEMINI_API_KEY") ->
        {:ok, :gemini, PortfolioIndex.Adapters.LLM.Gemini}

      System.get_env("ANTHROPIC_API_KEY") ->
        {:ok, :anthropic, PortfolioIndex.Adapters.LLM.Anthropic}

      System.get_env("OPENAI_API_KEY") ->
        {:ok, :openai, PortfolioIndex.Adapters.LLM.OpenAI}

      true ->
        {:error, :no_provider}
    end
  end

  defp get_index(name) do
    key = {:code_index, name}

    case :persistent_term.get(key, nil) do
      nil -> {:error, :not_found}
      index -> {:ok, index}
    end
  end

  defp shell_info(message), do: IO.puts(message)
  defp shell_error(message), do: IO.puts(:stderr, message)
end
