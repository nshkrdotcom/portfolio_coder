defmodule PortfolioCoder.Portfolio.Config do
  @moduledoc """
  Manages portfolio configuration and paths.

  The portfolio configuration is stored in a `config.yml` file in the portfolio
  repository root. This module provides functions to read and access configuration
  values.

  ## Configuration

  Set the portfolio path in your application config:

      config :portfolio_coder,
        portfolio_path: "~/p/g/n/portfolio"

  Or via environment variable:

      export PORTFOLIO_DIR=~/p/g/n/portfolio

  """

  @default_portfolio_path "~/p/g/n/portfolio"

  @doc """
  Returns the default portfolio path.
  """
  @spec default_portfolio_path() :: String.t()
  def default_portfolio_path, do: @default_portfolio_path

  @doc """
  Returns the configured portfolio path, expanded to an absolute path.
  """
  @spec portfolio_path() :: String.t()
  def portfolio_path do
    path =
      System.get_env("PORTFOLIO_DIR") ||
        Application.get_env(:portfolio_coder, :portfolio_path, @default_portfolio_path)

    expand_path(path)
  end

  @doc """
  Expands a path, replacing ~ with the user's home directory.
  """
  @spec expand_path(String.t()) :: String.t()
  def expand_path(path) do
    path
    |> String.replace_leading("~", System.user_home!())
    |> Path.expand()
  end

  @doc """
  Checks if the portfolio directory exists.
  """
  @spec exists?() :: boolean()
  def exists? do
    path = portfolio_path()
    File.dir?(path) and File.exists?(Path.join(path, "config.yml"))
  end

  @doc """
  Loads and parses the portfolio configuration from config.yml.
  """
  @spec load() :: {:ok, map()} | {:error, term()}
  def load do
    config_path = Path.join(portfolio_path(), "config.yml")

    case File.read(config_path) do
      {:ok, content} ->
        case YamlElixir.read_from_string(content) do
          {:ok, config} -> {:ok, config}
          {:error, reason} -> {:error, {:parse_error, reason}}
        end

      {:error, reason} ->
        {:error, {:file_error, reason}}
    end
  end

  @doc """
  Returns the list of directories to scan for repositories.
  """
  @spec scan_directories() :: [String.t()]
  def scan_directories do
    case load() do
      {:ok, config} ->
        config
        |> get_in(["scan", "directories"])
        |> List.wrap()
        |> Enum.map(&expand_path/1)

      {:error, _} ->
        []
    end
  end

  @doc """
  Returns the list of patterns to exclude when scanning.
  """
  @spec exclude_patterns() :: [String.t()]
  def exclude_patterns do
    case load() do
      {:ok, config} ->
        config
        |> get_in(["scan", "exclude_patterns"])
        |> List.wrap()

      {:error, _} ->
        default_exclude_patterns()
    end
  end

  @doc """
  Retrieves a nested configuration value.

  ## Examples

      iex> Config.get(["portfolio", "name"])
      {:ok, "My Portfolio"}

      iex> Config.get(["missing", "key"], "default")
      {:ok, "default"}

  """
  @spec get(list(String.t()), term()) :: {:ok, term()} | {:error, :not_found}
  def get(keys, default \\ nil)

  def get(keys, default) when is_list(keys) do
    case load() do
      {:ok, config} ->
        case get_in(config, keys) do
          nil when is_nil(default) -> {:error, :not_found}
          nil -> {:ok, default}
          value -> {:ok, value}
        end

      {:error, _} when is_nil(default) ->
        {:error, :not_found}

      {:error, _} ->
        {:ok, default}
    end
  end

  @doc """
  Returns the path to the repos directory in the portfolio.
  """
  @spec repos_path() :: String.t()
  def repos_path do
    Path.join(portfolio_path(), "repos")
  end

  @doc """
  Returns the path to the registry.yml file.
  """
  @spec registry_path() :: String.t()
  def registry_path do
    Path.join(portfolio_path(), "registry.yml")
  end

  @doc """
  Returns the path to the relationships.yml file.
  """
  @spec relationships_path() :: String.t()
  def relationships_path do
    Path.join(portfolio_path(), "relationships.yml")
  end

  # Private helpers

  defp default_exclude_patterns do
    [
      "**/node_modules/**",
      "**/.git/**",
      "**/deps/**",
      "**/_build/**",
      "**/__pycache__/**",
      "**/.pytest_cache/**"
    ]
  end
end
