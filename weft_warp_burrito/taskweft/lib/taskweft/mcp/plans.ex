# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.MCP.Plans do
  @moduledoc """
  Bundled RECTGTN HTN planning domains and problems, embedded into this
  module at compile time.

  `priv/plans/{domains,problems}/*.jsonld` (plus `*.notes.json` siblings)
  used to be read off disk at runtime via `:code.priv_dir/1` — first from a
  separate `taskweft_plans` package, then (transitionally) from this app's
  own `priv/`. Both are fragile the same way `Taskweft.JSONLD.Loader`
  documents for its own bundled JSON schema: a `priv/` directory that
  resolves fine under `mix run` can end up missing from an assembled
  release depending on how the build/packaging pipeline copies files (a
  Docker multi-stage `COPY`, a Burrito wrap step, ...). Baking file content
  into the `.beam` at compile time sidesteps the question entirely — the
  data travels with the module no matter how the release is assembled.

  Every getter returns the exact raw file bytes (not a decoded/re-encoded
  term) — this module has no JSON dependency, matching what MCP resource
  reads have always served. `@external_resource` on every bundled file
  makes `mix compile` recompile this module whenever a plan file changes.
  """

  @plans_dir Path.join([__DIR__, "..", "..", "..", "priv", "plans"]) |> Path.expand()

  @domain_files Path.wildcard(Path.join([@plans_dir, "domains", "*.jsonld"]))
  @problem_files Path.wildcard(Path.join([@plans_dir, "problems", "*.jsonld"]))
  @problem_note_files Path.wildcard(Path.join([@plans_dir, "problems", "*.notes.json"]))

  for file <- @domain_files ++ @problem_files ++ @problem_note_files do
    @external_resource file
  end

  # Not a `defp` helper: a module attribute assignment is evaluated during
  # compilation, before local functions defined later in the same module
  # body are callable from attribute context — inline the read instead.
  @domains Map.new(@domain_files, fn path -> {Path.basename(path), File.read!(path)} end)
  @problems Map.new(@problem_files, fn path -> {Path.basename(path), File.read!(path)} end)
  @problem_notes Map.new(@problem_note_files, fn path ->
                   {Path.basename(path), File.read!(path)}
                 end)

  @doc """
  Raw JSON-LD text for a bundled domain file, e.g. `"blocks_world.jsonld"`.
  """
  @spec domain(String.t()) :: {:ok, String.t()} | :error
  def domain(file), do: Map.fetch(@domains, file)

  @doc """
  Raw JSON-LD text for a bundled problem file, e.g. `"blocks_world_1a.jsonld"`.
  """
  @spec problem(String.t()) :: {:ok, String.t()} | :error
  def problem(file), do: Map.fetch(@problems, file)

  @doc """
  Raw JSON text for a bundled problem's sibling `.notes.json` file (human/
  LLM-facing status metadata, not part of the planning document itself),
  e.g. `"work_queue.notes.json"`.
  """
  @spec problem_notes(String.t()) :: {:ok, String.t()} | :error
  def problem_notes(file), do: Map.fetch(@problem_notes, file)
end
