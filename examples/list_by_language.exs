# List all repositories grouped by programming language
#
# Usage: mix run examples/list_by_language.exs

alias PortfolioCoder.Portfolio.Registry

IO.puts("Repositories by Language")
IO.puts(String.duplicate("=", 50))
IO.puts("")

case Registry.list_repos() do
  {:ok, repos} ->
    by_language =
      repos
      |> Enum.group_by(& &1.language)
      |> Enum.sort_by(fn {lang, _} -> to_string(lang) end)

    for {language, language_repos} <- by_language do
      lang_str = language || "Unknown"
      IO.puts("#{String.upcase(to_string(lang_str))} (#{length(language_repos)})")
      IO.puts(String.duplicate("-", 40))

      sorted = Enum.sort_by(language_repos, & &1.name)

      for repo <- sorted do
        status_icon =
          case repo.status do
            :active -> "+"
            :stale -> "~"
            :archived -> "-"
            _ -> " "
          end

        type_str = "(#{repo.type})"
        IO.puts("  [#{status_icon}] #{repo.name} #{type_str}")
      end

      IO.puts("")
    end

    IO.puts("Legend: [+] active, [~] stale, [-] archived")

  {:error, reason} ->
    IO.puts(:stderr, "Error: #{inspect(reason)}")
    System.halt(1)
end
