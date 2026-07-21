# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule WeftWarpBurrito.SandboxNif do
  @moduledoc """
  Fine (elixir-nx/fine) bindings for c_src/nif/weft_sandbox_nif.cpp.
  Not meant to be called directly - see `WeftWarpBurrito.Program`, the
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
    path = Path.join(:code.priv_dir(:uro), "weft_sandbox_nif")
    :erlang.load_nif(String.to_charlist(path), 0)
  end

  @doc "Loads a RISC-V ELF (binary) using the tagged-GuestValue host-call ABI as a program resource."
  def new_program_nif(_elf_binary), do: :erlang.nif_error(:nif_not_loaded)

  @doc """
  Calls an exported function of a compiled program with tagged GuestValue
  arguments. Returns `{:ok, tagged}` when the guest finishes, or
  `{:host_call, op, a, b}` when it trapped to the host-math ecall (RFD
  0018) -- compute in Elixir, then `program_resume_nif/2`.
  """
  def program_call_nif(_resource, _function, _args, _fuel), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Injects a host-call result and continues the stopped program."
  def program_resume_nif(_resource, _result), do: :erlang.nif_error(:nif_not_loaded)
end
