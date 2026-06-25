# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule UroLoop do
  @moduledoc """
  Hexagonal core for the game-loop cluster.

  No Ecto Repo, no HTTP, no Phoenix — pure dispatch through the
  `UroLoop.Ports.ProfileStore` port. The storage adapter is resolved at call time
  from application config so callers (and tests) can substitute a fake:

      # config/config.exs (zone-backend)
      config :uro, :loop_profile_store, Uro.Loop.EctoProfileStore

      # in tests
      Application.put_env(:uro, :loop_profile_store, MyFakeStore)

  The default adapter is `Uro.Loop.EctoProfileStore`, which lives in the
  zone-backend app and carries the only Repo dependency.
  """

  @doc """
  Replace each player's item set with the list provided in `profiles`.

  `profiles` is `[%{"name" => string, "items" => [integer]}]`.
  `store` is optional — omit to use the configured adapter.
  """
  def commit(profiles, store \\ nil) when is_list(profiles) do
    resolved = store || Application.get_env(:uro, :loop_profile_store, Uro.Loop.EctoProfileStore)
    resolved.commit(profiles)
  end
end
