defmodule PortfolioCoder do
  @moduledoc """
  Code Intelligence Platform built on the Portfolio RAG Ecosystem.

  Portfolio Coder provides:
  - Repository indexing with multi-language support
  - Semantic code search
  - Dependency graph building and querying
  - AI-powered code analysis

  ## Quick Start

      # Index a repository
      {:ok, stats} = PortfolioCoder.index_repo("/path/to/repo")

      # Search code
      {:ok, results} = PortfolioCoder.search_code("authentication")

      # Ask questions
      {:ok, answer} = PortfolioCoder.ask("How does this work?")

  ## Configuration

  Configure in your manifest or application config:

      config :portfolio_coder,
        default_index: "default",
        supported_languages: [:elixir, :python, :javascript]
  """

  alias PortfolioCoder.Graph
  alias PortfolioCoder.Indexer
  alias PortfolioCoder.Search

  @doc """
  Returns the current version of Portfolio Coder.
  """
  @spec version() :: String.t()
  def version, do: "0.1.0"

  @doc """
  Index a code repository.

  Scans the repository for source files, parses them, chunks the content,
  and stores embeddings in the configured vector store.

  ## Options

    - `:index_id` - Name of the index (default: "default")
    - `:languages` - List of languages to index (default: all supported)
    - `:exclude` - Patterns to exclude (default: deps/, _build/, etc.)
    - `:chunk_size` - Size of text chunks (default: 1000)
    - `:chunk_overlap` - Overlap between chunks (default: 200)

  ## Examples

      {:ok, stats} = PortfolioCoder.index_repo("/path/to/repo")
      {:ok, stats} = PortfolioCoder.index_repo("/path/to/repo",
        index_id: "my_project",
        languages: [:elixir]
      )
  """
  @spec index_repo(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def index_repo(repo_path, opts \\ []) do
    Indexer.index_repo(repo_path, opts)
  end

  @doc """
  Index specific files.

  ## Examples

      {:ok, stats} = PortfolioCoder.index_files(["/path/to/file.ex"])
  """
  @spec index_files([String.t()], keyword()) :: {:ok, map()} | {:error, term()}
  def index_files(file_paths, opts \\ []) do
    Indexer.index_files(file_paths, opts)
  end

  @doc """
  Semantic code search.

  Searches the indexed code using semantic similarity.

  ## Options

    - `:index_id` - Index to search (default: "default")
    - `:limit` - Maximum results (default: 10)
    - `:language` - Filter by language
    - `:file_pattern` - Filter by file pattern

  ## Examples

      {:ok, results} = PortfolioCoder.search_code("authentication middleware")
      {:ok, results} = PortfolioCoder.search_code("error handling",
        language: :elixir,
        limit: 5
      )
  """
  @spec search_code(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search_code(query, opts \\ []) do
    Search.semantic_search(query, opts)
  end

  @doc """
  Text-based code search.

  Searches using keyword matching.

  ## Examples

      {:ok, results} = PortfolioCoder.search_text("def handle_call")
  """
  @spec search_text(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search_text(query, opts \\ []) do
    Search.text_search(query, opts)
  end

  @doc """
  Ask a question about the codebase.

  Uses RAG to retrieve relevant code and generate an answer.

  ## Options

    - `:index_id` - Index to query (default: "default")
    - `:strategy` - RAG strategy (default: :hybrid)
    - `:k` - Number of chunks to retrieve (default: 5)

  ## Examples

      {:ok, answer} = PortfolioCoder.ask("How does authentication work?")
      {:ok, answer} = PortfolioCoder.ask("What patterns are used?",
        strategy: :self_rag
      )
  """
  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(question, opts \\ []) do
    Search.ask(question, opts)
  end

  @doc """
  Stream an answer about the codebase.

  ## Examples

      PortfolioCoder.stream_ask("Explain the architecture", fn chunk ->
        IO.write(chunk)
      end)
  """
  @spec stream_ask(String.t(), (String.t() -> any()), keyword()) :: :ok | {:error, term()}
  def stream_ask(question, callback, opts \\ []) when is_function(callback, 1) do
    Search.stream_ask(question, callback, opts)
  end

  @doc """
  Build a dependency graph from a repository.

  ## Options

    - `:language` - Language to analyze (default: auto-detect)

  ## Examples

      {:ok, stats} = PortfolioCoder.build_dependency_graph("deps", "/path/to/repo")
  """
  @spec build_dependency_graph(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def build_dependency_graph(graph_id, repo_path, opts \\ []) do
    Graph.build_dependency_graph(graph_id, repo_path, opts)
  end

  @doc """
  Get dependencies of a module/package.

  ## Examples

      {:ok, deps} = PortfolioCoder.get_dependencies("deps", "MyApp.Core")
  """
  @spec get_dependencies(String.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def get_dependencies(graph_id, entity, opts \\ []) do
    Graph.get_dependencies(graph_id, entity, opts)
  end

  @doc """
  Get modules/packages that depend on an entity.

  ## Examples

      {:ok, dependents} = PortfolioCoder.get_dependents("deps", "MyApp.Utils")
  """
  @spec get_dependents(String.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def get_dependents(graph_id, entity, opts \\ []) do
    Graph.get_dependents(graph_id, entity, opts)
  end

  @doc """
  Find circular dependencies.

  ## Examples

      {:ok, cycles} = PortfolioCoder.find_cycles("deps")
  """
  @spec find_cycles(String.t()) :: {:ok, [[String.t()]]} | {:error, term()}
  def find_cycles(graph_id) do
    Graph.find_cycles(graph_id)
  end

  @doc """
  Find usages of a symbol in the codebase.

  ## Examples

      {:ok, usages} = PortfolioCoder.find_usages("MyApp.User", index_id: "my_project")
  """
  @spec find_usages(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def find_usages(symbol, opts \\ []) do
    Search.find_usages(symbol, opts)
  end

  @doc """
  Get supported languages.
  """
  @spec supported_languages() :: [atom()]
  def supported_languages do
    Application.get_env(:portfolio_coder, :supported_languages, [:elixir, :python, :javascript])
  end
end
