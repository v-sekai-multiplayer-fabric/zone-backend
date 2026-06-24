# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Uro.LoopController do
  use Uro, :controller

  @doc """
  POST /api/v1/loop/commit

  Authoritative loop server calls this at the end of each field phase to persist
  player item snapshots. Auth uses the LOOP_API_KEY env var (same pattern as
  SIGNUP_API_KEY). No user session is involved — this is a server-to-server call.

  Body: {"api_key": "...", "profiles": [{"name": "alice", "items": [101, 202]}]}
  """
  def commit(conn, %{"api_key" => api_key, "profiles" => profiles})
      when is_list(profiles) do
    expected = System.get_env("LOOP_API_KEY", "")

    cond do
      expected == "" ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "loop_commit_disabled", message: "LOOP_API_KEY not configured."})

      api_key != expected ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "forbidden", message: "Invalid API key."})

      true ->
        case UroLoop.commit(profiles) do
          {:ok, _} ->
            conn
            |> put_status(:ok)
            |> json(%{ok: true})

          {:error, reason} ->
            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "commit_failed", message: inspect(reason)})
        end
    end
  end

  def commit(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "bad_request", message: "Expected {api_key, profiles}."})
  end
end
