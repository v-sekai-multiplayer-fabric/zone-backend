# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.CLITest do
  use ExUnit.Case, async: true

  alias Taskweft.CLI

  @domains Path.join(:code.priv_dir(:taskweft), "plans/domains")
  @problems Path.join(:code.priv_dir(:taskweft), "plans/problems")

  defp domain(name), do: Path.join(@domains, name)
  defp problem(name), do: Path.join(@problems, name)

  describe "meta subcommands (no NIF)" do
    test "version prints name, version, and build commit" do
      assert {:ok, out} = CLI.run(["version"])
      assert IO.iodata_to_binary(out) =~ ~r/^taskweft \d+\.\d+\.\d+(-[0-9A-Za-z.-]+)? \(.+\)$/
    end

    test "--version alias" do
      assert {:ok, out} = CLI.run(["--version"])
      assert IO.iodata_to_binary(out) =~ "taskweft"
    end

    test "help lists the subcommands" do
      assert {:ok, out} = CLI.run(["help"])
      text = IO.iodata_to_binary(out)
      assert text =~ "taskweft plan"
      assert text =~ "taskweft mcp"
      assert text =~ "taskweft replan"
    end
  end

  describe "mcp option parsing" do
    test "bare mcp has no port/host set (server.ex applies its own defaults)" do
      assert {:mcp, opts} = CLI.run(["mcp"])
      assert opts[:port] == nil
      assert opts[:host] == nil
    end

    test "--http is accepted as a no-op (HTTP is the only transport)" do
      assert {:mcp, opts} = CLI.run(["mcp", "--http"])
      assert opts == []
    end

    test "--port parses the integer" do
      assert {:mcp, opts} = CLI.run(["mcp", "--port", "8080"])
      assert opts[:port] == 8080
    end

    test "--host is accepted" do
      assert {:mcp, opts} = CLI.run(["mcp", "--http", "--host", "0.0.0.0"])
      assert opts[:host] == "0.0.0.0"
    end

    test "non-integer --port is an error" do
      assert {:error, msg, 2} = CLI.run(["mcp", "--port", "nope"])
      assert IO.iodata_to_binary(msg) =~ "--port must be an integer"
    end

    test "unknown mcp option is an error" do
      assert {:error, msg, 2} = CLI.run(["mcp", "--bogus"])
      assert IO.iodata_to_binary(msg) =~ "unknown option"
    end
  end

  describe "input errors" do
    test "missing domain file" do
      assert {:error, msg, 1} = CLI.run(["plan", "does-not-exist.jsonld"])
      assert IO.iodata_to_binary(msg) =~ "cannot read"
    end

    test "replan with a non-integer fail step" do
      assert {:error, msg, 2} = CLI.run(["replan", "x", domain("blocks_world.jsonld")])
      assert IO.iodata_to_binary(msg) =~ "must be an integer"
    end

    test "replan with no arguments" do
      assert {:error, _msg, 2} = CLI.run(["replan"])
    end
  end

  describe "planner subcommands (through the NIF)" do
    @describetag :nif

    test "plan on a self-contained domain prints a bare JSON step array" do
      assert {:ok, out} = CLI.run(["plan", domain("blocks_world.jsonld")])
      {:ok, steps} = out |> IO.iodata_to_binary() |> Jason.decode()
      assert is_list(steps)
      assert Enum.all?(steps, &is_list/1)
    end

    test "a bare domain path (no subcommand) is treated as plan" do
      assert {:ok, bare} = CLI.run([domain("blocks_world.jsonld")])
      assert {:ok, viaplan} = CLI.run(["plan", domain("blocks_world.jsonld")])
      assert IO.iodata_to_binary(bare) == IO.iodata_to_binary(viaplan)
    end

    test "replan echoes the original plan (issue #43 shape) and recovers" do
      assert {:ok, out} = CLI.run(["replan", "0", domain("blocks_world.jsonld")])
      {:ok, decoded} = out |> IO.iodata_to_binary() |> Jason.decode()
      assert is_list(decoded["original_plan"])
      assert decoded["original_plan"] != []
    end

    test "--problem merges the problem's tasks, changing the plan" do
      # blocks_world_1a fixes a goal that differs from the domain default,
      # so the merged plan must differ from the domain-only plan.
      assert {:ok, merged} =
               CLI.run([
                 "plan",
                 "--problem",
                 domain("blocks_world.jsonld"),
                 problem("blocks_world_1a.jsonld")
               ])

      assert {:ok, base} = CLI.run(["plan", domain("blocks_world.jsonld")])
      assert IO.iodata_to_binary(merged) != IO.iodata_to_binary(base)
    end
  end
end
