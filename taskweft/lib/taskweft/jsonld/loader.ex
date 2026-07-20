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
  - Planning keys (`"actions"`, `"variables"`, `"methods"`, `"todo_list"`) are
    plain strings not defined in `@context` — the loader preserves them as-is.
  - `@type` and `@id` are present but ignored by the C++ planner; this loader
    therefore validates `@type` on the Elixir side before the NIF call.

  ## Error handling

  Per project policy, every function returns `{:ok, _} | {:error, reason}`
  tuples. Reasons are human-readable strings suitable for surfacing to MCP
  clients.
  """

  alias Taskweft.JSONLD.Context

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

  Structural shape rules are enforced by a single JSON Schema
  (`priv/schemas/rectgtn_domain.schema.json`) — one declarative source of
  truth. The remaining checks are cross-referencing rules a document-shape
  schema can't express: whether a `domain:Definition` declares at least one
  action or method (an empty/near-empty `{}` domain is otherwise schema-valid
  but unsolvable and previously reached the NIF as an opaque failure), action/
  method call arity, `{param}` substitution references, and ISO 8601
  duration grammar (its own dedicated, property-tested parser).
  """
  @spec validate(map(), map()) :: :ok | {:error, String.t()}
  def validate(doc, _ctx) when is_map(doc) do
    with :ok <- check_json_schema(doc),
         :ok <- check_has_actions(doc),
         :ok <- check_arity(doc),
         :ok <- check_action_durations(doc),
         :ok <- check_var_refs(doc) do
      :ok
    end
  end

  def validate(other, _ctx),
    do: {:error, "expected JSON-LD object, got #{inspect(other)}"}

  # Embedded at compile time, not read from priv/ at runtime — this
  # repo's own established pattern for small bundled static data
  # (Taskweft.JSONLD.Context bakes its @context maps as module attributes
  # rather than reading files from priv/). :code.priv_dir/1 resolution is
  # correct in principle, but taskweft's own app priv/ directory turned out
  # to not actually be present at all in the deployed release (`/app/lib/
  # taskweft-<version>/priv` doesn't exist on the running machine) — some
  # apps' priv/ ends up in the release depending on how it's referenced
  # elsewhere in the build, and taskweft's own priv/ apparently never has
  # been. Baking the content into the module at compile time sidesteps
  # that packaging question entirely: it travels with the .beam file no
  # matter what. @external_resource makes `mix compile` recompile this
  # module when the schema file changes, so dev workflow still works.
  #
  # Path built from __DIR__, not a bare relative string — a relative path
  # resolves against Mix's current working directory when it compiles this
  # module, which for a path dependency is the *top-level* project's CWD
  # (e.g. /app/deploy in the hosted Containerfile), not this dependency's
  # own root (/app) — confirmed by reproducing the real Containerfile build.
  # __DIR__ is always this source file's actual on-disk location, so it's
  # correct regardless of which project is doing the compiling.
  @schema_path Path.join([
                 __DIR__,
                 "..",
                 "..",
                 "..",
                 "priv",
                 "schemas",
                 "rectgtn_domain.schema.json"
               ])
  @external_resource @schema_path
  @schema @schema_path
          |> File.read!()
          |> Jason.decode!()
          |> ExJsonSchema.Schema.resolve()

  defp check_json_schema(doc) do
    case ExJsonSchema.Validator.validate(@schema, doc) do
      :ok ->
        :ok

      {:error, errors} ->
        # Default error_formatter (Error.StringFormatter) yields {message, path}.
        msg =
          errors
          |> Enum.map(fn {e, p} -> "#{p}: #{e}" end)
          |> Enum.join("; ")

        {:error, "schema validation failed: #{msg}"}
    end
  end

  # A `domain:Definition` with neither actions nor methods is never
  # solvable — every `todo_list` entry bottoms out at an action, reached
  # either directly or through a method — so a caller mistake like an
  # unpopulated `{}` domain is otherwise schema-valid but useless. Methods
  # alone are accepted (a domain fragment that composes actions declared
  # elsewhere, e.g. via a later merge) — this only rejects the case where
  # neither is present at all. `domain:Problem` documents are exempt: they
  # carry state/todo_list only and inherit actions/methods from the domain
  # they're merged with.
  defp check_has_actions(%{"@type" => "domain:Definition"} = doc) do
    if non_empty_map?(doc["actions"]) or non_empty_map?(doc["methods"]) do
      :ok
    else
      {:error,
       "domain:Definition documents must declare at least one action or method (\"actions\"/\"methods\" is missing or empty)"}
    end
  end

  defp check_has_actions(_doc), do: :ok

  defp non_empty_map?(m) when is_map(m), do: map_size(m) > 0
  defp non_empty_map?(_), do: false

  # Per-action `duration` (RECTGTN 'T') feeds the temporal/STN block; unlike
  # capabilities this has a concrete grammar (ISO 8601), so a malformed value
  # is rejected here rather than left to the NIF's temporal parser.
  defp check_action_durations(doc) do
    actions = Map.get(doc, "actions", %{})

    if is_map(actions) do
      Enum.reduce_while(actions, :ok, fn {name, defn}, _ ->
        case check_action_duration(name, defn) do
          :ok -> {:cont, :ok}
          err -> {:halt, err}
        end
      end)
    else
      :ok
    end
  end

  defp check_action_duration(name, defn) when is_map(defn) do
    case Map.get(defn, "duration") do
      nil ->
        :ok

      dur when is_binary(dur) ->
        case Taskweft.Iso8601Duration.parse(dur) do
          {:ok, _components} ->
            :ok

          {:error, reason} ->
            {:error, "action #{name}: invalid duration #{inspect(dur)} (#{inspect(reason)})"}
        end

      other ->
        {:error, "action #{name}: duration must be a string, got #{inspect(other)}"}
    end
  end

  defp check_action_duration(_name, _defn), do: :ok

  # Each call in `todo_list` and in method `subtasks` is `[name, arg1, arg2, ...]`.
  # When `name` is a known action or method, `length(args)` must match the
  # callee's `params` arity. Unknown names are left to the planner.
  defp check_arity(doc) do
    actions = Map.get(doc, "actions", %{})
    methods = Map.get(doc, "methods", %{})
    tasks = Map.get(doc, "todo_list", [])
    arity_index = arity_index(actions, methods)

    with :ok <- check_calls(tasks, arity_index, "todo_list") do
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

    with :ok <-
           check_member_refs(actions, globals, "action", &Map.get(&1, "body", []), &bind_names/1) do
      check_member_refs(methods, globals, "method", &method_subtasks/1, fn _defn ->
        MapSet.new()
      end)
    end
  end

  # An action's own `bind` entries (e.g. `{"name": "under", "pointer": "/pos/{block}"}`)
  # introduce a body-scoped name the same way `params` does — bundled fixtures
  # (blocks_world's a_unstack, simple_travel's a_call_taxi) reference their own
  # bind name in `body`, so it must be in the allowed set alongside params/globals.
  # Methods have no `bind` key at all (schema-enforced), hence no equivalent here.
  defp bind_names(defn) do
    defn
    |> Map.get("bind", [])
    |> List.wrap()
    |> Enum.flat_map(fn
      %{"name" => n} when is_binary(n) -> [n]
      _ -> []
    end)
    |> MapSet.new()
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

  defp check_member_refs(defs, globals, kind, body_fn, extra_names_fn) when is_map(defs) do
    Enum.reduce_while(defs, :ok, fn {name, defn}, _ ->
      params = MapSet.new(Map.get(defn, "params", []) || [])
      allowed = params |> MapSet.union(globals) |> MapSet.union(extra_names_fn.(defn))

      case scan_refs(body_fn.(defn), allowed, "#{kind} #{name}") do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp check_member_refs(_, _, _, _, _), do: :ok

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

  defp read_file(path) do
    case File.read(path) do
      {:ok, body} -> {:ok, body}
      {:error, reason} -> {:error, "failed to read #{path}: #{:file.format_error(reason)}"}
    end
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, value} ->
        {:ok, value}

      {:error, %Jason.DecodeError{} = e} ->
        {:error, "invalid JSON: #{Exception.message(e)}#{decode_hint(json, e)}"}
    end
  end

  # Escaped/double-encoded and URI-shaped inputs get a specific, targeted
  # hint. Anything else falls back to a generic line/column + snippet, since
  # a bare byte offset is unusable on a multi-hundred-line domain document.
  defp decode_hint(json, e) when is_binary(json) do
    trimmed = String.trim_leading(json)

    cond do
      String.starts_with?(trimmed, "\\") ->
        ". input appears to be escaped/double-encoded; send raw JSON text starting with '{' (do not pre-escape quotes or braces)"

      uri_scheme?(trimmed) ->
        ". input looks like a URI, not JSON content — if this came from a " <>
          "taskweft://... resource, fetch its content first (e.g. via " <>
          "resources/read) and pass that content as domain_json, not the URI itself"

      true ->
        location_hint(json, Map.get(e, :position))
    end
  end

  defp decode_hint(_, _), do: ""

  @uri_scheme_re ~r/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//

  defp uri_scheme?(trimmed), do: Regex.match?(@uri_scheme_re, trimmed)

  # Jason.DecodeError only carries a raw byte offset. Render it as a
  # 1-indexed line/column plus a short snippet with a caret, so locating the
  # mistake doesn't require manually counting bytes.
  defp location_hint(json, position) when is_integer(position) do
    size = byte_size(json)
    pos = min(max(position, 0), size)
    prefix = binary_part(json, 0, pos)

    newline_positions = :binary.matches(prefix, "\n")
    line = length(newline_positions) + 1

    column =
      case List.last(newline_positions) do
        nil -> pos + 1
        {last_nl, _} -> pos - last_nl
      end

    snippet_start = max(pos - 20, 0)
    snippet_len = min(size - snippet_start, 40)
    snippet = binary_part(json, snippet_start, snippet_len) |> String.replace("\n", "\\n")
    caret = String.duplicate(" ", pos - snippet_start) <> "^"

    ". at line #{line}, column #{column}:\n    #{snippet}\n    #{caret}"
  end

  defp location_hint(_json, _position), do: ""

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
