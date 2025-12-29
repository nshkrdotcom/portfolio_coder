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

# Hammer rate limiter config for tests
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}

config :logger, level: :warning
