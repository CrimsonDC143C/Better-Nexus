# Rolling-policy optimization evidence

## Current tested recommendation

Update: the client catalog distinguishes role categories from quality groups.
The V3 recommendation below applies only to its frozen synthetic model. See
[CATALOG_STUDY.md](CATALOG_STUDY.md) for the corrected V4 experiment before using
any result as a basis for live-policy work.

Use `adaptive-0-settle` as the **offline implementation candidate**, with an
explicit validated Mechanics Profile. It is not a live-server optimum.

- Protect all still-needed exact copies. Under family-wide Banish exclusion,
  also protect every family that still contains a needed target.
- Preserve a second needed offer with Freeze when both copies can be used.
  Do not preserve a surplus copy or spend Freeze on the last pick.
- Select needed unfrozen offers before consuming held ones. Prioritize
  remaining copies relative to the declared current draw weight.
- If only a needed held offer remains, select it instead of spending Banishes
  searching around it.
- On an unwanted board, prefer Banish before Reroll when exclusion lasts for
  the run. Prefer Reroll first in the no-exclusion control model.
- For Banish, prefer the safe unwanted ID/family with the greatest declared
  draw weight. Do not add the experimental early-Banish override merely because
  it wins a small exact example.

The candidate is `C.Get('adaptive-0-settle')` in `candidates.lua`. The released
policy remains unchanged. The full safety and observation contract is still
required before any live integration. In particular, do not silently substitute
hypothetical weights when live weights are unknown.

## Client-informed version-3 sensitivity results

Training: 216,000 runs on seeds 400001..400050. Selection was frozen before
518,400 held-out runs on seeds 500001..500200. There are 864 fixed cells.

| Policy | Completed / 172,800 | Completion | Mean missing | Mean search charges |
| --- | ---: | ---: | ---: | ---: |
| adaptive-0-settle | 44,352 | 25.667% | 1.9631 | 8.6239 |
| banish-family-safe-pair | 42,540 | 24.618% | 2.0016 | 8.6653 |
| released | 35,891 | 20.770% | 2.2011 | 8.6428 |

Adaptive versus incumbent: +1.049 percentage points, paired seed-cluster 95%
interval [0.741, 1.356]. Against released: +4.896 points [4.333, 5.460].
There are 4,522 paired wins and 2,710 losses against the incumbent. Aggregate
point estimates are higher in 70/72 profiles and tied in two. This is not a
per-run guarantee. Per-profile intervals are exploratory, not multiple-testing
adjusted. All probabilities here describe synthetic workloads, not live success
rates. Unknown magnitudes and the grid are documented in `MECHANICS.md`.

The held-out phase took 454.61 seconds including all three policies and CSV
output. This is offline throughput, not measured in-game decision latency.
Source and raw-trial hashes were verified. One seed replayed across all cells
and policies reproduced all 2,592 complete-run records exactly.

Training CSV SHA-256: `d3a5d282276dcb3a0d19e60d70d2445832aa8e9c93c0d5e4a206d121b6e2095b`.
Evaluation CSV SHA-256: `23534c0455805442441d9b4affdc3f601bd9efbcb783c4a210107dc7194fae5d`.

## Proof boundary

The exact-guided early-Banish challenger was tested separately on fresh seeds.
It closes seven small-model cases, including the two previously measured gaps,
but it does not generalize. Training used 56,160 complete runs; the predeclared
selection kept adaptive-0-settle. Held-out testing then covered 561,600 runs:

| Model set | Early Banish completion | Adaptive completion | Early minus adaptive, 95% interval |
| --- | ---: | ---: | --- |
| V2, 72 cells | 14.049% | 14.688% | -0.639 points [-1.012, -0.266] |
| V3, 864 cells | 25.102% | 26.197% | -1.095 points [-1.586, -0.605] |

The challenger is retained as reproducible negative evidence in
`early_banish.lua`, not included in the recommendation. `build/early-study`
contains frozen selection, all raw trials, source hashes and losing examples.
This rejects a broad early-Banish rule; it does not refute the exact optimum
for the particular small states where early Banish is correct.

`optimal.py` and `optimal_v3.py` can prove the best action for a fully specified
finite state when their searches finish. This is the exact algorithm, not a
claim that every large corpus state has been solved. The research heuristics
are not global-optimality certificates. `test_v3_oracle.py` drove 12,000 complete
Lua runs with exact oracle decisions; observed rates matched their exact
probabilities within the fixed calibration tolerance.

