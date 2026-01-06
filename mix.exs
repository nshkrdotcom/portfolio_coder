defmodule PortfolioCoder.MixProject do
  use Mix.Project

  @version "0.4.0"
  @source_url "https://github.com/nshkrdotcom/portfolio_coder"

  def project do
    [
      app: :portfolio_coder,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Hex
      description: description(),
      package: package(),

      # Docs
      name: "PortfolioCoder",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),

      # Testing
      test_coverage: [tool: ExCoveralls],

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix],
        flags: [:error_handling, :unknown]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PortfolioCoder.Application, []}
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Portfolio Ecosystem (local path for development)
      {:portfolio_manager, path: "../portfolio_manager", override: true},
      {:portfolio_index, path: "../portfolio_index", override: true},
      {:portfolio_core, path: "../portfolio_core", override: true},

      # Code Parsing
      {:sourceror, "~> 1.0"},

      # File utilities
      {:file_system, "~> 1.0"},

      # JSON
      {:jason, "~> 1.4"},

      # YAML
      {:yaml_elixir, "~> 2.9"},

      # Telemetry
      {:telemetry, "~> 1.2"},

      # Development
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.1", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      quality: ["format --check-formatted", "credo --strict", "dialyzer"],
      "quality.ci": ["format --check-formatted", "credo --strict"]
    ]
  end

  defp description do
    """
    Code Intelligence Platform built on the Portfolio RAG ecosystem.
    Repository analysis, semantic code search, dependency graphs, and
    AI-powered code understanding with multi-language support.
    """
  end

  defp package do
    [
      name: "portfolio_coder",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Portfolio Ecosystem" => "https://github.com/nshkrdotcom/portfolio_core"
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md assets),
      maintainers: ["nshkrdotcom"]
    ]
  end

  defp docs do
    [
      main: "readme",
      assets: %{"assets" => "assets"},
      logo: "assets/portfolio_coder.svg",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_modules: [
        Core: [
          PortfolioCoder,
          PortfolioCoder.Indexer,
          PortfolioCoder.Search
        ],
        Portfolio: [
          PortfolioCoder.Portfolio.Config,
          PortfolioCoder.Portfolio.Registry,
          PortfolioCoder.Portfolio.Context,
          PortfolioCoder.Portfolio.Relationships,
          PortfolioCoder.Portfolio.Scanner,
          PortfolioCoder.Portfolio.Syncer
        ],
        Parsers: [
          PortfolioCoder.Parsers,
          PortfolioCoder.Parsers.Elixir,
          PortfolioCoder.Parsers.Python,
          PortfolioCoder.Parsers.JavaScript
        ],
        Graph: [
          PortfolioCoder.Graph,
          PortfolioCoder.Graph.Dependency,
          PortfolioCoder.Graph.CallGraph
        ],
        Tools: [
          PortfolioCoder.Tools,
          PortfolioCoder.Tools.SearchCode,
          PortfolioCoder.Tools.ReadFile,
          PortfolioCoder.Tools.ListFiles,
          PortfolioCoder.Tools.AnalyzeCode
        ],
        "CLI - Code": [
          Mix.Tasks.Code.Index,
          Mix.Tasks.Code.Search,
          Mix.Tasks.Code.Ask,
          Mix.Tasks.Code.Deps
        ],
        "CLI - Portfolio": [
          Mix.Tasks.Portfolio.List,
          Mix.Tasks.Portfolio.Show,
          Mix.Tasks.Portfolio.Scan,
          Mix.Tasks.Portfolio.Add,
          Mix.Tasks.Portfolio.Remove,
          Mix.Tasks.Portfolio.Sync,
          Mix.Tasks.Portfolio.Status,
          Mix.Tasks.Portfolio.Search,
          Mix.Tasks.Portfolio.Ask
        ]
      ]
    ]
  end
end
