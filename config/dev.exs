import Config

config :portfolio_coder,
  log_level: :debug

# Disable database connections for local Portfolio features
# (not needed for scanning/managing repos via YAML files)
config :portfolio_index,
  start_repo: false,
  start_boltx: false,
  start_telemetry: false

config :portfolio_manager,
  start_repo: false,
  start_router: false,
  manifest: %{}

config :logger, level: :debug
