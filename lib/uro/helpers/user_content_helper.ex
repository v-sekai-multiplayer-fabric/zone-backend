# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.Helpers.UserContentHelper do
  @doc false
  def merge_map_with_base_user_content(map, user_content) do
    Map.merge(map, %{
      id: to_string(user_content.id),
      name: to_string(user_content.name),
      description: to_string(user_content.description),
      user_content_data:
        to_string(
          Uro.Uploaders.UserContentData.url({user_content.user_content_data, user_content})
        ),
      user_content_preview:
        to_string(
          Uro.Uploaders.UserContentPreview.url({user_content.user_content_preview, user_content})
        )
    })
  end

  @doc false
  def get_api_user_content(user_content, config) do
    map = merge_map_with_base_user_content(%{}, user_content)

    map =
      if Map.get(config, :merge_is_public, false) == true,
        do: Map.merge(map, %{is_public: user_content.is_public}),
        else: map

    map =
      if Map.get(config, :merge_inserted_at, false) == true,
        do: Map.merge(map, %{inserted_at: user_content.inserted_at}),
        else: map

    map =
      if Map.get(config, :merge_updated_at, false) == true,
        do: Map.merge(map, %{updated_at: user_content.updated_at}),
        else: map

    map =
      if Map.get(config, :merge_uploader_id, false) == true,
        do: Map.merge(map, %{uploader_id: user_content.uploader_id}),
        else: map

    map
  end

  @doc false
  def get_api_user_content_list(user_content_list, config) do
    Enum.map(user_content_list, fn x -> get_api_user_content(x, config) end)
  end

  @doc false
  def has_avatar_upload_permission?(nil), do: false

  def has_avatar_upload_permission?(user) do
    ruleset = Uro.Helpers.Auth.get_user_privilege_ruleset(user)
    graph = build_upload_permission_graph(to_string(user.id), ruleset)
    Uro.ReBAC.check_rel(graph, to_string(user.id), "IS_MEMBER_OF", "avatar_uploaders")
  end

  @doc false
  def has_map_upload_permission?(nil), do: false

  def has_map_upload_permission?(user) do
    ruleset = Uro.Helpers.Auth.get_user_privilege_ruleset(user)
    graph = build_upload_permission_graph(to_string(user.id), ruleset)
    Uro.ReBAC.check_rel(graph, to_string(user.id), "IS_MEMBER_OF", "map_uploaders")
  end

  @doc false
  def has_prop_upload_permission?(nil), do: false

  def has_prop_upload_permission?(user) do
    ruleset = Uro.Helpers.Auth.get_user_privilege_ruleset(user)
    graph = build_upload_permission_graph(to_string(user.id), ruleset)
    Uro.ReBAC.check_rel(graph, to_string(user.id), "IS_MEMBER_OF", "prop_uploaders")
  end

  # Builds a per-request ReBAC graph from the existing boolean privilege ruleset.
  # Each upload permission becomes an IS_MEMBER_OF edge to the relevant group.
  defp build_upload_permission_graph(user_id, ruleset) do
    graph = Uro.ReBAC.new_graph()

    graph =
      if ruleset && ruleset.can_upload_avatars,
        do: Uro.ReBAC.add_edge(graph, user_id, "avatar_uploaders", "IS_MEMBER_OF"),
        else: graph

    graph =
      if ruleset && ruleset.can_upload_maps,
        do: Uro.ReBAC.add_edge(graph, user_id, "map_uploaders", "IS_MEMBER_OF"),
        else: graph

    if ruleset && ruleset.can_upload_props,
      do: Uro.ReBAC.add_edge(graph, user_id, "prop_uploaders", "IS_MEMBER_OF"),
      else: graph
  end

  @spec session_has_avatar_upload_permission?(
          atom
          | %{:assigns => nil | maybe_improper_list | map, optional(any) => any}
        ) :: boolean
  @doc false
  def session_has_avatar_upload_permission?(conn) do
    has_avatar_upload_permission?(conn.assigns[:current_user])
  end

  @doc false
  def session_has_map_upload_permission?(conn) do
    has_map_upload_permission?(conn.assigns[:current_user])
  end

  @doc false
  def session_has_prop_upload_permission?(conn) do
    has_prop_upload_permission?(conn.assigns[:current_user])
  end

  def get_correct_user_content_params(
        conn,
        user_content_params,
        user_content_data_filename_param,
        user_content_data_preview_param
      ) do
    user_content_data = Map.get(user_content_params, user_content_data_filename_param)
    user_content_preview = Map.get(user_content_params, user_content_data_preview_param)

    %{
      "name" => Map.get(user_content_params, "name", ""),
      "description" => Map.get(user_content_params, "description", ""),
      "user_content_data" => user_content_data,
      "user_content_preview" => user_content_preview,
      "is_public" => Map.get(user_content_params, "is_public", false),
      "uploader_id" => conn.assigns[:current_user].id
    }
  end
end