A proof of the best **live** policy remains blocked by the server transition
model: eligible pool, draw weights, exclusion identity, modifier magnitude,
duration, accumulation, and caps. The inspected client Lua contains descriptions
but no recovered numeric family-weight formula. Another heuristic tournament
cannot remove that uncertainty. No live policy was installed or published.

## Validation and local handoff

- All 233 listed offline addon tests passed. The full suite began before the
  V3 extension; all directly affected simulator checks were repeated afterwards.
- Exact rational tests, independent Python/Lua transition tests, 432 fast/full
  projection comparisons, mechanics calibration, protocol checks, oracle-driven
  complete runs and deterministic replay passed.
- Legacy V1 fingerprint remains `6207c2f6`. Released 864-decision fingerprint
  remains `74e21b53`. Native Lua 5.1 syntax checks passed.
- Review is a bounded self-review. No independent agent review or live gameplay
  validation is claimed.
- Review fixed one versioned-interface defect: V3 penalty history must not be
  added to the V2 observation contract. The V2 seam test caught it. The fix
  removes an unused empty field for V1/V2 only; V3 inputs and all policy outcomes
  remain unchanged. Post-fix tests and saved-study replays verify that claim.
- Study inputs were frozen and hash-verified at `e673638` before that interface
  correction. The reports retain those original source hashes; they are not
  rewritten to imply a study ran on a later tree.
- All changes in this optimization turn are research tools and documentation.
  Existing Orbweaver files, the live Nexus default and GitHub state are unchanged.

Recommended next step: validate the mechanics profile from current server rules
or private labelled captures before a separately reviewed Nexus policy change.
The exact solver can then measure optimal actions for tractable real states;
larger-state claims still require an explicit computation or regret bound.

## Exact reference

`optimal.py` computes a true finite-model optimum by backward induction. It
enumerates all safe legal actions and all draw outcomes with rational arithmetic.
`--scenario INPUT.json --output RESULT.json` accepts model and observed-state
objects; `--limit` bounds exact states. A failed or incomplete search does not
emit an optimal certificate. Small-model optimality is not live-server proof.

Eleven exact benchmark cases compare complete policies, not just their first
action. The current candidates all have counterexamples. In the weighted
two-target, two-pick case with an available Banish, the optimum can Banish a
trash offer before taking a visible target. The adaptive policy still loses
`27373/672000` completion probability in that particular exclusion model.
`build/planner-gaps.json` records every exact value and action.

## Fresh version-2 study

Six model-aware candidates were selected on seeds 220001..220200: 100,800
training runs including the incumbent. Selection was frozen before seeds
320001..321000: 216,000 evaluation runs.

| Policy | Completed / 72,000 | Completion | Mean missing | Mean search charges |
| --- | ---: | ---: | ---: | ---: |
| adaptive-0-settle | 10,872 | 15.100% | 2.3182 | 8.6846 |
| banish-family-safe-pair | 10,793 | 14.990% | 2.3244 | 8.7520 |
| released | 8,717 | 12.107% | 2.5217 | 8.6966 |

Adaptive versus incumbent: +0.110 percentage points, paired seed-cluster 95%
interval [-0.009, +0.229]. This does **not** establish an improvement over the
incumbent. There are 492 paired completion wins and 413 losses. Against released:
+2.993 points [2.713, 3.273]. The six mechanics hypotheses have equal weight;
these intervals measure seed variation, not server-model uncertainty.

`plan-16` uses observation-derived random samples and complete-run continuations
through the actual production policy. It cannot inspect executor seeds or future
draws. Its five-seed exploratory training trial completed 74/360 versus 83/360
for the incumbent and took 191.47 seconds for both policies. It was not promoted
to held-out evaluation. A higher sample count exists for experiments, but has not
been validated as a better policy. Sampled planning is neither exact nor proven
to improve the incumbent. The faster projection passed 432 complete-run parity
checks against the full production adapter.

## Evidence limits found during optimization

Read-only local client source:
`PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks.lua`.
SHA-256 `6fd6b028e7cae05b5a92534926f6f4cc6f1e0ae417e34272fcb1d1809660851f`.

- Line 776 describes Banish as removing a perk for the run.
- Line 1330 describes next-choice Reroll exclusion and lower family odds.
- Line 1763 describes a family draw boost after selection.

These are client descriptions, not the server implementation. Version 2 does
not model the latter two effects. Magnitudes, duration, stacking, quality and
eligibility rules are not established by that text. A live-optimality claim
would therefore be false even if every version-2 scenario were solved exactly.
The version-3 study above tests explicit, labelled sensitivity assumptions.
It does not invent or install a server formula.

All work remains offline and local. No Orbweaver addon, live Nexus default,
installation, GitHub state or release was changed.
