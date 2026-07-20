# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.ReBACZoneTest do
  use ExUnit.Case, async: true
  use PropCheck

  alias Taskweft.ReBAC

  # ── Unit tests for CAN_ENTER ───────────────────────────────────────────────

  test "CAN_ENTER: owner can enter their own zone" do
    g = ReBAC.new_graph() |> ReBAC.add_edge("owner-1", "zone-1", "CAN_ENTER")
    assert ReBAC.check_rel(g, "owner-1", "CAN_ENTER", "zone-1")
  end

  test "CAN_ENTER: stranger cannot enter without edge" do
    g = ReBAC.new_graph() |> ReBAC.add_edge("owner-1", "zone-1", "CAN_ENTER")
    refute ReBAC.check_rel(g, "stranger", "CAN_ENTER", "zone-1")
  end

  test "CAN_ENTER: OWNS implies CAN_ENTER via explicit edge" do
    g =
      ReBAC.new_graph()
      |> ReBAC.add_edge("owner-1", "zone-1", "OWNS")
      |> ReBAC.add_edge("owner-1", "zone-1", "CAN_ENTER")

    assert ReBAC.check_rel(g, "owner-1", "CAN_ENTER", "zone-1")
    refute ReBAC.check_rel(g, "guest", "CAN_ENTER", "zone-1")
  end

  test "CAN_ENTER: explicit invite grants access" do
    g =
      ReBAC.new_graph()
      |> ReBAC.add_edge("owner-1", "zone-1", "OWNS")
      |> ReBAC.add_edge("owner-1", "zone-1", "CAN_ENTER")
      |> ReBAC.add_edge("invited-player", "zone-1", "CAN_ENTER")

    assert ReBAC.check_rel(g, "invited-player", "CAN_ENTER", "zone-1")
    refute ReBAC.check_rel(g, "uninvited", "CAN_ENTER", "zone-1")
  end

  # ── Unit tests for CAN_INSTANCE ───────────────────────────────────────────

  test "CAN_INSTANCE: uploader can instance their own asset" do
    g = ReBAC.new_graph() |> ReBAC.add_edge("uploader-1", "asset-1", "CAN_INSTANCE")
    assert ReBAC.check_rel(g, "uploader-1", "CAN_INSTANCE", "asset-1")
  end

  test "CAN_INSTANCE: other player cannot instance without edge" do
    g = ReBAC.new_graph() |> ReBAC.add_edge("uploader-1", "asset-1", "CAN_INSTANCE")
    refute ReBAC.check_rel(g, "other", "CAN_INSTANCE", "asset-1")
  end

  # ── Property tests ─────────────────────────────────────────────────────────

  def id_gen do
    let(
      chars <- non_empty(list(range(?a, ?z))),
      do: List.to_string(chars)
    )
  end

  property "CAN_ENTER: add_edge always grants access to subject" do
    forall {subj, zone} <- {id_gen(), id_gen()} do
      g = ReBAC.new_graph() |> ReBAC.add_edge(subj, zone, "CAN_ENTER")
      ReBAC.check_rel(g, subj, "CAN_ENTER", zone)
    end
  end

  property "CAN_ENTER: no false grants — distinct subjects are independent" do
    forall {subj_a, subj_b, zone} <- {id_gen(), id_gen(), id_gen()} do
      implies subj_a != subj_b do
        g = ReBAC.new_graph() |> ReBAC.add_edge(subj_a, zone, "CAN_ENTER")
        not ReBAC.check_rel(g, subj_b, "CAN_ENTER", zone)
      end
    end
  end

  property "CAN_INSTANCE: add_edge always grants access to subject" do
    forall {subj, asset} <- {id_gen(), id_gen()} do
      g = ReBAC.new_graph() |> ReBAC.add_edge(subj, asset, "CAN_INSTANCE")
      ReBAC.check_rel(g, subj, "CAN_INSTANCE", asset)
    end
  end
end
