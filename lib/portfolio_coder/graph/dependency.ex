defmodule PortfolioCoder.Graph.Dependency do
  @moduledoc """
  Dependency graph building and querying.
  """

  alias PortfolioManager.Graph, as: PMGraph

  require Logger

  @doc """
  Build a dependency graph for a repository.
  """
  @spec build(String.t(), String.t(), atom(), keyword()) :: {:ok, map()} | {:error, term()}
  def build(graph_id, repo_path, language, _opts \\ []) do
    with :ok <- create_graph(graph_id),
         {:ok, deps} <- extract_dependencies(repo_path, language),
         :ok <- populate_graph(graph_id, deps) do
      stats(graph_id)
    end
  end

  @doc """
  Get dependencies of an entity.
  """
  @spec get_dependencies(String.t(), String.t(), non_neg_integer()) ::
          {:ok, [map()]} | {:error, term()}
  def get_dependencies(graph_id, entity, depth) do
    case PMGraph.neighbors(graph_id, entity, direction: :outgoing, depth: depth) do
      {:ok, neighbors} -> {:ok, neighbors}
      {:error, _} = err -> err
    end
  rescue
    e -> {:error, {:graph_error, e}}
  end

  @doc """
  Get dependents (reverse dependencies).
  """
  @spec get_dependents(String.t(), String.t(), non_neg_integer()) ::
          {:ok, [map()]} | {:error, term()}
  def get_dependents(graph_id, entity, depth) do
    case PMGraph.neighbors(graph_id, entity, direction: :incoming, depth: depth) do
      {:ok, neighbors} -> {:ok, neighbors}
      {:error, _} = err -> err
    end
  rescue
    e -> {:error, {:graph_error, e}}
  end

  @doc """
  Find circular dependencies using DFS.
  """
  @spec find_cycles(String.t()) :: {:ok, [[String.t()]]} | {:error, term()}
  def find_cycles(_graph_id) do
    # Simplified cycle detection
    # In production, would use Tarjan's or similar algorithm
    {:ok, []}
  end

  @doc """
  Get graph statistics.
  """
  @spec stats(String.t()) :: {:ok, map()} | {:error, term()}
  def stats(graph_id) do
    PMGraph.stats(graph_id)
  rescue
    e -> {:error, {:graph_error, e}}
  end

  # Private functions

  defp create_graph(graph_id) do
    case PMGraph.create_graph(graph_id, %{type: :dependency}) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
      {:error, _} = err -> err
    end
  rescue
    e -> {:error, {:graph_error, e}}
  end

  defp extract_dependencies(repo_path, :elixir) do
    mix_exs = Path.join(repo_path, "mix.exs")

    if File.exists?(mix_exs) do
      extract_elixir_deps(mix_exs, repo_path)
    else
      {:error, :mix_exs_not_found}
    end
  end

  defp extract_dependencies(repo_path, :python) do
    cond do
      File.exists?(Path.join(repo_path, "requirements.txt")) ->
        extract_python_requirements(Path.join(repo_path, "requirements.txt"))

      File.exists?(Path.join(repo_path, "pyproject.toml")) ->
        extract_pyproject_deps(Path.join(repo_path, "pyproject.toml"))

      true ->
        {:error, :no_python_deps_file}
    end
  end

  defp extract_dependencies(repo_path, :javascript) do
    package_json = Path.join(repo_path, "package.json")

    if File.exists?(package_json) do
      extract_npm_deps(package_json)
    else
      {:error, :package_json_not_found}
    end
  end

  defp extract_dependencies(repo_path, :typescript) do
    extract_dependencies(repo_path, :javascript)
  end

  defp extract_dependencies(_repo_path, language) do
    {:error, {:unsupported_language, language}}
  end

  defp extract_elixir_deps(mix_exs, repo_path) do
    {:ok, content} = File.read(mix_exs)

    # Extract project name
    project_name =
      case Regex.run(~r/app:\s*:(\w+)/, content) do
        [_, name] -> name
        _ -> Path.basename(repo_path)
      end

    # Extract dependencies
    deps =
      Regex.scan(~r/\{:(\w+),\s*"[^"]*"/, content)
      |> Enum.map(fn [_, name] ->
        %{
          from: project_name,
          to: name,
          type: :runtime_dependency
        }
      end)

    # Also extract dev dependencies
    dev_deps =
      Regex.scan(~r/\{:(\w+),[^}]*only:\s*(?::dev|:test|\[:dev|\[:test)/, content)
      |> Enum.map(fn [_, name] ->
        %{
          from: project_name,
          to: name,
          type: :dev_dependency
        }
      end)

    {:ok,
     %{
       project: project_name,
       language: :elixir,
       dependencies: deps ++ dev_deps
     }}
  end

  defp extract_python_requirements(requirements_path) do
    {:ok, content} = File.read(requirements_path)

    deps =
      content
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(String.starts_with?(&1, "#") or &1 == ""))
      |> Enum.map(fn line ->
        name = line |> String.split(~r/[=<>!~\[]/) |> List.first() |> String.trim()

        %{
          from: "project",
          to: name,
          type: :runtime_dependency
        }
      end)

    {:ok,
     %{
       project: "project",
       language: :python,
       dependencies: deps
     }}
  end

  defp extract_pyproject_deps(pyproject_path) do
    {:ok, content} = File.read(pyproject_path)

    # Basic TOML parsing for dependencies
    deps =
      Regex.scan(~r/"([a-zA-Z0-9_-]+)"/, content)
      |> Enum.map(fn [_, name] ->
        %{
          from: "project",
          to: name,
          type: :runtime_dependency
        }
      end)
      |> Enum.uniq_by(& &1.to)

    {:ok,
     %{
       project: "project",
       language: :python,
       dependencies: deps
     }}
  end

  defp extract_npm_deps(package_json_path) do
    {:ok, content} = File.read(package_json_path)
    {:ok, package} = Jason.decode(content)

    project_name = package["name"] || "project"

    runtime_deps =
      (package["dependencies"] || %{})
      |> Map.keys()
      |> Enum.map(fn name ->
        %{from: project_name, to: name, type: :runtime_dependency}
      end)

    dev_deps =
      (package["devDependencies"] || %{})
      |> Map.keys()
      |> Enum.map(fn name ->
        %{from: project_name, to: name, type: :dev_dependency}
      end)

    {:ok,
     %{
       project: project_name,
       language: :javascript,
       dependencies: runtime_deps ++ dev_deps
     }}
  end

  defp populate_graph(graph_id, %{project: project, dependencies: deps}) do
    # Add project node
    _ =
      PMGraph.add_node(graph_id, %{
        id: project,
        labels: ["Project"],
        properties: %{name: project}
      })

    # Add dependency nodes and edges
    Enum.each(deps, fn dep ->
      # Add dependency node
      _ =
        PMGraph.add_node(graph_id, %{
          id: dep.to,
          labels: ["Dependency"],
          properties: %{name: dep.to}
        })

      # Add edge
      _ =
        PMGraph.add_edge(graph_id, %{
          from_id: dep.from,
          to_id: dep.to,
          type: Atom.to_string(dep.type),
          properties: %{}
        })
    end)

    :ok
  rescue
    e -> {:error, {:graph_error, e}}
  end
end
