defmodule Taskweft.JSONLD.LoaderVarRefsPropTest do
  @moduledoc """
  Generative property coverage for `Taskweft.JSONLD.Loader`'s `{ref}`
  variable-reference check, exercised through the public `validate/2`.
  Complements the hand-picked example tests in `loader_test.exs`.

  Found while investigating a taskweft/mcp resource-read bug: several
  bundled domain fixtures (blocks_world.jsonld, simple_travel.jsonld, ...)
  reference `{vars}` that are only declared in their paired *problem* file,
  so `validate/2` correctly rejects them when checked standalone — domain
  files are not self-contained documents in this system. This test locks
  down that exact accept/reject boundary generatively, instead of relying
  on hand-picked fixtures to happen to cover it.
  """

  use ExUnit.Case, async: true
  use PropCheck

  alias Taskweft.JSONLD.Loader

  @numtests 500
  @alphabet ~w(a b c d e f g)

  property "an action body {ref} is accepted iff declared in params or global variables",
           [:verbose, numtests: @numtests] do
    forall {params, globals, refs} <- refs_gen() do
      doc = domain_with_action_refs(params, globals, refs)
      accepted_iff_declared?(doc, params, globals, refs)
    end
  end

  property "a method subtask {ref} is accepted iff declared in method params or global variables",
           [:verbose, numtests: @numtests] do
    forall {params, globals, refs} <- refs_gen() do
      doc = domain_with_method_refs(params, globals, refs)
      accepted_iff_declared?(doc, params, globals, refs)
    end
  end

  defp accepted_iff_declared?(doc, params, globals, refs) do
    declared = MapSet.new(params ++ globals)
    all_declared? = Enum.all?(refs, &MapSet.member?(declared, &1))

    case Loader.validate(doc, %{}) do
      :ok -> all_declared?
      {:error, msg} -> not all_declared? and msg =~ "undeclared variable"
    end
  end

  defp refs_gen do
    {list(oneof(@alphabet)), list(oneof(@alphabet)), list(oneof(@alphabet))}
  end

  defp domain_with_action_refs(params, globals, refs) do
    %{
      "@type" => "domain:Definition",
      "name" => "prop",
      "variables" => Enum.map(globals, &%{"name" => &1, "type" => "ref", "init" => %{}}),
      "actions" => %{
        "a1" => %{
          "params" => params,
          "body" => [%{"pointer/set" => "/x", "value" => refs_string(refs)}]
        }
      }
    }
  end

  defp domain_with_method_refs(params, globals, refs) do
    %{
      "@type" => "domain:Definition",
      "name" => "prop",
      "variables" => Enum.map(globals, &%{"name" => &1, "type" => "ref", "init" => %{}}),
      "methods" => %{
        "m1" => %{
          "params" => params,
          "alternatives" => [
            %{"name" => "only", "subtasks" => [["noop", refs_string(refs)]]}
          ]
        }
      }
    }
  end

  defp refs_string(refs), do: Enum.map_join(refs, " ", &"{#{&1}}")
end
