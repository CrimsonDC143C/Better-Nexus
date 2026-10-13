# Rolling logic recommendation — 2026-09-29

Use **`banish-family-safe-pair`** as the candidate for the next Better-Nexus
rolling-policy implementation. It is the best training-selected policy among
the 15 declared candidates. It also has the lowest worst-profile training
regret. This is a simulator recommendation, not a claim of universal optimality
or measured live-server performance.

Orbweaver addon development is abandoned. This work is a completed simulator
study for Nexus, not a restart of the Orbweaver implementation/controller.

## Held-out result

Training: 200 seeds x 72 workload/mechanics cells x 15 policies = **216,000 runs**.
Evaluation: 1,000 different seeds x 72 cells x 5 preselected policies = **360,000 runs**.
Selection was written to `selection.json` before any evaluation run started.

| Policy | Complete builds / 72,000 | Completion | Missing copies/run |
| --- | ---: | ---: | ---: |
| Released Nexus policy | 9,017 | 12.52% | 2.520 |
| Banish-first only | 9,500 | 13.19% | 2.487 |
| Banish-first + pair Freeze + family protection | 10,982 | 15.25% | 2.327 |

Selected candidate gain: **+2.73 percentage points**, paired seed-cluster 95%
interval **[+2.44, +3.02]**. Mean missing copies decrease by **0.193/run**,
interval **[-0.202, -0.185]**. Its aggregate completion gain is positive in all
six mechanics profiles: +1.48 to +3.65 percentage points.

The objective is completion, not minimum charges. Per run, the candidate uses
5.497 Banishes, 2.988 Rerolls and 0.264 Freezes; the released policy uses 5.458,
3.055 and 0.181 respectively. Do not call this a reduction in every resource.

## Exact policy handoff

The executable reference is `candidates.lua`, candidate
`banish-family-safe-pair`. Its observation seam calls the real released planner.

1. Keep the existing readiness, permission, protected-card, exact-copy,
   pending-action, Orb-context and two-frozen Reroll guards.
2. At the existing no-needed-offer Reroll branch, prefer an available legal
   Banish. Reassess after each replacement. There is no one-Banish limit or
   additional reserve threshold in this candidate.
3. Do not Banish any card in a Wishlist family, including wrong-quality siblings.
   Choose another legal disposable card; if none exists, evaluate the planner
   with Banish disabled for that decision.
4. Replace the initial single-offer Freeze rule with pair preservation: with
   at least two picks remaining and two selectable still-needed offers, Freeze
   one before taking the other. Do not Freeze a guaranteed/protected card or
   a duplicate that the next selection makes surplus. A Banish charge is not
   required merely to enable this pair Freeze.
5. Keep the released selection/held-card behavior otherwise. Pair-only initial
   Freeze does not remove the existing later search around an already held card.

No live implementation, installation, push, release or controller work occurred.
The candidate is lab-only; the live `NEXUS_POLICY` default is unchanged.

## Counterexamples and scope

Across 72,000 paired evaluation cases, the candidate completes when the released
policy fails in **2,857** cases. The released policy completes when the candidate
fails in **892** cases. They tie on completion in **68,251** cases. Net: **1,965**
additional complete builds. The candidate does not win every individual run.

Reproducible losses include:

| Profile | Workload | Seed | Candidate missing copies | Released missing copies |
| --- | --- | ---: | ---: | ---: |
| none-replacement | small-balanced | 100975 | 1 | 0 |
| none-replacement | tight-copies | 100072 | 1 | 0 |
| none-replacement | tight-copies | 100418 | 2 | 0 |

Replay these seeds using `trials.lua START COUNT released,banish-family-safe-pair`.
It emits all corpus cells so the exact profile/workload can be selected from CSV.

The corpus contains 12 fixed workloads and six alternative mechanics models.
Weights, run-long Banish exclusion, duplicate handling and stack caps are
explicit hypotheses. Intervals measure seed sampling, not uncertainty about
real server rules. There is no DPS scoring, hidden future-draw access, save/Orb
or combat simulation. This study does not finish or depend on an Orbweaver addon.

## Reproduce and inspect

```text
python tools/echo-policy-sim/evaluate.py --output build/policy-lab
```

LuaJIT must be on PATH, or supply `--lua` as documented in README.md. The task's
Windows run used `--lua python .tools/lua_jit.py` with Lupa 2.8 / LuaJIT 2.1.
Read `build/policy-lab/report.md`, `result.json`, `selection.json`, and raw CSVs.
The full study checked source hashes before reporting success.

Raw training SHA-256: `00f321d6183628a16325d59437bebd618c00d15097956607722fa5e536f57e6f`.
Raw evaluation SHA-256: `f54e8b97c05f189aca4507c323590cfaf5b28e2a8e90c71908f8b5b2a0eb97f7`.

Validation: 6 focused Lua files passed; 1,280 legacy simulator checks; 6,616 lab
checks; 5 Python protocol tests; 1,500 cross-runtime RNG values matched; repeat
small tournaments produced byte-identical artifacts. Inventory contains 233
Lua checks. This checkpoint did not rerun all unrelated addon checks; the prior
checkpoint passed its then-complete 232-test suite. V1 fixture fingerprint
`6207c2f6` and release control fingerprint `74e21b53` remain unchanged.
