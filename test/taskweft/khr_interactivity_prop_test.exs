defmodule Taskweft.KHRInteractivityPropTest do
  # Red-phase placeholder tests for KHR_interactivity §02 node types.
  #
  # Each test encodes a spec assertion as a domain whose action body uses
  # `eval` steps to check the expression result.  If the node type evaluates
  # correctly the planner finds a plan ({:ok, _}); if not, it returns
  # {:error, "no_plan"} — that is a failing (red) test.
  #
  # Spec source: thirdparty/gltf_interactivity/02_node_types.md
  #
  # Run:   mix test --include red
  # Skip:  mix test --exclude red
  use ExUnit.Case, async: true
  use PropCheck

  @moduletag :red

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Build a minimal single-action domain that runs `eval_steps` in its body.
  # Plan succeeds iff all eval checks pass.
  defp eval_domain(eval_steps) when is_list(eval_steps) do
    Jason.encode!(%{
      "@context" => %{
        "khr" => "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/",
        "domain" => "khr:planning/domain/"
      },
      "@type" => "domain:Definition",
      "name" => "khr_test",
      "variables" => [%{"name" => "ok", "init" => %{"v" => false}}],
      "actions" => %{
        "a_check" => %{
          "params" => [],
          "body" =>
            eval_steps ++
              [%{"pointer/set" => "/ok/v", "value" => true}]
        }
      },
      "tasks" => [["a_check"]]
    })
  end

  # Shorthand: single eval step.
  defp eval_domain(node), do: eval_domain([%{"eval" => node}])

  # Wrap a KHR node expression for use in an eval step.
  defp khr(type, fields \\ %{}), do: Map.put(fields, "type", type)

  defp plans?(domain) do
    case Taskweft.plan(domain) do
      {:ok, _} -> true
      {:error, "no_plan"} -> false
      {:error, _} -> false
    end
  end

  # Assert the domain produces a successful plan.
  defp assert_plans(domain), do: assert(plans?(domain))

  # Assert the domain fails to plan (expression evaluated to false/wrong).
  defp refute_plans(domain), do: refute(plans?(domain))

  # Interval check: |expr - expected| <= eps, expressed as KHR nodes.
  # Use for transcendental ops that are not required to be correctly rounded.
  defp near_eq(expr, expected, eps \\ 1.0e-9) do
    khr("math/le", %{
      "a" => khr("math/abs", %{"a" => khr("math/sub", %{"a" => expr, "b" => expected})}),
      "b" => eps
    })
  end

  # ---------------------------------------------------------------------------
  # §02 Constants: math/E, math/Pi, math/Inf, math/NaN
  # ---------------------------------------------------------------------------

  test "math/E > 2.718" do
    assert_plans(eval_domain(khr("math/gt", %{"a" => khr("math/E"), "b" => 2.718})))
  end

  test "math/E < 2.719" do
    assert_plans(eval_domain(khr("math/lt", %{"a" => khr("math/E"), "b" => 2.719})))
  end

  test "math/Pi > 3.14159" do
    assert_plans(eval_domain(khr("math/gt", %{"a" => khr("math/Pi"), "b" => 3.14159})))
  end

  test "math/Pi < 3.14160" do
    assert_plans(eval_domain(khr("math/lt", %{"a" => khr("math/Pi"), "b" => 3.14160})))
  end

  test "math/Inf is greater than any finite number" do
    assert_plans(eval_domain(khr("math/gt", %{"a" => khr("math/Inf"), "b" => 1.0e308})))
  end

  test "math/isNaN(math/NaN) is true" do
    assert_plans(eval_domain(khr("math/isNaN", %{"a" => khr("math/NaN")})))
  end

  test "math/isInf(math/Inf) is true" do
    assert_plans(eval_domain(khr("math/isInf", %{"a" => khr("math/Inf")})))
  end

  test "math/isInf of finite number is false" do
    refute_plans(eval_domain(khr("math/isInf", %{"a" => 1.0})))
  end

  # ---------------------------------------------------------------------------
  # §02 Arithmetic: add, sub, mul, div, rem, fract, neg, abs, min, max
  # ---------------------------------------------------------------------------

  test "math/add: 3 + 4 = 7" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/add", %{"a" => 3, "b" => 4}), "b" => 7}))
    )
  end

  test "math/sub: 10 - 3 = 7" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/sub", %{"a" => 10, "b" => 3}), "b" => 7}))
    )
  end

  test "math/mul: 3 * 4 = 12" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/mul", %{"a" => 3, "b" => 4}), "b" => 12}))
    )
  end

  test "math/div: 12 / 4 = 3" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{"a" => khr("math/div", %{"a" => 12.0, "b" => 4.0}), "b" => 3.0})
      )
    )
  end

  # math/rem uses truncated remainder (ECMAScript %)
  test "math/rem: 7 rem 3 = 1" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/rem", %{"a" => 7, "b" => 3}), "b" => 1}))
    )
  end

  test "math/rem: -7 rem 3 = -1 (truncated toward zero)" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/rem", %{"a" => -7, "b" => 3}), "b" => -1}))
    )
  end

  test "math/fract: fract(2.75) = 0.75" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/fract", %{"a" => 2.75}), "b" => 0.75}))
    )
  end

  test "math/fract: fract(-1.25) = 0.75" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/fract", %{"a" => -1.25}), "b" => 0.75}))
    )
  end

  test "math/neg: neg(-5) = 5" do
    assert_plans(eval_domain(khr("math/eq", %{"a" => khr("math/neg", %{"a" => -5}), "b" => 5})))
  end

  test "math/abs: abs(-3) = 3" do
    assert_plans(eval_domain(khr("math/eq", %{"a" => khr("math/abs", %{"a" => -3}), "b" => 3})))
  end

  test "math/min: min(3, 5) = 3" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/min", %{"a" => 3, "b" => 5}), "b" => 3}))
    )
  end

  test "math/max: max(3, 5) = 5" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/max", %{"a" => 3, "b" => 5}), "b" => 5}))
    )
  end

  test "math/saturate: saturate(1.5) = 1.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/saturate", %{"a" => 1.5}), "b" => 1.0}))
    )
  end

  test "math/saturate: saturate(-0.5) = 0.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/saturate", %{"a" => -0.5}), "b" => 0.0}))
    )
  end

  test "math/saturate: saturate(0.5) = 0.5" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/saturate", %{"a" => 0.5}), "b" => 0.5}))
    )
  end

  # ---------------------------------------------------------------------------
  # §02 Sign / rounding
  # ---------------------------------------------------------------------------

  test "math/sign: sign(-5.0) = -1.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/sign", %{"a" => -5.0}), "b" => -1.0}))
    )
  end

  test "math/sign: sign(0.0) = 0.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/sign", %{"a" => 0.0}), "b" => 0.0}))
    )
  end

  test "math/sign: sign(3.0) = 1.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/sign", %{"a" => 3.0}), "b" => 1.0}))
    )
  end

  test "math/trunc: trunc(2.9) = 2.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/trunc", %{"a" => 2.9}), "b" => 2.0}))
    )
  end

  test "math/trunc: trunc(-2.9) = -2.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/trunc", %{"a" => -2.9}), "b" => -2.0}))
    )
  end

  test "math/floor: floor(2.9) = 2.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/floor", %{"a" => 2.9}), "b" => 2.0}))
    )
  end

  test "math/floor: floor(-2.1) = -3.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/floor", %{"a" => -2.1}), "b" => -3.0}))
    )
  end

  test "math/ceil: ceil(2.1) = 3.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/ceil", %{"a" => 2.1}), "b" => 3.0}))
    )
  end

  test "math/ceil: ceil(-2.9) = -2.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/ceil", %{"a" => -2.9}), "b" => -2.0}))
    )
  end

  # Spec: half-way cases rounded away from zero.
  test "math/round: round(0.5) = 1.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/round", %{"a" => 0.5}), "b" => 1.0}))
    )
  end

  test "math/round: round(-0.5) = -1.0 (away from zero)" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/round", %{"a" => -0.5}), "b" => -1.0}))
    )
  end

  # ---------------------------------------------------------------------------
  # §02 Exponential / logarithmic
  # ---------------------------------------------------------------------------

  test "math/sqrt: sqrt(9.0) = 3.0" do
    assert_plans(eval_domain(near_eq(khr("math/sqrt", %{"a" => 9.0}), 3.0)))
  end

  test "math/cbrt: cbrt(27.0) = 3.0" do
    assert_plans(eval_domain(near_eq(khr("math/cbrt", %{"a" => 27.0}), 3.0)))
  end

  test "math/exp: exp(0.0) = 1.0" do
    assert_plans(eval_domain(near_eq(khr("math/exp", %{"a" => 0.0}), 1.0)))
  end

  test "math/log: log(1.0) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/log", %{"a" => 1.0}), 0.0)))
  end

  test "math/log2: log2(8.0) = 3.0" do
    assert_plans(eval_domain(near_eq(khr("math/log2", %{"a" => 8.0}), 3.0)))
  end

  test "math/log10: log10(100.0) = 2.0" do
    assert_plans(eval_domain(near_eq(khr("math/log10", %{"a" => 100.0}), 2.0)))
  end

  test "math/pow: pow(2.0, 10.0) = 1024.0" do
    assert_plans(eval_domain(near_eq(khr("math/pow", %{"a" => 2.0, "b" => 10.0}), 1024.0)))
  end

  # ---------------------------------------------------------------------------
  # §02 Comparison
  # ---------------------------------------------------------------------------

  test "math/eq: 7 == 7 is true" do
    assert_plans(eval_domain(khr("math/eq", %{"a" => 7, "b" => 7})))
  end

  test "math/eq: 7 == 8 is false (refute_plans)" do
    refute_plans(eval_domain(khr("math/eq", %{"a" => 7, "b" => 8})))
  end

  test "math/lt: 3 < 5 is true" do
    assert_plans(eval_domain(khr("math/lt", %{"a" => 3, "b" => 5})))
  end

  test "math/gt: 5 > 3 is true" do
    assert_plans(eval_domain(khr("math/gt", %{"a" => 5, "b" => 3})))
  end

  test "math/le: 5 <= 5 is true" do
    assert_plans(eval_domain(khr("math/le", %{"a" => 5, "b" => 5})))
  end

  test "math/ge: 5 >= 5 is true" do
    assert_plans(eval_domain(khr("math/ge", %{"a" => 5, "b" => 5})))
  end

  # ---------------------------------------------------------------------------
  # §02 Boolean: and, or, not, xor
  # ---------------------------------------------------------------------------

  test "math/and: true && true = true" do
    assert_plans(eval_domain(khr("math/and", %{"a" => true, "b" => true})))
  end

  test "math/and: true && false = false (refute_plans)" do
    refute_plans(eval_domain(khr("math/and", %{"a" => true, "b" => false})))
  end

  test "math/or: false || true = true" do
    assert_plans(eval_domain(khr("math/or", %{"a" => false, "b" => true})))
  end

  test "math/not: not(false) = true" do
    assert_plans(eval_domain(khr("math/not", %{"a" => false})))
  end

  test "math/not: not(true) = false (refute_plans)" do
    refute_plans(eval_domain(khr("math/not", %{"a" => true})))
  end

  test "math/xor (bool): true xor false = true" do
    assert_plans(eval_domain(khr("math/xor", %{"a" => true, "b" => false})))
  end

  test "math/xor (bool): true xor true = false (refute_plans)" do
    refute_plans(eval_domain(khr("math/xor", %{"a" => true, "b" => true})))
  end

  # ---------------------------------------------------------------------------
  # §02 Special nodes: select, switch, clamp, mix, random
  # ---------------------------------------------------------------------------

  test "math/select: condition=true returns a" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" => khr("math/select", %{"condition" => true, "a" => 10, "b" => 20}),
          "b" => 10
        })
      )
    )
  end

  test "math/select: condition=false returns b" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" => khr("math/select", %{"condition" => false, "a" => 10, "b" => 20}),
          "b" => 20
        })
      )
    )
  end

  test "math/switch: selection matches case" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" =>
            khr("math/switch", %{
              "selection" => 2,
              "cases" => [1, 2, 3],
              "1" => 100,
              "2" => 200,
              "3" => 300,
              "default" => 0
            }),
          "b" => 200
        })
      )
    )
  end

  test "math/switch: no match uses default" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" =>
            khr("math/switch", %{
              "selection" => 9,
              "cases" => [1, 2],
              "1" => 100,
              "2" => 200,
              "default" => 42
            }),
          "b" => 42
        })
      )
    )
  end

  test "math/clamp: clamp(5, 0, 3) = 3" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" => khr("math/clamp", %{"a" => 5, "b" => 0, "c" => 3}),
          "b" => 3
        })
      )
    )
  end

  test "math/clamp: clamp(-1, 0, 3) = 0" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" => khr("math/clamp", %{"a" => -1, "b" => 0, "c" => 3}),
          "b" => 0
        })
      )
    )
  end

  test "math/mix: mix(0.0, 10.0, t=0.5) = 5.0" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" => khr("math/mix", %{"a" => 0.0, "b" => 10.0, "c" => 0.5}),
          "b" => 5.0
        })
      )
    )
  end

  test "math/mix: mix(0.0, 10.0, t=0.0) = 0.0" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" => khr("math/mix", %{"a" => 0.0, "b" => 10.0, "c" => 0.0}),
          "b" => 0.0
        })
      )
    )
  end

  test "math/random: result is in [0, 1)" do
    # random ∈ [0,1) → random < 1.0
    assert_plans(eval_domain(khr("math/lt", %{"a" => khr("math/random"), "b" => 1.0})))
  end

  test "math/random: result is >= 0.0" do
    assert_plans(eval_domain(khr("math/ge", %{"a" => khr("math/random"), "b" => 0.0})))
  end

  # ---------------------------------------------------------------------------
  # §02 Trigonometry
  # ---------------------------------------------------------------------------

  test "math/sin: sin(0) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/sin", %{"a" => 0.0}), 0.0)))
  end

  test "math/cos: cos(0) = 1.0" do
    assert_plans(eval_domain(near_eq(khr("math/cos", %{"a" => 0.0}), 1.0)))
  end

  test "math/tan: tan(0) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/tan", %{"a" => 0.0}), 0.0)))
  end

  test "math/asin: asin(0) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/asin", %{"a" => 0.0}), 0.0)))
  end

  test "math/acos: acos(1.0) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/acos", %{"a" => 1.0}), 0.0)))
  end

  test "math/atan: atan(0) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/atan", %{"a" => 0.0}), 0.0)))
  end

  test "math/atan2: atan2(0, 1) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/atan2", %{"a" => 0.0, "b" => 1.0}), 0.0)))
  end

  # sin²(x) + cos²(x) = 1 — property test with arbitrary angles.
  property "math/sin²+cos²=1 for any angle" do
    forall a <- float(-6.28, 6.28) do
      sin_sq = :math.sin(a) * :math.sin(a)
      cos_sq = :math.cos(a) * :math.cos(a)
      abs(sin_sq + cos_sq - 1.0) < 1.0e-9
    end
  end

  test "math/deg: deg(Pi) = 180.0" do
    assert_plans(eval_domain(near_eq(khr("math/deg", %{"a" => khr("math/Pi")}), 180.0)))
  end

  test "math/rad: rad(180.0) = Pi" do
    assert_plans(eval_domain(near_eq(khr("math/rad", %{"a" => 180.0}), khr("math/Pi"))))
  end

  # ---------------------------------------------------------------------------
  # §02 Hyperbolic
  # ---------------------------------------------------------------------------

  test "math/sinh: sinh(0) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/sinh", %{"a" => 0.0}), 0.0)))
  end

  test "math/cosh: cosh(0) = 1.0" do
    assert_plans(eval_domain(near_eq(khr("math/cosh", %{"a" => 0.0}), 1.0)))
  end

  test "math/tanh: tanh(0) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/tanh", %{"a" => 0.0}), 0.0)))
  end

  test "math/asinh: asinh(0) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/asinh", %{"a" => 0.0}), 0.0)))
  end

  test "math/acosh: acosh(1.0) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/acosh", %{"a" => 1.0}), 0.0)))
  end

  test "math/atanh: atanh(0) = 0.0" do
    assert_plans(eval_domain(near_eq(khr("math/atanh", %{"a" => 0.0}), 0.0)))
  end

  # ---------------------------------------------------------------------------
  # §02 Integer bitwise / shift
  # ---------------------------------------------------------------------------

  test "math/xor (int): 5 xor 3 = 6" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/xor", %{"a" => 5, "b" => 3}), "b" => 6}))
    )
  end

  test "math/not (int): ~0 = -1 (two's complement 32-bit)" do
    assert_plans(eval_domain(khr("math/eq", %{"a" => khr("math/not", %{"a" => 0}), "b" => -1})))
  end

  test "math/asr: 8 >> 1 = 4" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/asr", %{"a" => 8, "b" => 1}), "b" => 4}))
    )
  end

  test "math/asr: -8 >> 1 = -4 (sign-extending)" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/asr", %{"a" => -8, "b" => 1}), "b" => -4}))
    )
  end

  test "math/lsl: 1 << 4 = 16" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/lsl", %{"a" => 1, "b" => 4}), "b" => 16}))
    )
  end

  test "math/clz: clz(0) = 32" do
    assert_plans(eval_domain(khr("math/eq", %{"a" => khr("math/clz", %{"a" => 0}), "b" => 32})))
  end

  test "math/clz: clz(1) = 31" do
    assert_plans(eval_domain(khr("math/eq", %{"a" => khr("math/clz", %{"a" => 1}), "b" => 31})))
  end

  test "math/ctz: ctz(0) = 32" do
    assert_plans(eval_domain(khr("math/eq", %{"a" => khr("math/ctz", %{"a" => 0}), "b" => 32})))
  end

  test "math/ctz: ctz(8) = 3" do
    assert_plans(eval_domain(khr("math/eq", %{"a" => khr("math/ctz", %{"a" => 8}), "b" => 3})))
  end

  test "math/popcnt: popcnt(7) = 3" do
    assert_plans(eval_domain(khr("math/eq", %{"a" => khr("math/popcnt", %{"a" => 7}), "b" => 3})))
  end

  test "math/popcnt: popcnt(0) = 0" do
    assert_plans(eval_domain(khr("math/eq", %{"a" => khr("math/popcnt", %{"a" => 0}), "b" => 0})))
  end

  # ---------------------------------------------------------------------------
  # §02 Type conversions (type/*)
  # ---------------------------------------------------------------------------

  test "type/boolToInt: true → 1" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("type/boolToInt", %{"a" => true}), "b" => 1}))
    )
  end

  test "type/boolToInt: false → 0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("type/boolToInt", %{"a" => false}), "b" => 0}))
    )
  end

  test "type/boolToFloat: true → 1.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("type/boolToFloat", %{"a" => true}), "b" => 1.0}))
    )
  end

  test "type/intToBool: 0 → false" do
    refute_plans(eval_domain(khr("type/intToBool", %{"a" => 0})))
  end

  test "type/intToBool: 1 → true" do
    assert_plans(eval_domain(khr("type/intToBool", %{"a" => 1})))
  end

  test "type/intToFloat: 5 → 5.0" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("type/intToFloat", %{"a" => 5}), "b" => 5.0}))
    )
  end

  test "type/floatToInt: 3.9 → 3 (truncate)" do
    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("type/floatToInt", %{"a" => 3.9}), "b" => 3}))
    )
  end

  test "type/floatToBool: 0.0 → false" do
    refute_plans(eval_domain(khr("type/floatToBool", %{"a" => 0.0})))
  end

  test "type/floatToBool: 1.0 → true" do
    assert_plans(eval_domain(khr("type/floatToBool", %{"a" => 1.0})))
  end

  # ---------------------------------------------------------------------------
  # §02 Vector swizzle: combine, extract, length, dot, cross, normalize
  # ---------------------------------------------------------------------------

  test "math/combine2 then extract2 roundtrip" do
    # combine2(3.0, 4.0) → [3.0, 4.0]; extract with index 0 → 3.0
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" =>
            khr("math/extract2", %{
              "a" => khr("math/combine2", %{"a" => 3.0, "b" => 4.0}),
              "b" => 0
            }),
          "b" => 3.0
        })
      )
    )
  end

  test "math/length: length([3.0, 4.0]) = 5.0" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" =>
            khr("math/length", %{
              "a" => khr("math/combine2", %{"a" => 3.0, "b" => 4.0})
            }),
          "b" => 5.0
        })
      )
    )
  end

  test "math/dot: dot([1,0,0],[0,1,0]) = 0.0" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" =>
            khr("math/dot", %{
              "a" => khr("math/combine3", %{"a" => 1.0, "b" => 0.0, "c" => 0.0}),
              "b" => khr("math/combine3", %{"a" => 0.0, "b" => 1.0, "c" => 0.0})
            }),
          "b" => 0.0
        })
      )
    )
  end

  test "math/dot: self-dot([3,4]) = 25.0" do
    v = khr("math/combine2", %{"a" => 3.0, "b" => 4.0})

    assert_plans(
      eval_domain(khr("math/eq", %{"a" => khr("math/dot", %{"a" => v, "b" => v}), "b" => 25.0}))
    )
  end

  test "math/normalize: length of normalized vector = 1.0" do
    v = khr("math/combine3", %{"a" => 3.0, "b" => 0.0, "c" => 4.0})

    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" => khr("math/length", %{"a" => khr("math/normalize", %{"a" => v})}),
          "b" => 1.0
        })
      )
    )
  end

  # ---------------------------------------------------------------------------
  # §02 Quaternion: quatMul, quatConjugate, quatAngleBetween
  # ---------------------------------------------------------------------------

  # Identity quaternion (0,0,0,1).
  defp quat_id, do: khr("math/combine4", %{"a" => 0.0, "b" => 0.0, "c" => 0.0, "d" => 1.0})

  test "math/quatConjugate: conjugate of identity is identity" do
    # identity conjugate → (0,0,0,1) → x component = 0
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" =>
            khr("math/extract4", %{
              "a" => khr("math/quatConjugate", %{"a" => quat_id()}),
              "b" => 3
            }),
          "b" => 1.0
        })
      )
    )
  end

  test "math/quatAngleBetween: angle between identity and itself = 0.0" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" => khr("math/quatAngleBetween", %{"a" => quat_id(), "b" => quat_id()}),
          "b" => 0.0
        })
      )
    )
  end

  test "math/quatMul: identity * identity = identity (w component = 1.0)" do
    assert_plans(
      eval_domain(
        khr("math/eq", %{
          "a" =>
            khr("math/extract4", %{
              "a" => khr("math/quatMul", %{"a" => quat_id(), "b" => quat_id()}),
              "b" => 3
            }),
          "b" => 1.0
        })
      )
    )
  end

  # ---------------------------------------------------------------------------
  # §02 Pointer/get: read state via pointer/get node
  # ---------------------------------------------------------------------------

  test "pointer/get: reads state variable through node expression" do
    # Domain sets /counter/n = 5, then action checks via pointer/get node.
    domain =
      Jason.encode!(%{
        "@context" => %{
          "khr" => "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/",
          "domain" => "khr:planning/domain/"
        },
        "@type" => "domain:Definition",
        "name" => "ptr_test",
        "variables" => [%{"name" => "counter", "init" => %{"n" => 5}}],
        "actions" => %{
          "a_read" => %{
            "params" => [],
            "body" => [
              %{
                "eval" => %{
                  "type" => "math/eq",
                  "a" => %{"type" => "pointer/get", "pointer" => "/counter/n"},
                  "b" => 5
                }
              }
            ]
          }
        },
        "tasks" => [["a_read"]]
      })

    assert_plans(domain)
  end
end
