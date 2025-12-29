defmodule PortfolioCoder.Graph do
  @moduledoc """
  Code dependency graph building and analysis.

  Builds dependency graphs from code repositories and provides
  querying capabilities for dependency analysis.
  """

  alias PortfolioCoder.Graph.Dependency

  require Logger

  @doc """
  Build a dependency graph from a repository.

  ## Options

    - `:language` - Language to analyze (auto-detected if not specified)
  """
  @spec build_dependency_graph(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def build_dependency_graph(graph_id, repo_path, opts \\ []) do
    repo_path = Path.expand(repo_path)

    if File.dir?(repo_path) do
      language = opts[:language] || detect_project_language(repo_path)
      Dependency.build(graph_id, repo_path, language, opts)
    else
      {:error, {:not_a_directory, repo_path}}
    end
  end

  @doc """
  Get dependencies of an entity.
  """
  @spec get_dependencies(String.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def get_dependencies(graph_id, entity, opts \\ []) do
    depth = Keyword.get(opts, :depth, 1)
    Dependency.get_dependencies(graph_id, entity, depth)
  end

  @doc """
  Get dependents of an entity (reverse dependencies).
  """
  @spec get_dependents(String.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def get_dependents(graph_id, entity, opts \\ []) do
    depth = Keyword.get(opts, :depth, 1)
    Dependency.get_dependents(graph_id, entity, depth)
  end

  @doc """
  Find circular dependencies in the graph.
  """
  @spec find_cycles(String.t()) :: {:ok, [[String.t()]]} | {:error, term()}
  def find_cycles(graph_id) do
    Dependency.find_cycles(graph_id)
  end

  @doc """
  Get graph statistics.
  """
  @spec stats(String.t()) :: {:ok, map()} | {:error, term()}
  def stats(graph_id) do
    Dependency.stats(graph_id)
  end

  @doc """
  Detect the primary language of a project.
  """
  @spec detect_project_language(String.t()) :: atom()
  def detect_project_language(repo_path) do
    cond do
      File.exists?(Path.join(repo_path, "mix.exs")) -> :elixir
      File.exists?(Path.join(repo_path, "pyproject.toml")) -> :python
      File.exists?(Path.join(repo_path, "requirements.txt")) -> :python
      File.exists?(Path.join(repo_path, "setup.py")) -> :python
      File.exists?(Path.join(repo_path, "package.json")) -> :javascript
      File.exists?(Path.join(repo_path, "tsconfig.json")) -> :typescript
      true -> :unknown
    end
  end
end
