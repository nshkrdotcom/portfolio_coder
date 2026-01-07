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

# Hammer rate limiter config (required by portfolio_index dependency)
config :hammer,
  backend:
    {Hammer.Backend.ETS,
     [
       # 2 hours
       expiry_ms: 60_000 * 60 * 2,
       # 10 minutes
       cleanup_interval_ms: 60_000 * 10
     ]}

import_config "#{config_env()}.exs"
