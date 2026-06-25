# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Loop.Item do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "loop_items" do
    belongs_to :player, Uro.Loop.Player, foreign_key: :loop_player_id
    field :item, :integer
    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:loop_player_id, :item])
    |> validate_required([:loop_player_id, :item])
    |> unique_constraint([:loop_player_id, :item])
  end
end
