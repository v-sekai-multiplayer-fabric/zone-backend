defmodule Taskweft.PlannerPropTest do
  use ExUnit.Case, async: true
  use PropCheck

  @domains_dir Path.join([__DIR__, "../../priv/plans/domains"])

  def domain_file_gen do
    files = File.ls!(@domains_dir) |> Enum.filter(&String.ends_with?(&1, ".jsonld"))
    oneof(Enum.map(files, &exactly/1))
  end

  # --- plan/1 ---

  property "plan: returns ok or no_plan — never crashes on valid domain" do
    forall fname <- domain_file_gen() do
      domain = File.read!(Path.join(@domains_dir, fname))
      result = Taskweft.plan(domain)

      match?({:ok, _}, result) or match?({:error, "no_plan"}, result) or
        match?({:error, _}, result)
    end
  end

  property "plan: result is valid JSON array when ok" do
    forall fname <- domain_file_gen() do
      domain = File.read!(Path.join(@domains_dir, fname))

      case Taskweft.plan(domain) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, steps} -> is_list(steps)
            _ -> false
          end

        {:error, _} ->
          true
      end
    end
  end

  property "plan: each step is a non-empty array" do
    forall fname <- domain_file_gen() do
      domain = File.read!(Path.join(@domains_dir, fname))

      case Taskweft.plan(domain) do
        {:ok, json} ->
          {:ok, steps} = Jason.decode(json)
          Enum.all?(steps, &(is_list(&1) and length(&1) >= 1))

        {:error, _} ->
          true
      end
    end
  end

  # --- replan/3 ---

  property "replan: result JSON has required keys when ok" do
    forall fname <- domain_file_gen() do
      domain = File.read!(Path.join(@domains_dir, fname))

      case Taskweft.plan(domain) do
        {:ok, plan_json} ->
          case Taskweft.replan(domain, plan_json, -1) do
            {:ok, json} ->
              {:ok, result} = Jason.decode(json)
              Map.has_key?(result, "recovered") and Map.has_key?(result, "fail_step")

            {:error, _} ->
              true
          end

        {:error, _} ->
          true
      end
    end
  end

  property "replan: fail_step -1 and 0 both produce valid responses" do
    forall {fname, fail_step} <- {domain_file_gen(), oneof([exactly(-1), exactly(0)])} do
      domain = File.read!(Path.join(@domains_dir, fname))
      result = Taskweft.replan(domain, "[]", fail_step)
      match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  # --- check_temporal/3 ---

  property "check_temporal: returns ok or error — never crashes" do
    forall fname <- domain_file_gen() do
      domain = File.read!(Path.join(@domains_dir, fname))

      case Taskweft.plan(domain) do
        {:ok, plan_json} ->
          result = Taskweft.check_temporal(domain, plan_json, "PT0S")
          match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, _} ->
          true
      end
    end
  end

  property "check_temporal: result has consistent field" do
    forall fname <- domain_file_gen() do
      domain = File.read!(Path.join(@domains_dir, fname))

      case Taskweft.plan(domain) do
        {:ok, plan_json} ->
          case Taskweft.check_temporal(domain, plan_json) do
            {:ok, json} ->
              {:ok, result} = Jason.decode(json)
              # result is {"plan": ..., "temporal": {"consistent": ...}}
              temporal = result["temporal"] || result
              Map.has_key?(temporal, "consistent")

            {:error, _} ->
              true
          end

        {:error, _} ->
          true
      end
    end
  end

  # --- multi-substitution in pointers ---
  #
  # Regression: prior to the resolve_param fix, "/cells/{r}_{c}" worked in
  # `set` ops but silently failed in `check` ops because resolve_param only
  # matched whole-string "{name}" patterns. Confirm any combination of two
  # params interpolates correctly inside a single path segment for both
  # `check` and `set`, regardless of param order or value types.

  defp multi_sub_domain(r, c, v) do
    %{
      "@type" => "domain:Definition",
      "name" => "multi_sub_test",
      "variables" => [%{"name" => "cells", "init" => %{"#{r}_#{c}" => 0}}],
      "actions" => %{
        "a_place" => %{
          "params" => ["r", "c", "v"],
          "body" => [
            %{"check" => "/cells/{r}_{c}", "eq" => 0},
            %{"set" => "/cells/{r}_{c}", "value" => "{v}"}
          ]
        }
      },
      "methods" => %{},
      "tasks" => [["a_place", r, c, v]]
    }
    |> Jason.encode!()
  end

  property "resolve_param: multi-{var} substitution works in check + set" do
    forall {r, c, v} <- {range(0, 9), range(0, 9), range(1, 9)} do
      domain = multi_sub_domain(r, c, v)
      match?({:ok, _}, Taskweft.plan(domain))
    end
  end

  # --- RFC 6901 conformance ---
  #
  # parse_pointer must:
  #   * round-trip keys containing '/' and '~' via the ~1/~0 escapes.
  #   * substitute {var} templates BEFORE escape, so a value of "a/b" maps
  #     to a single reference token.
  #   * reject pointers with arity != 2 (taskweft's state is 2-level).
  #   * reject pointers without a leading '/'.

  defp single_key_domain(key, value) do
    %{
      "@type" => "domain:Definition",
      "name" => "ptr_test",
      "variables" => [%{"name" => "store", "init" => %{key => 0}}],
      "actions" => %{
        "a_set" => %{
          "params" => ["k", "v"],
          "body" => [
            %{"check" => "/store/{k}", "eq" => 0},
            %{"set" => "/store/{k}", "value" => "{v}"}
          ]
        }
      },
      "methods" => %{},
      "tasks" => [["a_set", key, value]]
    }
    |> Jason.encode!()
  end

  property "RFC 6901: keys containing '/' substitute as single tokens" do
    forall {prefix, suffix, v} <- {non_empty_string(), non_empty_string(), range(1, 99)} do
      key = "#{prefix}/#{suffix}"
      match?({:ok, _}, Taskweft.plan(single_key_domain(key, v)))
    end
  end

  property "RFC 6901: keys containing '~' substitute as single tokens" do
    forall {prefix, suffix, v} <- {non_empty_string(), non_empty_string(), range(1, 99)} do
      key = "#{prefix}~#{suffix}"
      match?({:ok, _}, Taskweft.plan(single_key_domain(key, v)))
    end
  end

  property "RFC 6901: keys with mixed '/' and '~' round-trip" do
    forall v <- range(1, 99) do
      # Hand-crafted edge cases per RFC 6901 §4 ordering rules
      Enum.all?(["~/", "/~", "~~", "//", "~01", "~10"], fn key ->
        match?({:ok, _}, Taskweft.plan(single_key_domain(key, v)))
      end)
    end
  end

  # Strict mode: bare '~' (not followed by '0' or '1') is invalid per §3 ABNF.
  defp invalid_pointer_domain(ptr) do
    %{
      "@type" => "domain:Definition",
      "name" => "invalid_ptr",
      "variables" => [%{"name" => "store", "init" => %{"a" => 0}}],
      "actions" => %{
        "a_bad" => %{
          "params" => [],
          "body" => [%{"set" => ptr, "value" => 1}]
        }
      },
      "methods" => %{},
      "tasks" => [["a_bad"]]
    }
    |> Jason.encode!()
  end

  property "RFC 6901: bare '~' in a literal pointer is rejected" do
    forall ptr <-
             oneof([
               exactly("/store/a~b"),
               exactly("/store/a~"),
               exactly("/store/~"),
               exactly("/store/~x"),
               exactly("/store/~~"),
               exactly("/store/~2")
             ]) do
      match?({:error, _}, Taskweft.plan(invalid_pointer_domain(ptr)))
    end
  end

  defp non_empty_string do
    such_that(
      s <- utf8(),
      when: byte_size(s) > 0 and not String.contains?(s, "{") and not String.contains?(s, "}")
    )
  end
end
