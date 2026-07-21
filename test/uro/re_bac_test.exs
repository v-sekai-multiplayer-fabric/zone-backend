# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Uro.ReBACTest do
  use Uro.RepoCase

  import Mox
  import Ecto.Changeset

  alias Uro.VSekai
  alias Uro.VSekai.Zone
  alias Uro.Helpers.UserContentHelper

  setup :verify_on_exit!

  setup do
    Application.put_env(:uro, :rebac_adapter, Uro.ReBACMock)
    on_exit(fn -> Application.put_env(:uro, :rebac_adapter, Uro.ReBAC.ElixirAdapter) end)
    :ok
  end

  describe "Uro.VSekai.can_enter_zone?/2 via a mocked ReBAC adapter" do
    test "grants entry when the mock reports true" do
      zone = %Zone{public: false, user_id: "owner-1", id: "zone-1"}

      Uro.ReBACMock
      |> expect(:new_graph, fn -> :graph end)
      |> expect(:add_edge, 2, fn :graph, _subj, _obj, _rel -> :graph end)
      |> expect(:check_rel, fn :graph, "stranger-2", "CAN_ENTER", "zone-1" -> true end)

      assert VSekai.can_enter_zone?(zone, "stranger-2")
    end

    test "denies entry when the mock reports false" do
      zone = %Zone{public: false, user_id: "owner-1", id: "zone-1"}

      Uro.ReBACMock
      |> expect(:new_graph, fn -> :graph end)
      |> expect(:add_edge, 2, fn :graph, _subj, _obj, _rel -> :graph end)
      |> expect(:check_rel, fn :graph, "stranger-2", "CAN_ENTER", "zone-1" -> false end)

      refute VSekai.can_enter_zone?(zone, "stranger-2")
    end
  end

  describe "Uro.Helpers.UserContentHelper upload permission checks via a mocked ReBAC adapter" do
    setup do
      user = Repo.insert!(%Uro.Accounts.User{} |> cast(%{email: "uploader@test.test"}, [:email]))

      Repo.insert!(
        Uro.Accounts.UserPrivilegeRuleset.admin_changeset(
          %Uro.Accounts.UserPrivilegeRuleset{},
          %{
            user_id: user.id,
            can_upload_avatars: true,
            can_upload_maps: false,
            can_upload_props: false
          }
        )
      )

      %{user: user}
    end

    test "has_avatar_upload_permission?/1 reflects the mocked ReBAC result", %{user: user} do
      Uro.ReBACMock
      |> expect(:new_graph, fn -> :graph end)
      |> expect(:add_edge, fn :graph, _subj, "avatar_uploaders", "IS_MEMBER_OF" -> :graph end)
      |> expect(:check_rel, fn :graph, _subj, "IS_MEMBER_OF", "avatar_uploaders" -> true end)

      assert UserContentHelper.has_avatar_upload_permission?(user)
    end

    test "has_map_upload_permission?/1 is false when the user has no matching edge", %{
      user: user
    } do
      # The shared ruleset above has can_upload_avatars: true, so
      # build_upload_permission_graph/2 still adds an avatar_uploaders edge
      # even though this test is only checking the map_uploaders relation.
      Uro.ReBACMock
      |> expect(:new_graph, fn -> :graph end)
      |> expect(:add_edge, fn :graph, _subj, "avatar_uploaders", "IS_MEMBER_OF" -> :graph end)
      |> expect(:check_rel, fn :graph, _subj, "IS_MEMBER_OF", "map_uploaders" -> false end)

      refute UserContentHelper.has_map_upload_permission?(user)
    end

    test "has_prop_upload_permission?/1 is false for a nil user" do
      refute UserContentHelper.has_prop_upload_permission?(nil)
    end
  end
end
