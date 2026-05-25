# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
import Config
require Logger

Code.require_file("config/helpers.exs")
Code.ensure_loaded!(Uro.Config.Helpers)
alias Uro.Config.Helpers

compile_phase? = System.get_env("COMPILE_PHASE") != "false"

get_env = fn key, example ->
  case compile_phase? do
    true ->
      example

    false ->
      System.get_env(key) ||
        raise """
        Environment variable "#{key}" is required but not set.
        """
  end
end

get_optional_env = fn key ->
  System.get_env(key)
end

config :uro,
  compile_phase?: System.get_env("COMPILE_PHASE") != "false"

config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

url =
  "URL"
  |> get_env.("https://vsekai.local/")
  |> URI.new!()

root_origin =
  "ROOT_ORIGIN"
  |> get_env.("https://vsekai.local")
  |> URI.new!()

config :uro,
  ecto_repos: [Uro.Repo, Uro.Repo.Migration],
  url: url,
  frontend_url:
    "FRONTEND_URL"
    |> Helpers.get_env("https://vsekai.local/")
    |> URI.new!(),
  root_origin: root_origin

crdb_sni =
  case System.get_env("CRDB_SNI") do
    nil -> :disable
    name -> String.to_charlist(name)
  end

crdb_ssl =
  case System.get_env("CRDB_CA_CERT") do
    nil ->
      false

    ca ->
      [
        cacertfile: ca,
        certfile: System.get_env("CRDB_CLIENT_CERT"),
        keyfile: System.get_env("CRDB_CLIENT_KEY"),
        verify: :verify_peer,
        server_name_indication: crdb_sni
      ]
  end

crdb_admin_ssl =
  case System.get_env("CRDB_CA_CERT") do
    nil ->
      false

    ca ->
      [
        cacertfile: ca,
        certfile: System.get_env("CRDB_ADMIN_CERT"),
        keyfile: System.get_env("CRDB_ADMIN_KEY"),
        verify: :verify_peer,
        server_name_indication: crdb_sni
      ]
  end

# DML repo — gateway_writer, no DDL privilege
config :uro, Uro.Repo,
  adapter: Ecto.Adapters.Postgres,
  url:
    Helpers.get_env(
      "DATABASE_URL",
      "postgresql://gateway_writer@multiplayer-fabric-crdb.internal:26257/uro?sslmode=verify-full"
    ),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10,
  prepare: :unnamed,
  migration_lock: false,
  socket_options: [:inet6],
  ssl: crdb_ssl

# DDL repo — gateway_admin, used only for ecto.migrate.
# Shares the same migration files as Uro.Repo (priv: "priv/repo").
config :uro, Uro.Repo.Migration,
  priv: "priv/repo",
  adapter: Ecto.Adapters.Postgres,
  url:
    Helpers.get_env(
      "MIGRATION_DATABASE_URL",
      "postgresql://gateway_admin@multiplayer-fabric-crdb.internal:26257/uro?sslmode=verify-full"
    ),
  pool_size: 2,
  prepare: :unnamed,
  migration_lock: false,
  socket_options: [:inet6],
  ssl: crdb_admin_ssl

https_port = String.to_integer(System.get_env("HTTPS_PORT") || "443")
http_port = String.to_integer(Helpers.get_env("PORT", "4000"))

https_opts =
  case {System.get_env("HTTPS_CERTFILE"), System.get_env("HTTPS_KEYFILE")} do
    {cert, key} when is_binary(cert) and is_binary(key) ->
      [https: [port: https_port, certfile: cert, keyfile: key]]

    _ ->
      []
  end

config :uro, Uro.Endpoint,
  [{:adapter, Bandit.PhoenixAdapter},
   {:url, Map.take(url, [:scheme, :host, :path])},
   {:http, [port: http_port]},
   {:secret_key_base, get_env.("PHOENIX_KEY_BASE", nil)}
  ] ++ https_opts

# pubsub_server: Uro.PubSub,
# live_view: [signing_salt: "0dBPUwA2"]

root_origin =
  "ROOT_ORIGIN"
  |> Helpers.get_env("https://example.com")
  |> URI.new!()

config :cors_plug,
  origin: [URI.to_string(root_origin)],
  max_age: 86400

config :joken, default_signer: Helpers.get_env("JOKEN_SIGNER", "gqawCOER09ZZjaN8W2QM9XT9BeJSZ9qc")

config :uro, :stale_zone_cutoff,
  amount: 3,
  calendar_type: "month"

config :uro, :stale_zone_interval, 30 * 24 * 60 * 60 * 1000

config :uro, Uro.Turnstile,
  secret_key:
    get_optional_env.("TURNSTILE_SECRET_KEY") ||
      Logger.warning(
        "Turnstile (a reCaptcha alternative) is disabled because the environment variable TURNSTILE_SECRET_KEY is not set. For more information, see https://developers.cloudflare.com/turnstile/get-started/."
      )

config :uro, :pow,
  user: Uro.Accounts.User,
  users_context: Uro.Accounts,
  repo: Uro.Repo,
  web_module: Uro,
  extensions: [PowPersistentSession],
  controller_callbacks: Pow.Extension.Phoenix.ControllerCallbacks,
  routes_backend: Uro.Pow.Routes,
  cache_store_backend: Uro.Pow.DetsCache

config :uro, :pow_assent,
  user_identities_context: Uro.UserIdentities,
  providers:
    (case(compile_phase?) do
       true ->
         []

       false ->
         System.get_env()
         |> Map.filter(fn {k, _} -> String.match?(k, ~r/^OAUTH2_.+_STRATEGY/) end)
         |> Enum.map(fn {key, module_name} ->
           key =
             key
             |> String.replace("OAUTH2_", "")
             |> String.replace("_STRATEGY", "")

           {
             key
             |> String.downcase()
             |> String.to_atom(),
             [
               client_id: get_env.("OAUTH2_#{key}_CLIENT_ID", nil),
               client_secret: get_env.("OAUTH2_#{key}_CLIENT_SECRET", nil),
               strategy: Module.concat([module_name])
             ]
           }
         end)
     end)

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :waffle,
  storage: Waffle.Storage.Local

# storage_dir: "uploads"

# aria-storage chunk bucket — served by AriaStorage.ChunkServerPlug at /chunks/*.
# In production, Waffle.Storage.S3 is configured in prod.exs using AWS_* env vars.
config :aria_storage, :waffle_bucket, System.get_env("CHUNK_BUCKET", "zone-chunks")

# aria-storage uses SQLite for internal chunk metadata.
# zone-backend stores the file under its priv directory.
config :aria_storage, AriaStorage.Repo,
  database: System.get_env("ARIA_STORAGE_DB", "/app/priv/aria_storage.db")

import_config "#{Mix.env()}.exs"

if Mix.env() == "dev" do
  import_config "local.exs"
end
