defmodule PortfolioCoder.Portfolio.Scanner do
  @moduledoc """
  Scans directories to discover repositories.

  The scanner looks for git repositories in the configured directories and
  extracts metadata like language, type, and remotes.

  ## Usage

      # Scan all configured directories
      {:ok, repos} = Scanner.scan()

      # Scan specific directories
      {:ok, repos} = Scanner.scan(directories: ["~/p/g/n", "~/p/g/North-Shore-AI"])

  """

  alias PortfolioCoder.Portfolio.{Config, Registry}

  @type scan_result :: %{
          path: String.t(),
          name: String.t(),
          language: atom() | nil,
          type: atom() | nil,
          remotes: [map()],
          is_new: boolean()
        }

  @language_markers %{
    "mix.exs" => :elixir,
    "rebar.config" => :erlang,
    "requirements.txt" => :python,
    "setup.py" => :python,
    "pyproject.toml" => :python,
    "package.json" => :javascript,
    "Cargo.toml" => :rust,
    "go.mod" => :go,
    "Gemfile" => :ruby,
    "pom.xml" => :java,
    "build.gradle" => :java
  }

  @doc """
  Scans all configured directories for repositories.

  ## Options

    * `:directories` - Override configured directories
    * `:exclude` - Additional patterns to exclude

  """
  @spec scan(keyword()) :: {:ok, [scan_result()]}
  def scan(opts \\ []) do
    directories = opts[:directories] || Config.scan_directories()
    exclude_patterns = Config.exclude_patterns() ++ (opts[:exclude] || [])

    existing_paths =
      case Registry.list_repos() do
        {:ok, repos} -> MapSet.new(Enum.map(repos, & &1.path))
        {:error, _} -> MapSet.new()
      end

    results =
      directories
      |> Enum.flat_map(fn dir ->
        expanded = Config.expand_path(dir)

        case scan_directory(expanded, exclude: exclude_patterns) do
          {:ok, repos} -> repos
          {:error, _} -> []
        end
      end)
      |> Enum.map(fn result ->
        Map.put(result, :is_new, result.path not in existing_paths)
      end)

    {:ok, results}
  end

  @doc """
  Scans a single directory for repositories.
  """
  @spec scan_directory(String.t(), keyword()) :: {:ok, [scan_result()]} | {:error, term()}
  def scan_directory(directory, opts \\ []) do
    exclude_patterns = opts[:exclude] || Config.exclude_patterns()

    if File.dir?(directory) do
      results =
        directory
        |> File.ls!()
        |> Enum.map(&Path.join(directory, &1))
        |> Enum.filter(&File.dir?/1)
        |> Enum.reject(&excluded?(&1, exclude_patterns))
        |> Enum.filter(&git_repo?/1)
        |> Enum.map(&build_scan_result/1)

      {:ok, results}
    else
      {:error, :not_a_directory}
    end
  end

  @doc """
  Detects the primary language of a repository.
  """
  @spec detect_language(String.t()) :: atom() | nil
  def detect_language(repo_path) do
    @language_markers
    |> Enum.find_value(fn {marker, language} ->
      if File.exists?(Path.join(repo_path, marker)) do
        language
      end
    end)
  end

  @doc """
  Detects the type of a repository (library, application, port, etc).
  """
  @spec detect_type(String.t()) :: atom() | nil
  def detect_type(repo_path) do
    cond do
      has_phoenix?(repo_path) -> :application
      has_mix_exs?(repo_path) -> detect_elixir_type(repo_path)
      has_package_json?(repo_path) -> detect_js_type(repo_path)
      has_setup_py?(repo_path) -> :library
      true -> :unknown
    end
  end

  @doc """
  Extracts git remotes from a repository.
  """
  @spec extract_remotes(String.t()) :: [map()]
  def extract_remotes(repo_path) do
    case System.cmd("git", ["remote", "-v"], cd: repo_path, stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> Enum.filter(&String.contains?(&1, "(fetch)"))
        |> Enum.map(&parse_remote_line/1)
        |> Enum.uniq_by(& &1.name)

      _ ->
        []
    end
  end

  @doc """
  Checks if a directory is a git repository.
  """
  @spec git_repo?(String.t()) :: boolean()
  def git_repo?(path) do
    File.dir?(Path.join(path, ".git"))
  end

  @doc """
  Extracts dependencies from a repository.
  """
  @spec extract_dependencies(String.t(), atom()) :: %{runtime: [String.t()], dev: [String.t()]}
  def extract_dependencies(repo_path, :elixir) do
    mix_path = Path.join(repo_path, "mix.exs")

    if File.exists?(mix_path) do
      content = File.read!(mix_path)
      extract_elixir_deps(content)
    else
      %{runtime: [], dev: []}
    end
  end

  def extract_dependencies(repo_path, :python) do
    req_path = Path.join(repo_path, "requirements.txt")

    if File.exists?(req_path) do
      deps =
        req_path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.reject(&String.starts_with?(&1, "#"))
        |> Enum.map(&extract_python_dep_name/1)
        |> Enum.reject(&is_nil/1)

      %{runtime: deps, dev: []}
    else
      %{runtime: [], dev: []}
    end
  end

  def extract_dependencies(repo_path, :javascript) do
    pkg_path = Path.join(repo_path, "package.json")

    if File.exists?(pkg_path) do
      case File.read!(pkg_path) |> Jason.decode() do
        {:ok, pkg} ->
          runtime = pkg |> Map.get("dependencies", %{}) |> Map.keys()
          dev = pkg |> Map.get("devDependencies", %{}) |> Map.keys()
          %{runtime: runtime, dev: dev}

        _ ->
          %{runtime: [], dev: []}
      end
    else
      %{runtime: [], dev: []}
    end
  end

  def extract_dependencies(_repo_path, _language) do
    %{runtime: [], dev: []}
  end

  # Private functions

  defp build_scan_result(repo_path) do
    name = Path.basename(repo_path)
    language = detect_language(repo_path)
    type = detect_type(repo_path)
    remotes = extract_remotes(repo_path)

    %{
      path: repo_path,
      name: name,
      language: language,
      type: type,
      remotes: remotes,
      is_new: true
    }
  end

  defp excluded?(path, patterns) do
    name = Path.basename(path)

    Enum.any?(patterns, fn pattern ->
      # Simple pattern matching for common cases
      cond do
        String.contains?(pattern, "**") ->
          # Glob pattern - check if name matches the innermost part
          pattern_name =
            pattern
            |> String.replace("**/", "")
            |> String.replace("/**", "")
            |> String.trim_trailing("/")

          name == pattern_name

        String.ends_with?(pattern, "/") ->
          name == String.trim_trailing(pattern, "/")

        true ->
          name == pattern
      end
    end)
  end

  defp parse_remote_line(line) do
    parts = String.split(line, ~r/\s+/, trim: true)

    case parts do
      [name, url | _] -> %{name: name, url: url}
      _ -> %{name: "unknown", url: "unknown"}
    end
  end

  defp has_phoenix?(repo_path) do
    mix_path = Path.join(repo_path, "mix.exs")

    if File.exists?(mix_path) do
      content = File.read!(mix_path)
      String.contains?(content, ":phoenix")
    else
      false
    end
  end

  defp has_mix_exs?(repo_path) do
    File.exists?(Path.join(repo_path, "mix.exs"))
  end

  defp has_package_json?(repo_path) do
    File.exists?(Path.join(repo_path, "package.json"))
  end

  defp has_setup_py?(repo_path) do
    File.exists?(Path.join(repo_path, "setup.py"))
  end

  defp detect_elixir_type(repo_path) do
    mix_path = Path.join(repo_path, "mix.exs")
    content = File.read!(mix_path)

    cond do
      String.contains?(content, "mod:") -> :application
      String.contains?(content, "escript:") -> :application
      true -> :library
    end
  end

  defp detect_js_type(repo_path) do
    pkg_path = Path.join(repo_path, "package.json")

    case File.read!(pkg_path) |> Jason.decode() do
      {:ok, pkg} ->
        if Map.has_key?(pkg, "main") or Map.has_key?(pkg, "exports") do
          :library
        else
          :application
        end

      _ ->
        :unknown
    end
  end

  defp extract_elixir_deps(content) do
    # Extract runtime deps
    runtime_regex = ~r/\{:(\w+),\s*"[^"]*"\}/
    dev_regex = ~r/\{:(\w+),[^}]*only:\s*(?::dev|:test|\[:dev|\[:test)/

    runtime =
      runtime_regex
      |> Regex.scan(content)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.uniq()

    dev =
      dev_regex
      |> Regex.scan(content)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.uniq()

    # Remove dev deps from runtime
    runtime = runtime -- dev

    %{runtime: runtime, dev: dev}
  end

  defp extract_python_dep_name(line) do
    # Handle formats: package, package==1.0, package>=1.0, package[extra]
    line
    |> String.split(~r/[=<>!\[\s]/, parts: 2)
    |> List.first()
    |> case do
      "" -> nil
      name -> String.trim(name)
    end
  end
end
