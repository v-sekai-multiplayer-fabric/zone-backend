defmodule Taskweft.JSONLD.Context do
  @moduledoc """
  Canonical JSON-LD contexts for Taskweft planning domains.

  Provides the shared `@context` maps used across all domain files.
  These are the contexts the C++ NIF (tw_loader.hpp) implicitly understands
  when reading compact JSON-LD planning domains.
  """

  @planning_domain %{
    "vsekai" => "https://v-sekai.org/",
    "domain" => "vsekai:planning/domain/"
  }

  @udon %{
    "vsekai" => "https://v-sekai.org/",
    "domain" => "vsekai:planning/domain/",
    "udon" => "https://v-sekai.github.io/taskweft-udon/vocab#"
  }

  @doc "Base context for `domain:Definition` planning domains."
  def planning_domain, do: @planning_domain

  @doc "Extended context adding the `udon:` vocabulary prefix."
  def udon, do: @udon

  @doc """
  Return the context map for a given `@type` string, falling back to
  `planning_domain/0` for unknown types.
  """
  def for_type("udon:" <> _), do: @udon
  def for_type(_), do: @planning_domain
end
