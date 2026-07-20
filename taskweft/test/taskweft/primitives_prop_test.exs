# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule Taskweft.PrimitivesPropTest do
  @moduledoc """
  Inductive base — verifies the 5 atomic primitives the planner is built on,
  plus the planner-level state-threading invariant.

  If these hold, every plan the planner emits is sound by structural
  induction on the task decomposition tree. Anything beyond this is
  cross-section assertion on derived behavior.

    1. parse_pointer — covered by `planner_prop_test.exs` (RFC 6901 + multi-sub)
    2. eval_expr     — covered by `planner_prop_test.exs` (multi-sub)
    3. state.get     — this file
    4. state.set     — this file
    5. compare       — this file (per operator)
    6. state threading — this file (sequential + backtracking)
  """

  use ExUnit.Case, async: true
  use PropCheck

  defp simple_key, do: such_that(s <- alphanumeric(), when: byte_size(s) > 0)

  defp alphanumeric do
    let chars <- non_empty(list(oneof([range(?a, ?z), range(?A, ?Z), range(?0, ?9)]))) do
      List.to_string(chars)
    end
  end

  # New-shape (glTF Interactivity) action-body clause builders. taskweft-nif
  # dropped the `check`/`set` shorthand (taskweft-nif #6/#7), so a state read is
  # a `math/<op>` comparison over a `pointer/get`, and a write is `pointer/set`.
  defp getp(ptr), do: %{"type" => "pointer/get", "pointer" => ptr}
  defp cmp(ptr, op, v), do: %{"eval" => %{"type" => "math/#{op}", "a" => getp(ptr), "b" => v}}
  defp set(ptr, v), do: %{"pointer/set" => ptr, "value" => v}

  # ---- Primitive 3: state.get ------------------------------------------------

  property "state.get: a check against an init value passes" do
    forall {key, value} <- {simple_key(), integer()} do
      domain =
        %{
          "@type" => "domain:Definition",
          "name" => "get_test",
          "variables" => [%{"name" => "store", "init" => %{key => value}}],
          "actions" => %{
            "a_check" => %{
              "params" => [],
              "body" => [cmp("/store/#{key}", "eq", value)]
            }
          },
          "methods" => %{},
          "todo_list" => [["a_check"]]
        }
        |> Jason.encode!()

      match?({:ok, _}, Taskweft.plan(domain))
    end
  end

  # ---- Primitive 4: state.set ------------------------------------------------
  #
  # Doubles as a state-threading test: action 2 must see action 1's mutation.

  property "state.set: write then read returns the written value" do
    forall {key, init_val, new_val} <- {simple_key(), integer(), integer()} do
      implies init_val != new_val do
        domain =
          %{
            "@type" => "domain:Definition",
            "name" => "set_test",
            "variables" => [%{"name" => "store", "init" => %{key => init_val}}],
            "actions" => %{
              "a_set" => %{
                "params" => [],
                "body" => [set("/store/#{key}", new_val)]
              },
              "a_check_new" => %{
                "params" => [],
                "body" => [cmp("/store/#{key}", "eq", new_val)]
              }
            },
            "methods" => %{},
            "todo_list" => [["a_set"], ["a_check_new"]]
          }
          |> Jason.encode!()

        match?({:ok, _}, Taskweft.plan(domain))
      end
    end
  end

  # ---- Primitive 5: compare (per operator) -----------------------------------

  defp compare_domain(op, lhs, rhs) do
    %{
      "@type" => "domain:Definition",
      "name" => "cmp",
      "variables" => [%{"name" => "store", "init" => %{"v" => lhs}}],
      "actions" => %{
        "a_check" => %{
          "params" => [],
          "body" => [cmp("/store/v", op, rhs)]
        }
      },
      "methods" => %{},
      "todo_list" => [["a_check"]]
    }
    |> Jason.encode!()
  end

  property "compare/eq: succeeds iff lhs == rhs" do
    forall {a, b} <- {integer(), integer()} do
      a == b == match?({:ok, _}, Taskweft.plan(compare_domain("eq", a, b)))
    end
  end

  property "compare/neq: succeeds iff lhs != rhs" do
    forall {a, b} <- {integer(), integer()} do
      a != b == match?({:ok, _}, Taskweft.plan(compare_domain("neq", a, b)))
    end
  end

  property "compare/lt: succeeds iff lhs < rhs" do
    forall {a, b} <- {integer(), integer()} do
      a < b == match?({:ok, _}, Taskweft.plan(compare_domain("lt", a, b)))
    end
  end

  property "compare/le: succeeds iff lhs <= rhs" do
    forall {a, b} <- {integer(), integer()} do
      a <= b == match?({:ok, _}, Taskweft.plan(compare_domain("le", a, b)))
    end
  end

  property "compare/gt: succeeds iff lhs > rhs" do
    forall {a, b} <- {integer(), integer()} do
      a > b == match?({:ok, _}, Taskweft.plan(compare_domain("gt", a, b)))
    end
  end

  property "compare/ge: succeeds iff lhs >= rhs" do
    forall {a, b} <- {integer(), integer()} do
      a >= b == match?({:ok, _}, Taskweft.plan(compare_domain("ge", a, b)))
    end
  end

  # ---- Primitive 6: state threading ------------------------------------------
  #
  # Composed test: a method's failed alternative must roll back state before
  # the next alternative is tried. Without rollback, alternative 2 sees stale
  # mutations from alternative 1 and the "succeed" branch fails.

  property "state threading: failed method alternative rolls back its mutations" do
    forall stash_value <- integer() do
      implies stash_value != 0 do
        domain =
          %{
            "@type" => "domain:Definition",
            "name" => "rollback_test",
            "variables" => [%{"name" => "store", "init" => %{"x" => 0, "y" => 0}}],
            "actions" => %{
              "a_clobber_x" => %{
                "params" => [],
                "body" => [set("/store/x", stash_value)]
              },
              "a_unsatisfiable" => %{
                "params" => [],
                "body" => [cmp("/store/y", "eq", 1)]
              },
              "a_assert_x_zero" => %{
                "params" => [],
                "body" => [cmp("/store/x", "eq", 0)]
              }
            },
            "methods" => %{
              "try_then_fallback" => %{
                "params" => [],
                "alternatives" => [
                  %{
                    "name" => "doomed",
                    "subtasks" => [["a_clobber_x"], ["a_unsatisfiable"]]
                  },
                  %{
                    "name" => "fallback",
                    "subtasks" => [["a_assert_x_zero"]]
                  }
                ]
              }
            },
            "todo_list" => [["try_then_fallback"]]
          }
          |> Jason.encode!()

        match?({:ok, _}, Taskweft.plan(domain))
      end
    end
  end
end
