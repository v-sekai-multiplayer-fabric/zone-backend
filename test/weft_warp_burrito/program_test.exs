# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule WeftWarpBurrito.ProgramTest do
  use ExUnit.Case, async: true

  alias WeftWarpBurrito.Program

  setup do
    elf_path = Path.join(:code.priv_dir(:uro), "s7_basic.elf")
    pid = start_supervised!({Program, elf: File.read!(elf_path)})
    %{pid: pid}
  end

  test "fixnum arithmetic stays in the guest", %{pid: pid} do
    assert {:ok, 7} = Program.call(pid, "add", [3, 4])
    assert {:ok, -5} = Program.call(pid, "add", [5, -10])
  end

  test "boolean results decode", %{pid: pid} do
    assert {:ok, true} = Program.call(pid, "lt", [3, 4])
    assert {:ok, false} = Program.call(pid, "lt", [4, 3])
  end

  test "closures work inside the compiled program", %{pid: pid} do
    # (inc (dbl 20)) = 41
    assert {:ok, 41} = Program.call(pid, "compose-demo", [20])
  end

  test "bignum result crosses to the BEAM as a real Elixir integer", %{pid: pid} do
    assert {:ok, result} = Program.call(pid, "bigfact", [25])
    assert result == Enum.reduce(1..25, 1, &(&1 * &2))
    # Well past the 61-bit fixnum range -- this value only exists via
    # the host-call trampoline (RFD 0018).
    assert result > Bitwise.bsl(1, 60)
  end

  test "bignum intermediate values demote back to fixnums", %{pid: pid} do
    # fact(25) has six trailing zeros -> remainder 1_000_000 is 0.
    assert {:ok, 0} = Program.call(pid, "bigfact-rem", [25, 1_000_000])
  end

  test "lists cross as handles and structural ops trampoline", %{pid: pid} do
    assert {:ok, 15} = Program.call(pid, "sum-list", [[1, 2, 3, 4, 5]])
    assert {:ok, 20} = Program.call(pid, "second", [[10, 20, 30]])
    # Guest-built list decodes back as a real Elixir list.
    assert {:ok, [1, 2, 3]} = Program.call(pid, "build-list", [1, 2])
  end

  test "tuples map to scheme vectors", %{pid: pid} do
    assert {:ok, 40} = Program.call(pid, "tuple-pick", [{7, 40, 9}])
    assert {:ok, 3} = Program.call(pid, "tuple-size", [{7, 40, 9}])
  end

  test "maps answer hash-table-ref; missing key is false", %{pid: pid} do
    assert {:ok, 100} = Program.call(pid, "map-get", [%{hp: 100, mp: 30}, :hp])
    assert {:ok, false} = Program.call(pid, "map-get", [%{hp: 100}, :armor])
  end

  test "binaries answer string-length in bytes", %{pid: pid} do
    assert {:ok, 5} = Program.call(pid, "bin-size", ["hello"])
  end

  test "atoms are interned so eq? works across the boundary", %{pid: pid} do
    assert {:ok, true} = Program.call(pid, "same?", [:fire, :fire])
    assert {:ok, false} = Program.call(pid, "same?", [:fire, :water])
  end

  test "unknown function is a clean error", %{pid: pid} do
    assert {:error, :no_such_function} = Program.call(pid, "nope", [])
  end

  test "gas exhaustion is a clean error", %{pid: pid} do
    assert {:error, :gas_exhausted} = Program.call(pid, "bigfact", [25], 1_000)
  end
end
