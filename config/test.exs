import Config

config :portfolio_coder,
  log_level: :warning

config :portfolio_manager,
  env: :test,
  start_repo: false,
  start_router: false

config :portfolio_index,
  start_repo: false,
  start_boltx: false,
  start_telemetry: false

config :logger, level: :warning
