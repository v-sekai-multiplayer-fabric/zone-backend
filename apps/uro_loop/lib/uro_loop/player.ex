# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule UroLoop.Player do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "loop_players" do
    field :name, :string
    has_many :items, UroLoop.Item, foreign_key: :loop_player_id
    timestamps()
  end

  def changeset(player, attrs) do
    player
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
