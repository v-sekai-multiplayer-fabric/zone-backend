alias Taskweft

# ── Load domain fixtures ──────────────────────────────────────────────────────

domains_dir  = Path.join([__DIR__, "../priv/plans/domains"])
problems_dir = Path.join([__DIR__, "../priv/plans/problems"])

read = fn path -> File.read!(path) end

simple_travel    = read.(Path.join(domains_dir,  "simple_travel.jsonld"))
blocks_world     = read.(Path.join(domains_dir,  "blocks_world.jsonld"))
healthcare       = read.(Path.join(domains_dir,  "healthcare.jsonld"))

bw_1a  = read.(Path.join(problems_dir, "blocks_world_1a.jsonld"))
bw_1b  = read.(Path.join(problems_dir, "blocks_world_1b.jsonld"))
bw_2a  = read.(Path.join(problems_dir, "blocks_world_2a.jsonld"))
bw_2b  = read.(Path.join(problems_dir, "blocks_world_2b.jsonld"))
bw_3   = read.(Path.join(problems_dir, "blocks_world_3.jsonld"))

hc_one = read.(Path.join(problems_dir, "healthcare_one.jsonld"))
hc_two = read.(Path.join(problems_dir, "healthcare_two.jsonld"))

robosub = read.(Path.join(problems_dir, "robosub_full_mission.jsonld"))
rescue_move   = read.(Path.join(problems_dir, "rescue_move.jsonld"))
rescue_survey = read.(Path.join(problems_dir, "rescue_survey.jsonld"))

# Pre-compute a plan to use for replan/temporal checks
{:ok, bw_3_plan}     = Taskweft.plan(bw_3)
{:ok, robosub_plan}  = Taskweft.plan(robosub)
{:ok, hc_one_plan}   = Taskweft.plan(hc_one)

IO.puts("\n=== Taskweft planner benchmark (C++20 NIF) ===\n")

Benchee.run(
  %{
    # ── Planning latency ──────────────────────────────────────────────────────
    "plan/simple_travel"    => fn -> Taskweft.plan(simple_travel) end,

    "plan/blocks_world_1a"  => fn -> Taskweft.plan(bw_1a) end,
    "plan/blocks_world_1b"  => fn -> Taskweft.plan(bw_1b) end,
    "plan/blocks_world_2a"  => fn -> Taskweft.plan(bw_2a) end,
    "plan/blocks_world_2b"  => fn -> Taskweft.plan(bw_2b) end,
    "plan/blocks_world_3"   => fn -> Taskweft.plan(bw_3) end,

    "plan/healthcare_one"   => fn -> Taskweft.plan(hc_one) end,
    "plan/healthcare_two"   => fn -> Taskweft.plan(hc_two) end,

    "plan/robosub_full"     => fn -> Taskweft.plan(robosub) end,
    "plan/rescue_move"      => fn -> Taskweft.plan(rescue_move) end,
    "plan/rescue_survey"    => fn -> Taskweft.plan(rescue_survey) end,

    # ── Temporal check (plan already computed) ────────────────────────────────
    "check_temporal/blocks_world_3" =>
      fn -> Taskweft.check_temporal(bw_3, bw_3_plan) end,
    "check_temporal/robosub_full"   =>
      fn -> Taskweft.check_temporal(robosub, robosub_plan) end,
    "check_temporal/healthcare_one" =>
      fn -> Taskweft.check_temporal(hc_one, hc_one_plan) end,

    # ── Replan (first step fails) ─────────────────────────────────────────────
    "replan/blocks_world_3/step_0" =>
      fn -> Taskweft.replan(bw_3, bw_3_plan, 0) end,
    "replan/robosub_full/step_0"   =>
      fn -> Taskweft.replan(robosub, robosub_plan, 0) end,
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [fast_warning: false]
)
