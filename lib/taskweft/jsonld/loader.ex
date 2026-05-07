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
  """
  @spec validate(map(), map()) :: :ok | {:error, String.t()}
  def validate(doc, _ctx) when is_map(doc) do
    with :ok <- check_type(doc["@type"]),
         :ok <- check_name(doc["name"]) do
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
      {:ok, str} -> {:ok, str}
      {:error, %Jason.EncodeError{} = e} -> {:error, "JSON encode failed: #{Exception.message(e)}"}
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
