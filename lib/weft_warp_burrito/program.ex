# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule WeftWarpBurrito.Program do
  @moduledoc """
  One actor per s7c-compiled RISC-V program (RFD 0018's BEAM half).

  Runs functions exported by ELFs produced by the in-repo s7 AOT
  compiler (`c_src/s7`), driving the host-call trampoline: when guest
  fixnum arithmetic overflows (or touches a bignum handle), the guest
  ecalls, the Machine stops with its state intact in the NIF resource,
  and this GenServer computes the operation with Elixir's native
  arbitrary-precision integers before resuming execution. Bignums
  therefore cross the boundary as real Elixir integers -- no GMP, no
  vendored numeric library.

  The per-call handle table lives here, in plain Elixir state, and is
  discarded when the call completes (godot-sandbox CurrentState
  semantics). Arguments must be fixnum-range integers or booleans for
  now; results may be arbitrarily large integers.
  """
  use GenServer

  import Bitwise

  alias WeftWarpBurrito.SandboxNif

  @default_fuel 100_000_000

  # Tagged GuestValue constants -- must match c_src/s7/value.h.
  @false_v 0x06
  @true_v 0x0E
  @nil_v 0x16
  @handle_tag 0x2
  @closure_tag 0x4
  @fixnum_min -(1 <<< 60)
  @fixnum_max (1 <<< 60) - 1

  # Host-math ops -- must match c_src/s7/value.h.
  @op_add 0
  @op_sub 1
  @op_mul 2
  @op_quot 3
  @op_rem 4
  @op_lt 5
  @op_eq 6

  ## Public API

  def start_link(opts) do
    {elf, opts} = Keyword.pop!(opts, :elf)
    GenServer.start_link(__MODULE__, elf, opts)
  end

  @doc """
  Calls an exported function with integer/boolean arguments. Returns
  `{:ok, value}` (integers may exceed fixnum range -- decoded from the
  handle table), or `{:error, reason}`.
  """
  def call(pid, function, args, fuel \\ @default_fuel) when is_list(args) do
    GenServer.call(pid, {:call, function, args, fuel}, :infinity)
  end

  ## GenServer callbacks

  @impl true
  def init(elf) when is_binary(elf) do
    case SandboxNif.new_program_nif(elf) do
      {:ok, resource} -> {:ok, %{resource: resource}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:call, function, args, fuel}, _from, state) do
    with {:ok, tagged_args} <- encode_args(args) do
      handles = %{next: 0, values: %{}}

      result =
        state.resource
        |> SandboxNif.program_call_nif(function, tagged_args, fuel)
        |> trampoline(state.resource, handles)

      {:reply, result, state}
    else
      error -> {:reply, error, state}
    end
  end

  ## Trampoline: keep computing host calls in Elixir until the guest
  ## finishes (or errors).

  defp trampoline({:host_call, op, a, b}, resource, handles) do
    case host_math(op, a, b, handles) do
      {:ok, tagged, handles} ->
        resource
        |> SandboxNif.program_resume_nif(tagged)
        |> trampoline(resource, handles)

      {:error, _} = error ->
        error
    end
  end

  defp trampoline({:ok, tagged}, _resource, handles), do: decode(tagged, handles)
  defp trampoline({:error, _} = error, _resource, _handles), do: error

  ## Host math (RFD 0018): Elixir integers ARE the bignums.

  defp host_math(op, a, b, handles) do
    with {:ok, x} <- unbox(a, handles),
         {:ok, y} <- unbox(b, handles) do
      case op do
        @op_add -> box(x + y, handles)
        @op_sub -> box(x - y, handles)
        @op_mul -> box(x * y, handles)
        @op_quot when y == 0 -> {:error, :division_by_zero}
        @op_quot -> box(div(x, y), handles)
        @op_rem when y == 0 -> {:error, :division_by_zero}
        @op_rem -> box(rem(x, y), handles)
        # Comparisons return RAW 0/1 (the guest tags them itself).
        @op_lt -> {:ok, if(x < y, do: 1, else: 0), handles}
        @op_eq -> {:ok, if(x == y, do: 1, else: 0), handles}
        _ -> {:error, :unknown_host_op}
      end
    end
  end

  defp unbox(tagged, handles) do
    cond do
      (tagged &&& 7) == 0 -> {:ok, tagged >>> 3}
      (tagged &&& 7) == @handle_tag -> fetch_handle(handles, tagged >>> 3)
      true -> {:error, :host_math_type_error}
    end
  end

  defp fetch_handle(handles, index) do
    case Map.fetch(handles.values, index) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :bad_handle}
    end
  end

  defp box(value, handles) when value >= @fixnum_min and value <= @fixnum_max do
    {:ok, value <<< 3, handles}
  end

  defp box(value, handles) do
    index = handles.next
    handles = %{handles | next: index + 1, values: Map.put(handles.values, index, value)}
    {:ok, index <<< 3 ||| @handle_tag, handles}
  end

  ## GuestValue codec

  defp encode_args(args) do
    Enum.reduce_while(args, {:ok, []}, fn arg, {:ok, acc} ->
      case encode_arg(arg) do
        {:ok, tagged} -> {:cont, {:ok, [tagged | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp encode_arg(value)
       when is_integer(value) and value >= @fixnum_min and
              value <= @fixnum_max,
       do: {:ok, value <<< 3}

  defp encode_arg(true), do: {:ok, @true_v}
  defp encode_arg(false), do: {:ok, @false_v}
  defp encode_arg(nil), do: {:ok, @nil_v}
  defp encode_arg(_), do: {:error, :unsupported_argument}

  defp decode(tagged, handles) do
    cond do
      (tagged &&& 7) == 0 -> {:ok, tagged >>> 3}
      tagged == @true_v -> {:ok, true}
      tagged == @false_v -> {:ok, false}
      tagged == @nil_v -> {:ok, nil}
      (tagged &&& 7) == @handle_tag -> fetch_handle(handles, tagged >>> 3)
      (tagged &&& 7) == @closure_tag -> {:ok, :closure}
      true -> {:error, {:undecodable, tagged}}
    end
  end
end
