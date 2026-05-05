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
  - `@type` and `@id` are present but ignored by the C++ planner.
  """

  alias Taskweft.JSONLD.Context

  @doc """
  Load a JSON-LD domain file, resolve all `@context` references, validate,
  and return a compact JSON string ready for the C++ NIF.
  """
  @spec load_file!(Path.t()) :: String.t()
  def load_file!(path) do
    path
    |> File.read!()
    |> load_string!(base_dir: Path.dirname(path))
  end

  @doc """
  Process a JSON-LD domain string (with optional `base_dir` for resolving
  relative file-context references), validate, and return compact JSON for
  the C++ NIF.
  """
  @spec load_string!(String.t(), keyword()) :: String.t()
  def load_string!(json, opts \\ []) do
    base_dir = Keyword.get(opts, :base_dir, File.cwd!())
    doc = Jason.decode!(json)
    resolved_ctx = resolve_context(doc["@context"], base_dir)
    validate!(doc, resolved_ctx)
    doc |> Map.put("@context", resolved_ctx) |> Jason.encode!()
  end

  @doc """
  Validate that a decoded JSON-LD document is a well-formed planning domain.
  Raises `ArgumentError` on failure.
  """
  @spec validate!(map(), map()) :: :ok
  def validate!(doc, _ctx) do
    type = doc["@type"]

    valid_types = [
      "domain:Definition",
      "domain:MetaDomain",
      "udon:Vocabulary",
      "udon:VocabularyModule"
    ]

    unless type in valid_types do
      raise ArgumentError,
            "expected @type in #{inspect(valid_types)}, got #{inspect(type)}"
    end

    unless is_binary(doc["name"]) do
      raise ArgumentError, "domain document must have a string \"name\" field"
    end

    :ok
  end

  # ── Context resolution ──────────────────────────────────────────────────────

  # nil / missing — return the canonical planning context as the fallback.
  defp resolve_context(nil, _base), do: Context.planning_domain()

  # Inline map — resolve any nested @import (JSON-LD 1.1).
  defp resolve_context(ctx, base) when is_map(ctx) do
    case Map.pop(ctx, "@import") do
      {nil, ctx} ->
        ctx

      {import_ref, ctx} ->
        imported = resolve_context(import_ref, base)
        Map.merge(imported, ctx)
    end
  end

  # String — either a local file path or a remote URL.
  defp resolve_context(ref, base) when is_binary(ref) do
    local = Path.join(base, ref)

    if File.exists?(local) do
      local
      |> File.read!()
      |> Jason.decode!()
      |> then(fn file_doc ->
        resolve_context(file_doc["@context"], Path.dirname(local))
      end)
    else
      # Remote URL: fetch via JSON.LD's document loader.
      case JSON.LD.DocumentLoader.Default.load(ref, []) do
        {:ok, %{document: %{"@context" => remote_ctx}}} ->
          resolve_context(remote_ctx, base)

        _ ->
          # Keep as string; the NIF will never see it but we preserve intent.
          %{"@import" => ref}
      end
    end
  end

  # Array — merge all entries left-to-right (later entries win on conflict).
  defp resolve_context(list, base) when is_list(list) do
    Enum.reduce(list, %{}, fn entry, acc ->
      resolved = resolve_context(entry, base)
      if is_map(resolved), do: Map.merge(acc, resolved), else: acc
    end)
  end
end
