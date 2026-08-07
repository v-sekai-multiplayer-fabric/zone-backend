# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
import Config

config :uro, Uro.Endpoint,
  debug_errors: true,
  code_reloader: true,
  check_origin: false

config :uro, Uro.Mailer, adapter: Swoosh.Adapters.Local

config :open_api_spex, :cache_adapter, OpenApiSpex.Plug.NoneCache

config :logger, :console, format: "[$level] $message\n"
config :logger, level: :debug

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :uro, Uro.Repo,
  show_sensitive_data_on_connection_error: true,
  url: System.get_env("DATABASE_URL"),
  username: "vsekai",
  password: "vsekai",
  hostname: "localhost",
  port: 26257,
  database: "vsekai",
  stacktrace: true,
  migration_lock: false,
  pool_size: 10
