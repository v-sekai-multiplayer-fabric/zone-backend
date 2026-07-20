# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Tagging do
  @moduledoc """
  OpenUSD/glTF semantic tagging and similarity, per the HRR tagging plan.

  Turns the tag manifest `idtxcli bake --tags-out` produces into one HRR
  bundle vector per `SharedFile` (`Uro.SharedContent.SharedFileSemanticTag`),
  and answers "which other assets look similar" by cosine similarity over
  those vectors (`Uro.Hrr`) -- no training loop, meaningful even with very
  few examples per asset.
  """

  import Ecto.Query, warn: false
  alias Uro.Repo
  alias Uro.SharedContent.SharedFileSemanticTag

  @doc """
  Tags `shared_file_id` from `manifest` (the parsed JSON `idtxcli bake
  --tags-out` produces: `%{"schema_version" => 1, "source_format" => "usd",
  "tags" => %{"avatar_type" => "humanoid", ...}}`), storing one bundled HRR
  vector for the row. Upserts on `shared_file_id` so re-tagging (e.g. after
  a re-bake) replaces the previous manifest/vector rather than erroring on
  the unique index.
  """
  def tag_asset(shared_file_id, %{"tags" => tag_map} = manifest) when is_map(tag_map) do
    schema_version = Map.get(manifest, "schema_version", 1)

    bundled =
      tag_map
      |> Enum.map(fn {dimension, value} -> Uro.Hrr.gen_atom(atom_seed(dimension, value)) end)
      |> Enum.reduce(nil, fn
        atom, nil -> atom
        atom, acc -> Uro.Hrr.bundle(acc, atom)
      end) || List.duplicate(0.0, Uro.Hrr.dim())

    attrs = %{
      shared_file_id: shared_file_id,
      tags: manifest,
      hrr_vector: bundled,
      hrr_dim: Uro.Hrr.dim(),
      schema_version: schema_version
    }

    %SharedFileSemanticTag{}
    |> SharedFileSemanticTag.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:tags, :hrr_vector, :hrr_dim, :schema_version, :updated_at]},
      conflict_target: :shared_file_id
    )
  end

  # Deterministic seed from "dimension:value" -- the first 8 bytes of its
  # SHA-256, as an unsigned big-endian integer, matching Uro.Hrr.gen_atom's
  # integer seed. Same tag value always yields the same atom across every
  # asset and every run.
  defp atom_seed(dimension, value) do
    <<seed::unsigned-big-64, _rest::binary>> =
      :crypto.hash(:sha256, "#{dimension}:#{inspect(value)}")

    seed
  end

  @doc """
  Cosine-similarity neighbours of `shared_file_id`, nearest first. Linear
  scan over every tagged asset -- fine up to roughly 10^3-10^4 rows; revisit
  with an ANN index only once the catalog actually grows past that (not a
  v1 concern, per the plan).
  """
  def similar_assets(shared_file_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    case Repo.get_by(SharedFileSemanticTag, shared_file_id: shared_file_id) do
      nil ->
        {:error, :not_found}

      %SharedFileSemanticTag{hrr_vector: target} ->
        results =
          SharedFileSemanticTag
          |> where([t], t.shared_file_id != ^shared_file_id)
          |> Repo.all()
          |> Enum.map(fn t ->
            %{shared_file_id: t.shared_file_id, score: Uro.Hrr.cosine_sim(target, t.hrr_vector)}
          end)
          |> Enum.sort_by(& &1.score, :desc)
          |> Enum.take(limit)

        {:ok, results}
    end
  end
end
