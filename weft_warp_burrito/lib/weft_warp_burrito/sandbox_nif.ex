# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule WeftWarpBurrito.SandboxNif do
  @moduledoc """
  Fine (elixir-nx/fine) bindings for c_src/nif/weft_sandbox_nif.cpp -
  see rfd/0003 for why Fine rather than hand-rolled erl_nif marshalling.
  Not meant to be called directly - see `WeftWarpBurrito.Sandbox`, the
  GenServer actor that owns one Machine resource per process and is the
  actual public API.

  This module's only job is loading the compiled NIF; every function
  below is replaced by the native implementation once `on_load/0` runs
  (`:erlang.load_nif/2`), the standard Elixir NIF idiom - the Elixir
  stubs exist only so calling this module before the NIF loads (or on
  a platform where it fails to load) raises rather than silently doing
  nothing.
  """

  @on_load :load_nif

  def load_nif do
    path = Path.join(:code.priv_dir(:weft_warp_burrito), "weft_sandbox_nif")
    :erlang.load_nif(String.to_charlist(path), 0)
  end

  @doc "Loads guest ELF at `path`, running guest_init() once. Returns {:ok, resource} | {:error, reason}."
  def new_sandbox_nif(_path), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Runs one fixed, named guest capability with a fuel (gas) budget.
  `capability` is one of :loot_roll | :combat_replay | :progression_replay -
  never an arbitrary caller-supplied symbol name (see the NIF source's
  own header comment for why: a generic "call this named guest symbol"
  entry point would defeat the whole point of a closed capability set).
  """
  def call_capability_nif(_resource, _capability, _fuel), do: :erlang.nif_error(:nif_not_loaded)
end
