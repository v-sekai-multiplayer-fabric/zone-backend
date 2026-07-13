defmodule Taskweft.JSONLD.Loader do
  @moduledoc """
  JSON-LD document loader for Taskweft planning domains.

  ## Architecture

  The C++ NIF (`taskweft_nif`) has its own minimal JSON parser (`tw_loader.hpp`)
  that reads compact JSON-LD with plain keys (`"actions"`, `"variables"`, etc.).
  Those keys are outside the `@context` vocabulary so a full JSON-LD expansion
  would drop them; we must keep the compact form for the NIF.

  This module's job is therefore **context resolution, not expansion**:

  1. Parse the raw JSON with `Jason`.
  2. Resolve all `@context` entries — inline maps, local file references
     (e.g. `"./udon-vm.jsonld"`), and remote URLs — into a single merged map
     using `JSON.LD.context/1`.
  3. Validate the document type and required keys.
  4. Re-serialise to a compact JSON string with the fully-resolved context
     inlined, ready for the NIF.

  ## C++ NIF contract

  The NIF receives a compact JSON string where:
  - `@context` is a flat map of prefix → IRI (no `@import`, no arrays).
  - Planning keys (`"actions"`, `"variables"`, `"methods"`, `"goals"`) are
    plain strings not defined in `@context` — the loader preserves them as-is.
  - `@type` and `@id` are present but ignored by the C++ planner; this loader
    therefore validates `@type` on the Elixir side before the NIF call.

  ## Error handling

  Per project policy, every function returns `{:ok, _} | {:error, reason}`
  tuples. Reasons are human-readable strings suitable for surfacing to MCP
  clients.
  """

  alias Taskweft.JSONLD.Context

  @valid_types [
    "domain:Definition",
    "domain:MetaDomain",
    "domain:Problem",
    "udon:Vocabulary",
    "udon:VocabularyModule"
  ]

  @doc """
  Load a JSON-LD domain file, resolve all `@context` references, validate,
  and return a compact JSON string ready for the C++ NIF.
  """
  @spec load_file(Path.t()) :: {:ok, String.t()} | {:error, String.t()}
  def load_file(path) do
    with {:ok, body} <- read_file(path) do
      load_string(body, base_dir: Path.dirname(path))
    end
  end

  @doc """
  Process a JSON-LD domain string (with optional `base_dir` for resolving
  relative file-context references), validate, and return compact JSON for
  the C++ NIF.
  """
  @spec load_string(String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def load_string(json, opts \\ []) do
    base_dir = Keyword.get(opts, :base_dir, File.cwd!())

    with {:ok, doc} <- decode(json),
         {:ok, ctx} <- resolve_context(doc["@context"], base_dir),
         :ok <- validate(doc, ctx),
         {:ok, encoded} <- encode(Map.put(doc, "@context", ctx)) do
      {:ok, encoded}
    end
  end

  @doc """
  Validate that a decoded JSON-LD document is a well-formed planning domain.

  Runs in order: `@type`, `name`, top-level field shapes, goal/multigoal
  shapes, action/method call arity, variable substitution references. The
  first failure is returned; subsequent checks rely on the shape established
  by earlier ones (e.g. arity assumes `actions` is a map).
  """
  @spec validate(map(), map()) :: :ok | {:error, String.t()}
  def validate(doc, _ctx) when is_map(doc) do
    with :ok <- check_type(doc["@type"]),
         :ok <- check_name(doc["name"]),
         :ok <- check_shape(doc),
         :ok <- check_goals(doc),
         :ok <- check_multigoal_tasks(doc),
         :ok <- check_arity(doc),
         :ok <- check_var_refs(doc),
         :ok <- check_no_legacy_steps(doc) do
      :ok
    end
  end

  def validate(other, _ctx),
    do: {:error, "expected JSON-LD object, got #{inspect(other)}"}

  defp check_type(type) when type in @valid_types, do: :ok

  defp check_type(type),
    do: {:error, "expected @type in #{inspect(@valid_types)}, got #{inspect(type)}"}

  defp check_name(name) when is_binary(name), do: :ok
  defp check_name(_), do: {:error, ~s(domain document must have a string "name" field)}

  # Top-level field shapes — only checked if the field is present, since
  # vocabulary-style domains may legitimately omit actions/methods/tasks.
  defp check_shape(doc) do
    with :ok <- check_field(doc, "actions", &is_map/1, "object"),
         :ok <- check_field(doc, "variables", &is_list/1, "array"),
         :ok <- check_field(doc, "methods", &is_map/1, "object"),
         :ok <- check_field(doc, "tasks", &is_list/1, "array") do
      :ok
    end
  end

  defp check_field(doc, key, predicate, expected_label) do
    case Map.fetch(doc, key) do
      :error ->
        :ok

      {:ok, value} ->
        if predicate.(value),
          do: :ok,
          else: {:error, "expected #{key} to be #{expected_label}, got #{json_type(value)}"}
    end
  end

  # `goals` (RECTGTN 'T') has two shapes the NIF accepts:
  #   * a domain-style **object** keyed by state var name — goal *methods*,
  #     validated structurally like `methods` (nothing fixed to assert here);
  #   * a problem-style **array** of `{"pointer": "/var/key", "eq": desired}`
  #     bindings that the loader folds into one conjunctive `TwGoal` task.
  # Only the array form has a fixed binding shape, so that is what we check.
  defp check_goals(doc) do
    case Map.get(doc, "goals") do
      nil -> :ok
      goals when is_map(goals) -> :ok
      goals when is_list(goals) -> check_goal_bindings(goals)
      other -> {:error, "expected goals to be object or array, got #{json_type(other)}"}
    end
  end

  defp check_goal_bindings(bindings) do
    bindings
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {binding, i}, _ ->
      case check_goal_binding(binding, i) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp check_goal_binding(%{"pointer" => p} = b, i) when is_binary(p) do
    if Map.has_key?(b, "eq"),
      do: :ok,
      else: {:error, ~s(goals[#{i}]: binding must have an "eq" field)}
  end

  defp check_goal_binding(%{"pointer" => _}, i),
    do: {:error, ~s(goals[#{i}]: "pointer" must be a string)}

  defp check_goal_binding(b, i) when is_map(b),
    do: {:error, ~s(goals[#{i}]: binding must have a "pointer" field)}

  defp check_goal_binding(other, i),
    do: {:error, "goals[#{i}]: expected object, got #{json_type(other)}"}

  # A `tasks` entry is either a `[name, args...]` call (checked by check_arity)
  # or a multigoal object (RECTGTN 'N') `{"multigoal": {var: {key: desired,
  # ...}, ...}}`. Validate the object form's shape here; anything else that is
  # neither a call array nor a multigoal object is rejected.
  defp check_multigoal_tasks(doc) do
    doc
    |> Map.get("tasks", [])
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {task, i}, _ ->
      case check_task_shape(task, i) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp check_task_shape(task, _i) when is_list(task), do: :ok

  defp check_task_shape(%{"multigoal" => mg}, i) when is_map(mg),
    do: check_multigoal_bindings(mg, i)

  defp check_task_shape(%{"multigoal" => other}, i),
    do: {:error, "tasks[#{i}]: \"multigoal\" must be an object, got #{json_type(other)}"}

  defp check_task_shape(task, i) when is_map(task),
    do: {:error, "tasks[#{i}]: object task must be a {\"multigoal\": {...}} entry"}

  defp check_task_shape(other, i),
    do: {:error, "tasks[#{i}]: expected call array or multigoal object, got #{json_type(other)}"}

  defp check_multigoal_bindings(mg, i) when map_size(mg) == 0,
    do: {:error, "tasks[#{i}]: multigoal must bind at least one variable"}

  defp check_multigoal_bindings(mg, i) do
    Enum.reduce_while(mg, :ok, fn {var, kv}, _ ->
      cond do
        not is_map(kv) ->
          {:halt, {:error, "tasks[#{i}]: multigoal[#{var}] must be an object of key→desired"}}

        map_size(kv) == 0 ->
          {:halt, {:error, "tasks[#{i}]: multigoal[#{var}] must bind at least one key"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  defp json_type(v) when is_map(v), do: "object"
  defp json_type(v) when is_list(v), do: "array"
  defp json_type(v) when is_binary(v), do: "string"
  defp json_type(v) when is_integer(v), do: "integer"
  defp json_type(v) when is_float(v), do: "number"
  defp json_type(v) when is_boolean(v), do: "boolean"
  defp json_type(nil), do: "null"
  defp json_type(_), do: "unknown"

  # Each call in `tasks` and in method `subtasks` is `[name, arg1, arg2, ...]`.
  # When `name` is a known action or method, `length(args)` must match the
  # callee's `params` arity. Unknown names are left to the planner.
  defp check_arity(doc) do
    actions = Map.get(doc, "actions", %{})
    methods = Map.get(doc, "methods", %{})
    tasks = Map.get(doc, "tasks", [])
    arity_index = arity_index(actions, methods)

    with :ok <- check_calls(tasks, arity_index, "tasks") do
      methods
      |> Enum.reduce_while(:ok, fn {mname, mdef}, _ ->
        case check_calls(method_subtasks(mdef), arity_index, "method #{mname}") do
          :ok -> {:cont, :ok}
          err -> {:halt, err}
        end
      end)
    end
  end

  defp arity_index(actions, methods) when is_map(actions) and is_map(methods) do
    Map.merge(name_arity_map(actions), name_arity_map(methods))
  end

  defp arity_index(_, _), do: %{}

  defp name_arity_map(defs) do
    for {name, defn} <- defs, is_map(defn), into: %{} do
      params = Map.get(defn, "params", []) || []
      {name, length(params)}
    end
  end

  defp check_calls(calls, index, ctx) when is_list(calls) do
    Enum.reduce_while(calls, :ok, fn call, _ ->
      case check_call(call, index, ctx) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp check_calls(_, _, _), do: :ok

  defp check_call([name | args], index, ctx) when is_binary(name) do
    case Map.fetch(index, name) do
      :error ->
        :ok

      {:ok, expected} ->
        if length(args) == expected,
          do: :ok,
          else: {:error, "#{ctx}: #{name} expects #{expected} arg(s), got #{length(args)}"}
    end
  end

  defp check_call(_, _, _), do: :ok

  defp method_subtasks(%{"alternatives" => alts}) when is_list(alts) do
    Enum.flat_map(alts, fn
      %{"subtasks" => subs} when is_list(subs) -> subs
      _ -> []
    end)
  end

  defp method_subtasks(_), do: []

  # `{name}` substitutions inside an action `body` may reference the
  # action's own `params` or any global `variables[].name`. Inside a
  # method `subtasks` they may reference the method's own `params` or
  # any global. Unknown references are caller bugs the planner cannot
  # detect (it just emits the unsubstituted token).
  @var_re ~r/\{([^{}]+)\}/

  defp check_var_refs(doc) do
    globals = global_var_names(doc)
    actions = Map.get(doc, "actions", %{})
    methods = Map.get(doc, "methods", %{})

    with :ok <- check_member_refs(actions, globals, "action", &Map.get(&1, "body", [])) do
      check_member_refs(methods, globals, "method", &method_subtasks/1)
    end
  end

  defp global_var_names(doc) do
    doc
    |> Map.get("variables", [])
    |> List.wrap()
    |> Enum.flat_map(fn
      %{"name" => n} when is_binary(n) -> [n]
      _ -> []
    end)
    |> MapSet.new()
  end

  defp check_member_refs(defs, globals, kind, body_fn) when is_map(defs) do
    Enum.reduce_while(defs, :ok, fn {name, defn}, _ ->
      params = MapSet.new(Map.get(defn, "params", []) || [])
      allowed = MapSet.union(params, globals)

      case scan_refs(body_fn.(defn), allowed, "#{kind} #{name}") do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp check_member_refs(_, _, _, _), do: :ok

  defp scan_refs(s, allowed, ctx) when is_binary(s) do
    @var_re
    |> Regex.scan(s, capture: :all_but_first)
    |> Enum.reduce_while(:ok, fn [ref], _ ->
      if MapSet.member?(allowed, ref),
        do: {:cont, :ok},
        else: {:halt, {:error, "#{ctx}: undeclared variable {#{ref}}"}}
    end)
  end

  defp scan_refs(list, allowed, ctx) when is_list(list) do
    Enum.reduce_while(list, :ok, fn item, _ ->
      case scan_refs(item, allowed, ctx) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp scan_refs(map, allowed, ctx) when is_map(map) do
    Enum.reduce_while(map, :ok, fn {_k, v}, _ ->
      case scan_refs(v, allowed, ctx) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp scan_refs(_, _, _), do: :ok

  # Reject the legacy `set` / `check` step shorthand and the legacy
  # `{"pointer": "/x", "<op>": v}` method-alternative check clause shape.
  # Both were removed in taskweft-nif (issue #50 phase 3); the action body
  # now accepts only `{"eval": <node>}` and `{"pointer/set": "/x", ...}`,
  # and method check arrays accept only `{"eval": <node>}` clauses.
  defp check_no_legacy_steps(doc) do
    actions = Map.get(doc, "actions", %{})
    methods = Map.get(doc, "methods", %{})

    with :ok <- check_action_bodies(actions) do
      check_method_alts(methods)
    end
  end

  defp check_action_bodies(actions) when is_map(actions) do
    Enum.reduce_while(actions, :ok, fn {name, defn}, _ ->
      body = Map.get(defn, "body", []) || []

      case Enum.reduce_while(body, :ok, fn step, _ ->
             case legacy_body_step(step) do
               nil -> {:cont, :ok}
               legacy_key -> {:halt, {:error, legacy_body_msg(name, legacy_key)}}
             end
           end) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp check_action_bodies(_), do: :ok

  defp legacy_body_step(%{"set" => _}), do: "set"
  defp legacy_body_step(%{"check" => v}) when is_binary(v), do: "check"
  defp legacy_body_step(_), do: nil

  defp legacy_body_msg(action_name, key) do
    replacement =
      case key do
        "set" ->
          ~s({"pointer/set": "/path", "value": ...})

        "check" ->
          ~s({"eval": {"type": "math/eq", "a": {"type": "pointer/get", "pointer": "/path"}, "b": ...}})
      end

    "action #{action_name}: legacy `#{key}` step is no longer supported (taskweft-nif #50 phase 3); use #{replacement}"
  end

  defp check_method_alts(methods) when is_map(methods) do
    Enum.reduce_while(methods, :ok, fn {mname, mdef}, _ ->
      alts = Map.get(mdef, "alternatives", []) || []

      case Enum.reduce_while(alts, :ok, fn alt, _ ->
             clauses = Map.get(alt, "check", []) || []

             case Enum.reduce_while(clauses, :ok, fn clause, _ ->
                    case legacy_check_clause(clause) do
                      nil -> {:cont, :ok}
                      _ -> {:halt, {:error, legacy_alt_check_msg(mname)}}
                    end
                  end) do
               :ok -> {:cont, :ok}
               err -> {:halt, err}
             end
           end) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp check_method_alts(_), do: :ok

  defp legacy_check_clause(%{"pointer" => _} = c) do
    if Map.has_key?(c, "eval"), do: nil, else: :legacy
  end

  defp legacy_check_clause(_), do: nil

  defp legacy_alt_check_msg(method_name) do
    ~s/method #{method_name}: legacy `{"pointer": "\/x", "<op>": v}` check clause is no longer supported (taskweft-nif #50 phase 3); use {"eval": {"type": "math\/<op>", "a": {"type": "pointer\/get", "pointer": "\/x"}, "b": v}}/
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, "failed to read #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, value} -> {:ok, value}
      {:error, %Jason.DecodeError{} = e} -> {:error, "invalid JSON: #{Exception.message(e)}"}
    end
  end

  defp encode(value) do
    case Jason.encode(value) do
      {:ok, str} ->
        {:ok, str}

      {:error, %Jason.EncodeError{} = e} ->
        {:error, "JSON encode failed: #{Exception.message(e)}"}
    end
  end

  # nil / missing — return the canonical planning context as the fallback.
  defp resolve_context(nil, _base), do: {:ok, Context.planning_domain()}

  # Inline map — resolve any nested @import (JSON-LD 1.1).
  defp resolve_context(ctx, base) when is_map(ctx) do
    case Map.pop(ctx, "@import") do
      {nil, ctx} ->
        {:ok, ctx}

      {import_ref, ctx} ->
        with {:ok, imported} <- resolve_context(import_ref, base) do
          {:ok, Map.merge(imported, ctx)}
        end
    end
  end

  # String — either a local file path or a remote URL.
  defp resolve_context(ref, base) when is_binary(ref) do
    local = Path.join(base, ref)

    if File.exists?(local) do
      with {:ok, body} <- read_file(local),
           {:ok, file_doc} <- decode(body) do
        resolve_context(file_doc["@context"], Path.dirname(local))
      end
    else
      case JSON.LD.DocumentLoader.Default.load(ref, []) do
        {:ok, %{document: %{"@context" => remote_ctx}}} ->
          resolve_context(remote_ctx, base)

        _ ->
          {:ok, %{"@import" => ref}}
      end
    end
  end

  # Array — merge all entries left-to-right (later entries win on conflict).
  defp resolve_context(list, base) when is_list(list) do
    Enum.reduce_while(list, {:ok, %{}}, fn entry, {:ok, acc} ->
      case resolve_context(entry, base) do
        {:ok, resolved} when is_map(resolved) -> {:cont, {:ok, Map.merge(acc, resolved)}}
        {:ok, _} -> {:cont, {:ok, acc}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  defp resolve_context(other, _base),
    do: {:error, "unsupported @context value: #{inspect(other)}"}
end
