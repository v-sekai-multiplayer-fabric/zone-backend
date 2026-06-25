# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Repo.Migrations.AddLoopProfiles do
  use Ecto.Migration

  def up do
    create table(:loop_players, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false
      add :name, :string, null: false
      timestamps()
    end

    create unique_index(:loop_players, [:name])

    create table(:loop_items, primary_key: false) do
      add :id, :binary_id, primary_key: true, null: false

      add :loop_player_id, references(:loop_players, type: :binary_id, on_delete: :delete_all),
        null: false

      add :item, :integer, null: false
      timestamps()
    end

    create unique_index(:loop_items, [:loop_player_id, :item])
  end

  def down do
    drop table(:loop_items)
    drop table(:loop_players)
  end
end
