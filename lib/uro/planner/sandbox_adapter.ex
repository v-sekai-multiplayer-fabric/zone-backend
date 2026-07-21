# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Planner.SandboxAdapter do
  @moduledoc """
  Planner adapter that finds a plan by running compiled Scheme
  (`c_src/s7/fixtures/planner.scm`, RFD 0023 -- Stage 5A of the sandbox
  roadmap) inside the libriscv guest, instead of the native
  `Taskweft.NIF.plan/1` (`standalone/tw_loader.hpp` + `tw_planner.hpp`).

  This module does nothing but translate parsed domain JSON into the
  host-owned tagged lists `planner.scm` walks -- ALL planning logic (the
  HTN search, action/method execution, the expression evaluator) is
  compiled Scheme; see that file's own header for the full design.

  Uses `Uro.Planner.OrderedJson`, not `Jason`, to parse the domain: a
  `multigoal`'s per-var/per-key binding order is semantically meaningful
  (it determines which binding the HTN search tries first) and must
  match native's `tsl::ordered_map`-backed parser exactly for the two
  adapters to be a true drop-in swap -- see that module's own header for
  why plain `Jason.decode!/1` (and, as first explored, `json_ld`/
  `jsonld_ex`, which decode into unordered RDF triples) don't work here.

  Targets the CURRENT `tw_loader.hpp` schema (`variables`/`actions`/
  `methods`/`todo_list`) -- NOT the stale `state`/`tasks` schema
  `priv/domains/*.jsonld` happen to use today, which is a separate,
  pre-existing bug (RFD 0023's Context section) out of scope here.

  Explicitly unsupported in Stage 5A (raises a clear error rather than
  silently misbehaving): scan methods, ReBAC-based goal bindings
  (`capabilities`), `enums`, floating-point values, and any
  KHR_interactivity node type beyond `eq`/`lt`/`add`/`sub`/`not`/`and`/
  `or`/`get`. State/desired/literal values are fixnums, booleans, or
  atoms only -- JSON strings are atomized (`String.to_atom/1`), which is
  safe only because domain JSON is trusted, author-controlled content
  (bundled `.jsonld` files), never arbitrary end-user input -- the same
  bounded-vocabulary assumption `Uro.ReBAC.SandboxAdapter` makes for its
  three fixed relation-name constants, just extended to a whole domain's
  worth of names.

  Requires `Uro.Planner.SandboxAdapter.Program` to be running (started
  by `Uro.Application` when `:planner_adapter` is configured to this
  module -- see the config-flip in RFD 0023).
  """
  @behaviour Uro.Ports.Planner

  alias Uro.Planner.OrderedJson, as: OJ
  alias WeftWarpBurrito.Program

  # Fixed tag order -- MUST match c_src/s7/fixtures/planner.scm's header
  # comment exactly (call goal multigoal eval set lit param get eq lt
  # add sub not and or).
  @tags [
    :call,
    :goal,
    :multigoal,
    :eval,
    :set,
    :lit,
    :param,
    :get,
    :eq,
    :lt,
    :add,
    :sub,
    :not,
    :and,
    :or
  ]

  @impl true
  def plan(domain_json) do
    domain = OJ.decode!(domain_json)
    validate_keys!(domain)

    state = build_state(OJ.get(domain, "variables") || [])
    actions_tbl = build_actions_tbl(OJ.get(domain, "actions"))
    methods_tbl = build_methods_tbl(OJ.get(domain, "methods"))
    tasks = build_tasks(OJ.get(domain, "todo_list") || [])
    ctx = [actions_tbl, methods_tbl, @tags]

    case Program.call(program(), "plan", [state, tasks, ctx]) do
      # Matches Uro.Planner.TaskweftAdapter's contract (Taskweft.NIF.plan/1
      # raises on no-plan, per taskweft_nif.cpp) so the two adapters are a
      # true drop-in swap, not a silent behavior change.
      {:ok, false} ->
        raise "no_plan"

      {:ok, plan_tasks} when is_list(plan_tasks) ->
        Jason.encode!(Enum.map(plan_tasks, &plan_step_json/1))

      {:error, reason} ->
        raise "Uro.Planner.SandboxAdapter.plan failed: #{inspect(reason)}"
    end
  end

  defp plan_step_json([:call, name, args]),
    do: [Atom.to_string(name) | Enum.map(args, &to_json_value/1)]

  defp to_json_value(v) when is_atom(v) and not is_boolean(v), do: Atom.to_string(v)
  defp to_json_value(v), do: v

  defp program do
    case Process.whereis(__MODULE__.Program) do
      pid when is_pid(pid) ->
        pid

      nil ->
        raise "Uro.Planner.SandboxAdapter.Program is not running -- " <>
                "start it (see Uro.Application) before selecting this adapter"
    end
  end

  # --- Top-level whitelist (Stage 5A subset of tw_loader.hpp's) ---

  @known_keys ~w(@context @type name description version source variables actions methods todo_list)

  defp validate_keys!(domain) do
    for {key, _} <- OJ.pairs(domain), key not in @known_keys do
      raise "Uro.Planner.SandboxAdapter: unsupported domain key #{inspect(key)} " <>
              "(enums/capabilities are Stage 5C follow-on; anything else is unrecognized)"
    end
  end

  # --- State: variables -> a 2-level map (var -> key -> value). Only
  #     dict-shaped `init` is supported (a bare scalar `init` has no
  #     pointer-addressable (var,key) path to reach it from an action/
  #     method eval node anyway). ---

  defp build_state(variables) do
    Enum.reduce(variables, %{}, fn var_def, state ->
      name = OJ.get(var_def, "name")
      init = OJ.get(var_def, "init")

      unless match?({:obj, _}, init) do
        raise "Uro.Planner.SandboxAdapter: variable #{name} has a non-dict init " <>
                "(bare scalar state vars aren't pointer-addressable; Stage 5A requires a dict)"
      end

      inner = Map.new(OJ.pairs(init), fn {k, v} -> {String.to_atom(k), from_domain_value(v)} end)
      Map.put(state, String.to_atom(name), inner)
    end)
  end

  defp from_domain_value(v) when is_integer(v), do: v
  defp from_domain_value(v) when is_boolean(v), do: v
  defp from_domain_value(v) when is_binary(v), do: String.to_atom(v)

  defp from_domain_value(v) do
    raise "Uro.Planner.SandboxAdapter: unsupported value #{inspect(v)} " <>
            "(Stage 5A state/desired values are fixnums, booleans, or atoms only -- no floats)"
  end

  # --- Actions: name -> (params binds body). "actions" is a JSON object
  #     (name -> def), not an array. ---

  defp build_actions_tbl(nil), do: %{}

  defp build_actions_tbl(actions) do
    Map.new(OJ.pairs(actions), fn {name, def_} ->
      params = Enum.map(OJ.get(def_, "params") || [], &String.to_atom/1)
      binds = build_binds(OJ.get(def_, "bind") || [])
      body = Enum.map(OJ.get(def_, "body") || [], &compile_step/1)
      {String.to_atom(name), [params, binds, body]}
    end)
  end

  defp build_binds(binds) do
    Enum.map(binds, fn bind ->
      name = OJ.get(bind, "name")
      {var, key} = parse_pointer(OJ.get(bind, "pointer"))
      [String.to_atom(name), var, key]
    end)
  end

  defp compile_step(step) do
    cond do
      node = OJ.get(step, "eval") ->
        [:eval, compile_node(node)]

      ptr = OJ.get(step, "pointer/set") ->
        {var, key} = parse_pointer(ptr)
        [:set, var, key, compile_node(OJ.get(step, "value"))]

      true ->
        raise "Uro.Planner.SandboxAdapter: unsupported action body step #{inspect(step)} " <>
                "(only eval/pointer-set are implemented in Stage 5A)"
    end
  end

  # --- Methods: name -> [(params binds checks subtasks), ...]. "methods"
  #     is a JSON object (task name -> group), like "actions". ---

  defp build_methods_tbl(nil), do: %{}

  defp build_methods_tbl(methods) do
    Map.new(OJ.pairs(methods), fn {name, group} ->
      cond do
        OJ.get(group, "scan") ->
          raise "Uro.Planner.SandboxAdapter: scan methods are not supported yet " <>
                  "(#{name} -- Stage 5B follow-on, see RFD 0023)"

        alts = OJ.get(group, "alternatives") ->
          params = Enum.map(OJ.get(group, "params") || [], &String.to_atom/1)
          {String.to_atom(name), Enum.map(alts, &build_method_alt(params, &1))}

        true ->
          raise "Uro.Planner.SandboxAdapter: method group #{name} has neither " <>
                  "\"alternatives\" nor \"scan\""
      end
    end)
  end

  defp build_method_alt(params, alt) do
    binds = build_binds(OJ.get(alt, "bind") || [])

    checks =
      Enum.map(OJ.get(alt, "check") || [], fn clause -> compile_node(OJ.get(clause, "eval")) end)

    subtasks =
      Enum.map(OJ.get(alt, "subtasks") || [], fn [name | arg_nodes] ->
        [String.to_atom(name), Enum.map(arg_nodes, &compile_node/1)]
      end)

    [params, binds, checks, subtasks]
  end

  # --- Tasks (todo_list): an array. Each item is either a plain array
  #     (a "call") or an object (a "goal"/"multigoal"). ---

  defp build_tasks(todo_list), do: Enum.map(todo_list, &compile_task/1)

  defp compile_task([name | args]) when is_binary(name),
    do: [:call, String.to_atom(name), Enum.map(args, &from_domain_value/1)]

  defp compile_task({:obj, _} = task) do
    cond do
      entries = OJ.get(task, "goal") ->
        [:goal, Enum.map(entries, &compile_goal_entry/1)]

      vars = OJ.get(task, "multigoal") ->
        # Order matters: try-multigoal-bindings tries unmet bindings in
        # this exact order, so both levels must preserve JSON key order
        # (OJ.pairs/1, not a plain-map comprehension).
        bindings =
          for {var, kv} <- OJ.pairs(vars), {key, desired} <- OJ.pairs(kv) do
            [String.to_atom(var), String.to_atom(key), from_domain_value(desired)]
          end

        [:multigoal, bindings]

      true ->
        raise "Uro.Planner.SandboxAdapter: todo_list entry #{inspect(task)} is neither " <>
                "a call, a goal, nor a multigoal"
    end
  end

  defp compile_goal_entry(entry) do
    {var, key} = parse_pointer(OJ.get(entry, "pointer"))
    [var, key, from_domain_value(OJ.get(entry, "eq"))]
  end

  # --- Node compilation: JSON KHR_interactivity-shaped values into
  #     planner.scm's tagged node format. A non-object value is a
  #     literal, except the single-param-reference shorthand "{name}"
  #     (matches tw_loader.hpp's resolve_param fast path). ---

  @supported_node_types ~w(eq lt add sub not and or get)

  defp compile_node({:obj, _} = node) do
    type = OJ.get(node, "type")
    short = type |> String.split("/") |> List.last()

    unless short in @supported_node_types do
      raise "Uro.Planner.SandboxAdapter: unsupported node type #{inspect(type)} " <>
              "(Stage 5A implements eq/lt/add/sub/not/and/or/get only -- no floats/trig/" <>
              "quaternion/matrix nodes)"
    end

    case short do
      "get" ->
        {var, key} = parse_pointer(OJ.get(node, "pointer"))
        [:get, var, key]

      "not" ->
        [:not, compile_node(OJ.get(node, "a"))]

      _ ->
        [String.to_atom(short), compile_node(OJ.get(node, "a")), compile_node(OJ.get(node, "b"))]
    end
  end

  defp compile_node("{" <> _ = ref) do
    case Regex.run(~r/^\{([^{}]+)\}$/, ref) do
      [_, name] -> [:param, String.to_atom(name)]
      nil -> [:lit, String.to_atom(ref)]
    end
  end

  defp compile_node(value), do: [:lit, from_domain_value(value)]

  # --- RFC 6901-ish 2-segment pointer, no templating (Stage 5A pointers
  #     are always fixed paths -- template substitution is a scan-method
  #     feature, Stage 5B follow-on). ---

  defp parse_pointer("/" <> rest) do
    case String.split(rest, "/") do
      [var, key] -> {String.to_atom(var), String.to_atom(key)}
      _ -> raise "Uro.Planner.SandboxAdapter: pointer must be exactly /var/key, got #{rest}"
    end
  end
end
