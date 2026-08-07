# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
import Config

# Everything else that used to live here (Mailer, ex_aws, opentelemetry,
# Endpoint's server: true) needed a real deploy-time secret or URL, and
# now lives in config/runtime.exs's `if config_env() == :prod do` block
# instead, which a real OTP release actually re-evaluates at boot.
# Use S3-compatible storage (versitygw) for Waffle uploads and
# aria-storage chunks in prod; dev/test use Waffle.Storage.Local
# (config.exs's default). This is just an atom, not a secret, so it is
# safe to bake in at compile time.
config :waffle, storage: Waffle.Storage.S3

config :logger, level: :info
