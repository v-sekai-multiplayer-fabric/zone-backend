defmodule Taskweft.MCP.Server do
  @moduledoc """
  MCP server for Taskweft.

  Start with `mix taskweft.mcp` or `taskweft mcp` (HTTP only — see `Taskweft.CLI`).

  The planner model is **RECTGTN** — Relationship-Enabled Capability-Temporal
  Goal-Task-Network. A domain's `todo_list` (GTPyHOP's own term for this
  heterogeneous list) holds three task kinds: `TwCall` call arrays
  (`'E'`/`'T'`), `TwGoal` `{"goal": [...]}` entries (`'G'`, conjunctive
  bindings satisfied via a goal method — an ordinary `methods` entry named
  after the state var it targets; there's no separate `goals` key), and
  `TwMultiGoal` `{"multigoal": …}` entries (`'N'`). Two more layers apply on
  top of any task kind: capability guards (`'R'`/`'C'`, top-level
  `capabilities` graph data plus a hand-written `rebac/check` eval step per
  action — no compiled sugar) and per-action temporal duration (`'T'`, an
  action's `duration` field). The `plan` tool's `domain_json` description
  documents all five with golden shapes (and rejected shapes for
  goal/multigoal — capabilities/duration are plan-time, not load-time, so
  nothing there is structurally validated).

  ## Tools

  | Tool | Description |
  |------|-------------|
  | `plan` | Run the HTN planner over a JSON-LD domain (TwCall / TwGoal / TwMultiGoal, capabilities, duration) |
  | `replan` | Recover from a failed plan step |

  `check_temporal` is not exposed as its own tool; every `plan` response
  already includes a `"temporal"` block computed from action `duration`
  fields. ReBAC, bridge, and cache NIF entrypoints are not exposed.

  ## Prompts

  `plan_problem` (solve a problem/domain pair), `plan_goal` (build a TwGoal or
  TwMultiGoal problem), `plan_capability_temporal` (build a domain using
  capability guards and/or action durations), `replan_after_failure`, and
  `work_queue`.

  ## Resources

  Every `.jsonld` under `priv/plans/{domains,problems}` is exposed as
  `taskweft://domains/<file>` and `taskweft://problems/<file>`; new files require
  `mix compile` to register.
  """

  use ExMCP.Server.Handler

  # No `version:` here — ex_mcp's DSL requires a compile-time literal for it
  # (confirmed empirically: __using__'s opts get wrapped in Macro.escape/1,
  # which freezes ANY nested `@attr` read or function call as inert AST data
  # rather than letting it compile as ordinary code, so there's no way to
  # derive this from mix.exs's own @version without patching ex_mcp). A
  # hand-copied literal here silently drifted from mix.exs twice already
  # (taskweft/mcp#23, #24) — rather than keep chasing ways to sync two
  # numbers that don't need to be synced, just don't advertise one; ex_mcp
  # falls back to its own default ("1.0.0") for `serverInfo.version`, which
  # callers should treat as informational only, not as this package's actual
  # release version (that's `Application.spec(:taskweft_mcp, :vsn)`, used
  # correctly elsewhere in this file, e.g. the taskweft://meta resource).
  use ExMCP.Server.DSL, name: "taskweft"

  # ---------- TOOLS ----------

  tool "plan",
       "Run the IPyHOP-style HTN planner over a JSON-LD domain. Returns the plan as JSON." do
    param(:domain_json, :object,
      required: true,
      description: """
      A JSON-LD HTN domain object for the RECTGTN planner (Relationship-Enabled
      Capability-Temporal Goal-Task-Network; pointer-based IPyHOP) — pass the
      parsed JSON object directly, not a JSON-encoded string. The two required
      keys are LITERALLY "@type" and "name" WITH the "@" — this is JSON-LD, not
      a generic "type"/"context" object; "type" and "context" (no "@") are NOT
      recognized keys and the document is rejected as if they were absent.
      Shape:
        "@context": {"vsekai": "https://v-sekai.org/", "domain": "vsekai:planning/domain/"}
        "@type": "domain:Definition", "name": <string>
        "variables": [{"name": <v>, "type": <t>, "init": {<key>: <value>, ...}}]   # state; NOT a flat "state" object
        "actions": {<name>: {"params": [<p>...],
                             "body": [{"pointer/set": "/path/{p}", "value": <v>}]}}   # effects; NOT pre/eff
        "methods": {<name>: {"params": [<p>...],
                             "alternatives": [{"name": <alt>,
                                               "check": [{"pointer": "/path", "eq": <v>}],   # optional guard
                                               "subtasks": [[<call>, <arg>...], ...]}]}}
        "todo_list": [<task>, ...]
      Every variable's "type" is mandatory — glTF Interactivity's own value-type
      vocabulary (KHR_interactivity socket/custom-variable types) verbatim, no
      RECTGTN extensions: "bool", "int", "float", "float2"/"float3"/"float4",
      "float2x2"/"float3x3"/"float4x4", "ref". There is no "string" type — what
      looks like free text (a block's position "table"/"hand", an agent name)
      is an opaque identity reference compared for equality, i.e. "ref". There
      is no "enum" type either — a symbolic/discrete/named-class concept is
      capability/ReBAC membership (below), not a separate lookup-table
      mechanism. "init" shape depends on "type": either a bare value (a
      single-valued fluent) or an object mapping instance keys to values of
      that type (a per-entity fluent, e.g. {"drone_1": ..., "drone_2": ...} —
      the common case).
      "todo_list" is GTPyHOP's own term for this exact heterogeneous list
      (find_plan(state, todo_list)). Each <task> is ONE of three RECTGTN task kinds:
        1. TwCall  ('E'/'T') — a call-array [<name>, <arg>...]; a bare string is NOT a call.
        2. TwGoal  ('G')     — a todo_list entry {"goal": [{"pointer": "/var/key", "eq": <desired>}, ...]}
                               (a conjunctive goal solved by a goal method — an ordinary "methods"
                               entry named after the state var it targets; there is no separate
                               "goals" key, a goal method IS an ordinary method).
        3. TwMultiGoal ('N') — a todo_list entry {"multigoal": {<var>: {<key>: <desired>, ...}, ...}};
                               the planner backjumps over which binding to satisfy first.
      A "todo_list" may mix call-arrays, {"goal": [...]}, and {"multigoal": ...} objects freely.
      Effects use "pointer/set" (the legacy "set" op is rejected). {curly} names in
      paths/values are substituted from action/method params.

      Two orthogonal RECTGTN features layer on top of any task kind above:
        * Capabilities ('R'/'C') — top-level "capabilities": {"entities": {<entity>: [<cap>,...]},
          "graph": {"edges": [...], "definitions": {}}}. A dedicated key, not a variable:
          structured/relational data gets its own namespaced slot, matching glTF Interactivity's
          own convention for extension data that isn't a scalar/vector value socket. A capability
          requirement is a hand-written {"eval": {"type": "rebac/check", "rel": <relation>,
          "subject": <ref>, "object": <cap>}} guard step written directly into an action's own
          body, the same mechanism every other action precondition uses. An agent lacking a
          required capability fails that guard, so the planner tries the next alternative (or
          reports no plan if none qualify). This is a plan-time guard, not a load-time check:
          Loader.validate does not structurally validate the "actions" requirement shape (there
          isn't one — it's an ordinary eval step) though it does validate "capabilities" itself.
        * Temporal duration ('T') — a per-action "duration": "<ISO8601>" field (e.g. "PT5M", "PT1H30M").
          Every `plan` response already includes a "temporal" block (STN consistency + per-step
          start/end) computed from these durations; actions without a "duration" default to "PT0S".
          Also not load-time validated — an invalid ISO 8601 string is a NIF-loader concern, not a
          Loader.validate rejection.

      Minimal capability + duration example (drone_1 only holds "fly", so the planner picks the
      "fly" alternative over "walk", which human_1 lacks):
        {"@context":{"vsekai":"https://v-sekai.org/","domain":"vsekai:planning/domain/"},
         "@type":"domain:Definition","name":"capability_demo",
         "variables":[{"name":"loc","type":"ref","init":{"drone_1":"base"}}],
         "capabilities":{"entities":{"drone_1":["fly"]}},
         "actions":{"a_fly":{"duration":"PT5M","params":["agent","to"],
                              "body":[{"eval":{"type":"rebac/check","rel":"HAS_CAPABILITY","subject":"{agent}","object":"fly"}},
                                      {"pointer/set":"/loc/{agent}","value":"{to}"}]},
                    "a_walk":{"duration":"PT30M","params":["agent","to"],
                              "body":[{"eval":{"type":"rebac/check","rel":"HAS_CAPABILITY","subject":"{agent}","object":"walk"}},
                                      {"pointer/set":"/loc/{agent}","value":"{to}"}]}},
         "methods":{"move":{"params":["agent","to"],
                             "alternatives":[{"name":"fly","subtasks":[["a_fly","{agent}","{to}"]]},
                                             {"name":"walk","subtasks":[["a_walk","{agent}","{to}"]]}]}},
         "todo_list":[["move","drone_1","city"]]}
      See also the bundled taskweft://domains/entity_capabilities.jsonld (capabilities) and
      taskweft://domains/temporal_travel.jsonld (duration-only) resources.

      Minimal TwCall example:
        {"@context":{"vsekai":"https://v-sekai.org/","domain":"vsekai:planning/domain/"},
         "@type":"domain:Definition","name":"demo",
         "variables":[{"name":"done","type":"bool","init":{"a":false,"b":false}}],
         "actions":{"do_a":{"params":[],"body":[{"pointer/set":"/done/a","value":true}]},
                    "do_b":{"params":[],"body":[{"pointer/set":"/done/b","value":true}]}},
         "methods":{"top":{"params":[],"alternatives":[{"name":"seq","subtasks":[["do_a"],["do_b"]]}]}},
         "todo_list":[["top"]]}
      Minimal TwGoal problem (state + desired bindings, methods come from the domain):
        {"@type":"domain:Problem","name":"switch_goal",
         "variables":[{"name":"switch","type":"bool","init":{"x":false}}],
         "todo_list":[{"goal":[{"pointer":"/switch/x","eq":true}]}]}
      Minimal TwMultiGoal problem:
        {"@type":"domain:Problem","name":"switch_multigoal",
         "variables":[{"name":"switch","type":"bool","init":{"x":false,"y":false}}],
         "todo_list":[{"multigoal":{"switch":{"x":true,"y":true}}}]}
      Rejected shapes (Loader.validate): a "goal" binding missing "pointer"/"eq", or an empty
      "goal" list; an empty {"multigoal":{}} or a multigoal var bound to a non-object; an object
      task that is neither a {"multigoal": ...} nor a {"goal": ...} entry.
      """
    )

    param(:explain, :boolean,
      required: false,
      description:
        "When true, include an explain tree for successful plans and return structured no_plan diagnostics instead of a bare failure token."
    )

    run(fn args, state ->
      guarded(state, fn ->
        domain = Map.fetch!(args, :domain_json)
        explain = Map.get(args, :explain, false)
        plan_with_optional_explain(Jason.encode!(domain), explain)
      end)
    end)
  end

  tool "replan",
       "Replan after a step failure. Pass the original domain, the previously-returned plan, and the index of the failed step (-1 for full replan)." do
    param(:domain_json, :object, required: true)
    param(:plan_json, :object, required: true)

    param(:fail_step, :integer,
      required: false,
      description: "Index of the failed step; -1 for a full replan."
    )

    run(fn args, state ->
      guarded(state, fn ->
        domain = Map.fetch!(args, :domain_json)
        plan_arg = Map.fetch!(args, :plan_json)
        fail_step = Map.get(args, :fail_step, -1)

        domain_json = Jason.encode!(domain)

        with {:ok, steps} <- decode_plan(plan_arg),
             :ok <- validate_fail_step(steps, fail_step),
             :ok <- validate_for_replan(domain_json) do
          # tw_replan wants a bare top-level step array; the {"plan":[...]} envelope
          # that `plan` returns silently parses to 0 steps (#43), so re-encode the
          # step list before handing it to the NIF.
          Taskweft.replan(domain_json, Jason.encode!(steps), fail_step)
        end
      end)
    end)
  end

  tool "validate",
       "Validate a JSON-LD domain/problem document without planning. Returns the normalized document JSON on success, or a validation error. plan/replan do not validate — call this first if you want to check a document's shape without also attempting to solve it." do
    param(:domain_json, :object, required: true)

    run(fn args, state ->
      guarded(state, fn ->
        domain = Map.fetch!(args, :domain_json)
        validate_domain(Jason.encode!(domain))
      end)
    end)
  end

  # ---------- RESOURCES ----------
  # Every bundled `.jsonld` under priv/plans/{domains,problems} is readable. 1.0's
  # `resource` needs a literal URI, so the per-file set is exposed as two templates.

  resource "taskweft://meta", "Taskweft MCP metadata" do
    title("Taskweft metadata")
    mime_type("application/json")

    read(fn _args, _state ->
      version = Application.spec(:taskweft, :vsn) |> to_string()
      {:ok, Jason.encode!(%{"name" => "taskweft", "version" => version})}
    end)
  end

  resource_template "taskweft://domains/{file}", "JSON-LD HTN domain" do
    title("HTN domain")
    mime_type("application/ld+json")
    param(:file, :string)

    read(fn %{file: file}, state -> read_jsonld("taskweft://domains/#{file}", state) end)
  end

  resource_template "taskweft://problems/{file}", "JSON-LD HTN problem" do
    title("HTN problem")
    mime_type("application/ld+json")
    param(:file, :string)

    read(fn %{file: file}, state -> read_jsonld("taskweft://problems/#{file}", state) end)
  end

  # ---------- PROMPTS ----------

  prompt "work_queue",
         "Stored skill — read taskweft://problems/work_queue.jsonld and its sibling .notes.json, and report decoded status." do
    title("Work queue status")

    render(fn _args, state ->
      message(
        "Read the resources taskweft://problems/work_queue.jsonld (the plannable state/todo_list) " <>
          "and taskweft://problems/work_queue.notes.json (human/LLM-facing status metadata, not " <>
          "part of the planning document) and report the decoded status: phases, pass conditions, " <>
          "scenarios, and stack readiness.",
        state
      )
    end)
  end

  prompt "plan_problem",
         "Sample workflow — solve a problem against a domain via the `plan` tool." do
    title("Plan a problem")
    arg(:domain, required: false, description: "Domain file name, e.g. blocks_world.jsonld")
    arg(:problem, required: false, description: "Problem file name, e.g. blocks_world_1a.jsonld")

    render(fn args, state ->
      domain = args[:domain] || "<domain>.jsonld"
      problem = args[:problem] || "<problem>.jsonld"

      message(
        "Read taskweft://domains/#{domain} and taskweft://problems/#{problem}, then call the `plan` tool with the combined JSON-LD domain.",
        state
      )
    end)
  end

  prompt "plan_goal",
         "Sample workflow — solve a goal or multigoal (RECTGTN 'G'/'N') against a domain via the `plan` tool." do
    title("Plan a goal / multigoal")
    arg(:domain, required: false, description: "Domain file name, e.g. blocks_world.jsonld")

    arg(:kind,
      required: false,
      description: "Task kind: \"goal\" (TwGoal) or \"multigoal\" (TwMultiGoal)"
    )

    render(fn args, state ->
      domain = args[:domain] || "<domain>.jsonld"
      kind = args[:kind] || "goal"

      shape =
        if kind == "multigoal" do
          ~s(a `{"multigoal": {<var>: {<key>: <desired>, ...}}}` entry in "todo_list")
        else
          ~s(a `{"goal": [{"pointer": "/var/key", "eq": <desired>}, ...]}` entry in "todo_list")
        end

      message(
        "Read taskweft://domains/#{domain} for its actions and methods (goal methods are " <>
          "ordinary methods named after the state var they target, not a separate key). " <>
          "Build a domain:Problem whose desired end-state is expressed as #{shape} " <>
          "(RECTGTN #{if kind == "multigoal", do: "'N' TwMultiGoal", else: "'G' TwGoal"}), " <>
          "then call the `plan` tool with the merged domain. The planner solves each " <>
          "binding via the matching goal method; a multigoal additionally backjumps " <>
          "over which binding to satisfy first.",
        state
      )
    end)
  end

  prompt "plan_capability_temporal",
         "Sample workflow — build a domain using capability guards and/or action durations (RECTGTN 'R'/'C'/'T'), then plan it." do
    title("Plan with capabilities / temporal duration")

    arg(:domain,
      required: false,
      description: "Domain file name, e.g. entity_capabilities.jsonld or temporal_travel.jsonld"
    )

    render(fn args, state ->
      domain = args[:domain] || "entity_capabilities.jsonld"

      message(
        "Read taskweft://domains/#{domain}. If it has a top-level \"capabilities\" object " <>
          "({\"entities\": {<entity>: [<cap>,...]}, \"graph\": {...}}), note which capabilities " <>
          "each entity holds — a capability guard is a hand-written {\"eval\": {\"type\": " <>
          "\"rebac/check\", \"rel\": <relation>, \"subject\": <ref>, \"object\": <cap>}} step in " <>
          "an action's own body (RECTGTN 'R'/'C'; this is a plan-time guard, not a load-time " <>
          "validation). If any action carries a \"duration\" (ISO 8601, e.g. \"PT5M\") that's " <>
          "RECTGTN 'T' — the `plan` tool's response already includes a \"temporal\" block (STN " <>
          "consistency + per-step start/end) computed from those durations, with no extra call " <>
          "needed. Then call the `plan` tool with the domain JSON as-is (add a \"todo_list\" " <>
          "entry if the bundled file doesn't already have one).",
        state
      )
    end)
  end

  prompt "replan_after_failure",
         "Sample workflow — recover from a failed plan step via the `replan` tool." do
    title("Replan after failure")
    arg(:domain, required: false, description: "Domain file name")
    arg(:fail_step, required: false, description: "Index of the failed step")

    render(fn args, state ->
      domain = args[:domain] || "<domain>.jsonld"
      fail_step = args[:fail_step] || "<index>"

      message(
        "Read taskweft://domains/#{domain}, then call the `replan` tool with the original plan and fail_step #{fail_step}.",
        state
      )
    end)
  end

  # ---------- HELPERS ----------

  # Same rationale as plan_with_optional_explain/2: surface a schema error
  # instead of letting a malformed domain reach the NIF as a bare
  # "failed_to_load_domain" token.
  defp validate_for_replan(json) do
    case validate_domain(json) do
      {:error, _reason} = error -> error
      _ok -> :ok
    end
  end

  defp validate_domain(json), do: Taskweft.JSONLD.Loader.load_string(json)

  # `fail_step = -1` means full replan (no completed prefix). Any other value must
  # point at a real index in the plan; otherwise the planner silently treats it as
  # past-the-end success.
  defp validate_fail_step(_steps, -1), do: :ok

  defp validate_fail_step(steps, fail_step)
       when is_list(steps) and is_integer(fail_step) and fail_step >= 0 do
    if fail_step < length(steps),
      do: :ok,
      else: {:error, "fail_step #{fail_step} out of range for plan of length #{length(steps)}"}
  end

  defp validate_fail_step(_steps, fail_step),
    do: {:error, "fail_step must be an integer >= -1, got #{inspect(fail_step)}"}

  # Accept either a bare step array or the {"plan":[...]} envelope that `plan`
  # returns, and normalize to a bare step list — the NIF's tw_replan wants a
  # top-level array and silently yields 0 steps from an envelope (#43). Reject
  # anything else with a structured error instead of silently passing it through.
  # `plan_json` arrives as an already-decoded term (a list or a map) — the
  # transport parsed the JSON, so there's no string here to be malformed.
  defp decode_plan(list) when is_list(list), do: {:ok, list}
  defp decode_plan(%{"plan" => list}) when is_list(list), do: {:ok, list}

  defp decode_plan(other),
    do:
      {:error,
       "plan_json must be an array of step arrays or a {\"plan\": [...]} envelope, got #{inspect(other)}"}

  # Neither `Taskweft.plan/1` nor `plan_explain/1` validate before handing the
  # JSON to the NIF loader — a malformed domain (missing "@type", a legacy
  # "goals"/"tasks" key, a variable missing "type", etc.) surfaces only as the
  # opaque NIF-level "failed_to_load_domain" token, which gives a caller no
  # way to fix their document (confirmed via adversarial testing — repeated
  # real callers hit this and had no actionable signal). Run the same schema
  # validation `validate` uses first, so a shape error reports precisely what
  # is wrong instead of a bare failure string.
  defp plan_with_optional_explain(domain_json, explain) do
    case validate_domain(domain_json) do
      {:error, _reason} = error -> error
      _ok -> do_plan(domain_json, explain)
    end
  end

  defp do_plan(domain_json, false), do: Taskweft.plan(domain_json)

  defp do_plan(domain_json, true) do
    case Taskweft.plan_explain(domain_json) do
      {:ok, result_json} ->
        with {:ok, domain} <- Jason.decode(domain_json),
             {:ok, result} <- Jason.decode(result_json) do
          diagnostics = scan_domain_diagnostics(domain)
          explain = merge_explain_payload(result["explain"], diagnostics, result)
          payload = Map.put(result, "explain", explain)
          {:ok, Jason.encode!(payload)}
        else
          _ -> {:ok, result_json}
        end

      other ->
        other
    end
  end

  defp merge_explain_payload(existing, diagnostics, result) when is_map(existing) do
    existing
    |> Map.put("diagnostics", diagnostics)
    |> Map.put_new_lazy("status", fn -> result["status"] || "ok" end)
  end

  defp merge_explain_payload(_existing, diagnostics, result) do
    status = result["status"] || "ok"

    base = %{
      "mode" => "fallback",
      "status" => status,
      "diagnostics" => diagnostics
    }

    if status == "no_plan" do
      Map.put(base, "summary", "planner returned no_plan")
    else
      Map.put(base, "summary", "plan found")
      |> Map.put("solution_tree", build_solution_tree(result))
    end
  end

  defp build_solution_tree(%{"plan" => plan} = result) when is_list(plan) do
    temporal_steps = get_in(result, ["temporal", "steps"])

    children =
      Enum.with_index(plan)
      |> Enum.map(fn {step, index} ->
        action = List.first(step)
        args = Enum.drop(step, 1)
        temporal = if is_list(temporal_steps), do: Enum.at(temporal_steps, index), else: nil

        %{
          "kind" => "action",
          "index" => index,
          "action" => action,
          "args" => args,
          "temporal" => temporal
        }
      end)

    %{
      "kind" => "root",
      "label" => "plan_execution",
      "children" => children
    }
  end

  defp build_solution_tree(_),
    do: %{"kind" => "root", "label" => "plan_execution", "children" => []}

  defp scan_domain_diagnostics(domain) when is_map(domain) do
    eval_ops = valid_eval_ops()
    actions = Map.get(domain, "actions", %{})
    methods = Map.get(domain, "methods", %{})

    # There is no separate "goals" key — a goal method is an ordinary
    # "methods" entry named after the state var it targets, so it's already
    # covered by methods' keys here.
    symbols =
      Map.keys(actions)
      |> Kernel.++(Map.keys(methods))
      |> MapSet.new()

    unknown_subtasks =
      methods
      |> Enum.flat_map(fn {method_name, method} ->
        method
        |> Map.get("alternatives", [])
        |> Enum.with_index()
        |> Enum.flat_map(fn {alt, alt_idx} ->
          alt
          |> Map.get("subtasks", [])
          |> Enum.with_index()
          |> Enum.flat_map(fn {subtask, sub_idx} ->
            case subtask do
              [name | _] when is_binary(name) ->
                if MapSet.member?(symbols, name) do
                  []
                else
                  [
                    %{
                      "severity" => "error",
                      "type" => "unknown_subtask_symbol",
                      "method" => method_name,
                      "alternative" => alt_idx,
                      "subtask" => sub_idx,
                      "symbol" => name
                    }
                  ]
                end

              _ ->
                []
            end
          end)
        end)
      end)

    check_issues =
      methods
      |> Enum.flat_map(fn {method_name, method} ->
        method
        |> Map.get("alternatives", [])
        |> Enum.with_index()
        |> Enum.flat_map(fn {alt, alt_idx} ->
          alt
          |> Map.get("check", [])
          |> Enum.with_index()
          |> Enum.flat_map(fn {check, check_idx} ->
            cond do
              is_map(check) and Map.has_key?(check, "pointer") ->
                [
                  %{
                    "severity" => "error",
                    "type" => "legacy_check_syntax",
                    "method" => method_name,
                    "alternative" => alt_idx,
                    "check" => check_idx
                  }
                ]

              is_map(check) and is_map(check["eval"]) ->
                eval_type = get_in(check, ["eval", "type"]) || ""

                if eval_type in eval_ops do
                  []
                else
                  [
                    %{
                      "severity" => "error",
                      "type" => "unknown_eval_operator",
                      "method" => method_name,
                      "alternative" => alt_idx,
                      "check" => check_idx,
                      "operator" => eval_type
                    }
                  ]
                end

              true ->
                []
            end
          end)
        end)
      end)

    unknown_subtasks ++ check_issues
  end

  defp scan_domain_diagnostics(_), do: []

  defp valid_eval_ops do
    [
      "math/eq",
      "math/neq",
      "math/lt",
      "math/le",
      "math/gt",
      "math/ge",
      "math/and",
      "math/or",
      "math/not",
      # Capability requirements now compile to this op (taskweft/nif's
      # eval_node, tw_loader.hpp) rather than a bespoke guard mechanism, so
      # it's also directly authorable in an ordinary method/goal-method
      # "check" clause: {"eval": {"type": "rebac/check", "rel": <string-or-
      # relation-expr>, "subject": <expr>, "object": <expr>}}.
      "rebac/check"
    ]
  end

  # Run a planner call, converting any {:error, _} into the MCP error shape and
  # any raised exception / exit / thrown value into a clean {:error, _} result —
  # so a malformed domain returns an MCP `isError` instead of crashing the
  # transport (which surfaced as an opaque HTTP 500 / "Error POSTing to endpoint").
  defp guarded(state, fun) do
    tuple_result(fun.(), state)
  rescue
    e -> {:error, "taskweft: #{Exception.message(e)}", state}
  catch
    kind, reason -> {:error, "taskweft: #{inspect({kind, reason})}", state}
  end

  # Unwrap the {:ok, _} | {:error, _} from Taskweft.plan/3 and replan/3 into the
  # MCP run-handler shape (a plain string becomes text content).
  defp tuple_result({:ok, result}, state) when is_binary(result), do: {:ok, result, state}
  defp tuple_result({:error, reason}, state) when is_binary(reason), do: {:error, reason, state}
  defp tuple_result({:error, reason}, state), do: {:error, inspect(reason), state}

  # `Taskweft.MCP.Plans` embeds every bundled file into the .beam at compile
  # time (see its moduledoc) — no runtime `priv/` resolution, no release-
  # packaging fragility to worry about. `rest` is `"domains/<file>"` or
  # `"problems/<file>"`; the latter also covers `.notes.json` siblings
  # (`work_queue.notes.json` etc.), which aren't planning documents but share
  # the same `taskweft://problems/{file}` template.
  defp read_jsonld("taskweft://" <> rest = uri, state) do
    lookup =
      case String.split(rest, "/", parts: 2) do
        ["domains", file] -> Taskweft.MCP.Plans.domain(file)
        ["problems", file] -> problem_or_notes(file)
        _ -> :error
      end

    case lookup do
      {:ok, content} -> {:ok, %{uri: uri, text: content, mimeType: "application/ld+json"}, state}
      :error -> {:error, "unknown resource: #{uri}", state}
    end
  end

  defp read_jsonld(uri, state), do: {:error, "unknown resource: #{uri}", state}

  defp problem_or_notes(file) do
    with :error <- Taskweft.MCP.Plans.problem(file) do
      Taskweft.MCP.Plans.problem_notes(file)
    end
  end

  # A single user text message — the render-handler shape.
  defp message(text, state) do
    {:ok, %{messages: [%{role: "user", content: %{type: "text", text: text}}]}, state}
  end
end
