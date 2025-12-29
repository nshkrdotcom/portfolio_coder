defmodule Mix.Tasks.Code.Ask do
  @moduledoc """
  Ask questions about indexed code.

  Uses RAG (Retrieval-Augmented Generation) to answer questions
  about your codebase using context from indexed files.

  ## Usage

      mix code.ask QUESTION [OPTIONS]

  ## Options

    * `--index` - Name of the index to use (default: "default")
    * `--stream` - Stream the response (default: false)

  ## Examples

      mix code.ask "How does authentication work?"
      mix code.ask "What database queries are used?" --index my_project
      mix code.ask "Explain the error handling strategy" --stream

  """
  use Mix.Task

  @shortdoc "Ask questions about code"

  @impl Mix.Task
  def run(args) do
    {:ok, _} = Application.ensure_all_started(:portfolio_coder)

    {opts, question_parts, _} =
      OptionParser.parse(args,
        strict: [
          index: :string,
          stream: :boolean,
          help: :boolean
        ],
        aliases: [i: :index, s: :stream, h: :help]
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

    ask_opts =
      []
      |> maybe_add(:index_id, opts[:index])

    if opts[:stream] do
      stream_answer(question, ask_opts)
    else
      get_answer(question, ask_opts)
    end
  end

  defp get_answer(question, opts) do
    case PortfolioCoder.ask(question, opts) do
      {:ok, answer} ->
        shell_info("Answer:\n")
        shell_info(answer)

      {:error, reason} ->
        shell_error("Error: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp stream_answer(question, opts) do
    shell_info("Answer:\n")

    callback = fn chunk ->
      IO.write(chunk)
    end

    case PortfolioCoder.stream_ask(question, callback, opts) do
      :ok ->
        IO.puts("")

      {:error, reason} ->
        shell_error("\nError: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp shell_info(message), do: IO.puts(message)
  defp shell_error(message), do: IO.puts(:stderr, message)

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)
end
