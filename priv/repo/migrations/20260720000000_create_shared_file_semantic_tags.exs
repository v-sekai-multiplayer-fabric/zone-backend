# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Repo.Migrations.CreateSharedFileSemanticTags do
  use Ecto.Migration

  def change do
    create table(:shared_file_semantic_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :shared_file_id, references(:shared_files, type: :binary_id, on_delete: :delete_all),
        null: false

      # Raw tag manifest from idtxcli's `bake --tags-out` (schema_version 1,
      # source_format, tags.{avatar_type,has_rig,skeleton_style,...}).
      add :tags, :map, null: false

      # HRR bundle of every tag atom, {:array, :float} decoded from the NIF's
      # fixed-point binary (Fabric.HRR's Int-scaled representation).
      add :hrr_vector, {:array, :float}, null: false

      # Explicit guard against a silent future hrrDim change breaking
      # cross-row comparisons (see Fabric.HRR.hrrDim).
      add :hrr_dim, :integer, null: false
      add :schema_version, :integer, null: false

      timestamps(inserted_at: :created_at)
    end

    create unique_index(:shared_file_semantic_tags, [:shared_file_id])
  end
end
