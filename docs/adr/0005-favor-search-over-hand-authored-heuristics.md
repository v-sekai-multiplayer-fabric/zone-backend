# Favor generic, compute-scalable search over hand-authored domain heuristics

- Status: accepted
- Date: 2026-07-16
- Deciders: K. S. Ernest (iFire) Lee

## Context and Problem Statement

New RECTGTN domains (starting with the in-progress ArtifactsMMO domain, and
already visible in retrospect in `skill_allocation`) can be authored two
ways: as many hand-crafted methods, each encoding a specific human-chosen
strategy for a specific case (e.g. one `craft_<item>` method per recipe,
each with its own author-decided "gather vs. already-have" branch order), or
as a small number of generic methods that recurse over data and leave the
choice among alternatives to the planner's own search/backtracking.

The first style front-loads authoring cost per case and caps solution
quality at how clever the author was for that case. It doesn't get better as
the domain grows or as more compute is thrown at planning — every new item,
recipe tier, or edge case needs its own hand-written method. This does not
scale to ArtifactsMMO's actual size (300+ craftable items, multi-tier
recipe graphs) or generalize to other domains without repeating the
authoring cost each time.

## Decision Drivers

- Sutton's "Bitter Lesson" (http://www.incompleteideas.net/IncIdeas/BitterLesson.html):
  general methods that leverage computation (search) consistently beat
  methods that encode human domain knowledge, as problem scale grows.
- This session's own native-planner work already invested in exactly the
  kind of lever this decision depends on: `tw_seek_plan`'s fast-path
  linear-advancement loop, the `tw_witness_oracle` pruning cache, and
  `TW_MAX_DEPTH` are all knobs that make backtracking search cheaper and
  deeper — capacity that sits unused if domains route around search with
  hand-authored strategy instead.
- Practical scale: ArtifactsMMO's recipe graph is large and will keep
  changing (seasons/patches); a method-per-item authoring style means
  re-authoring on every content update.

## Considered Options

1. **Author one method (or a small handful) per recipe/case, encoding a
   specific human-decided strategy in each.** Fast to write for a single
   case, does not scale, quality capped by author cleverness, cannot
   improve by spending more compute.
2. **Author a small number of generic, data-driven methods whose
   alternatives are resolved by the planner's search over facts (`ref`
   data), not by author-chosen branch order.** Slower to design once, scales
   to arbitrarily many cases without new authoring, and improves as search
   budget (depth, witness-oracle exploration) increases.
3. **Replace HTN methods entirely with flat STRIPS-style goal regression,
   no hand-authored decomposition structure at all.** Maximally
   compute-driven, but throws away RECTGTN's actual model (methods,
   alternatives, `bind`/`scan`) and is a different planner, not a domain-
   design choice within this one.

## Decision Outcome

Chosen: **option 2**. Domain actions still encode real game facts
(preconditions, effects, durations) — those are not heuristics and stay
hand-authored, they're the ground truth the planner searches over. But
where a method must choose among strategies (e.g. "gather materials first"
vs. "already have them", later "gather vs. buy from market"), it is
expressed as one generic alternative set over data (e.g. an
`ensure_have(item, qty)` method recursing over a recipe graph supplied as
`ref` data) rather than as many bespoke per-case methods that bake in a
pre-decided strategy. When search over this generic structure proves too
slow or shallow for a given problem size, the fix is to spend more search
compute (raise `TW_MAX_DEPTH`, widen witness-oracle exploration, extend
budget) — not to add hand-authored heuristics back in.

This does not forbid hand-authored structure everywhere: RECTGTN is HTN, not
raw STRIPS, so some decomposition is inherent to the model (option 3 is
rejected). The line is between *facts* (always hand-authored: what an action
requires/produces) and *strategy* (should be generic + search-resolved, not
author-decided per case).

### Consequences

- Good: new content (recipes, items, cases) extends the data the generic
  methods recurse over, not the method count — no re-authoring per item.
- Good: aligns domain-design effort with where this session already spent
  engineering effort (native search performance/depth), instead of leaving
  that capacity unused behind hand-authored shortcuts.
- Bad: generic methods are harder to reason about per-case than a bespoke
  method with an obvious, author-chosen branch order; debugging a bad plan
  may require inspecting search behavior rather than reading one method.
- Neutral: this raises the importance of the native planner's search
  performance/depth ceiling (`TW_MAX_DEPTH`, witness-oracle budget) as a
  first-class lever for domain authors, not just an internal implementation
  detail.

## More Information

Motivated by, and first applied to, the in-progress ArtifactsMMO domain
(`priv/plans/domains/artifactsmmo.jsonld`, not yet committed as of this
ADR). Retrofit consideration: `skill_allocation`'s `allocate_job` method
(`assign_to_qualified` / `train_and_assign`) already follows this shape by
construction — two generic alternatives resolved by a `check`, not a
per-engineer or per-job hand-written method — and is the pattern this ADR
generalizes.
