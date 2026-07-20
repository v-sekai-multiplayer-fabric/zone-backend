# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.SharedContent.SharedFileSemanticTag do
  @moduledoc """
  One row per `SharedFile` holding its OpenUSD/glTF semantic tag manifest
  (from `idtxcli bake --tags-out`) and the HRR bundle vector encoding it,
  per the OpenUSD/glTF bake + HRR tagging plan.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "shared_file_semantic_tags" do
    belongs_to :shared_file, Uro.SharedContent.SharedFile

    field :tags, :map
    field :hrr_vector, {:array, :float}
    field :hrr_dim, :integer
    field :schema_version, :integer

    timestamps(inserted_at: :created_at)
  end

  @doc false
  def changeset(shared_file_semantic_tag, attrs) do
    shared_file_semantic_tag
    |> cast(attrs, [:shared_file_id, :tags, :hrr_vector, :hrr_dim, :schema_version])
    |> validate_required([:shared_file_id, :tags, :hrr_vector, :hrr_dim, :schema_version])
    |> foreign_key_constraint(:shared_file_id)
    |> unique_constraint(:shared_file_id)
  end
end
