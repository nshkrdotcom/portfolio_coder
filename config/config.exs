import Config

config :portfolio_coder,
  default_index: "default",
  default_graph: "dependencies",
  supported_languages: [:elixir, :python, :javascript, :typescript],
  chunk_size: 1000,
  chunk_overlap: 200,
  exclude_patterns: [
    "deps/",
    "_build/",
    "node_modules/",
    ".git/",
    "*.min.js",
    "*.map"
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
