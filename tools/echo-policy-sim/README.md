# Echo roller search-order experiment

## Current scope: finish the simulator, not the Orbweaver addon

The user retired Orbweaver addon development on 2026-09-29. This project now
researches rolling logic for Better-Nexus. It does not build or repair the
Orbweaver addon, its Transaction engine, or its controller. Existing Orbweaver
files remain preserved. Nothing here is installed into the live game.

See [OPTIMIZATION.md](OPTIMIZATION.md) for the current recommendation and exact
optimality limits. [RESULTS.md](RESULTS.md) preserves the earlier 576,000-run
study. Its winner was superseded by further model-aware research, not installed
into Nexus. [MECHANICS.md](MECHANICS.md) separates client descriptions from
unverified server constants.

[CATALOG_STUDY.md](CATALOG_STUDY.md) documents the newer local-catalog model.
It separates role categories from quality groups and uses real per-entry caps.
Older synthetic tournament rankings are not a calibrated live recommendation.

The finished policy laboratory is run from the repository root:

```text
python tools/echo-policy-sim/evaluate.py --output build/policy-lab
```

It needs LuaJIT on PATH. A different Lua command can be supplied explicitly.
For this task's isolated Windows runtime:

```text
python tools/echo-policy-sim/evaluate.py --lua python .tools/lua_jit.py --output build/policy-lab
```

This one command runs probability/safety tests, trains 15 declared candidates
over 72 workload/mechanics cells, freezes candidate selection, and evaluates
the selected policies on separate seeds. Defaults: 200 training seeds per cell
and 1,000 evaluation seeds per cell. The objective is user-approved: complete
Wishlists first, missing copies second, search actions third. Resource counts
remain separate; there is no DPS scoring or invented resource exchange rate.

Read `build/policy-lab/report.md`. The same directory contains raw CSV trials,
the pre-evaluation selection receipt, source hashes, artifact hashes and JSON
totals. Failures stop the run; incomplete trials are not counted as successes.
Small smoke runs can use `--train 3 --test 4`; fewer than 30 evaluation seeds
do not receive a confidence interval or an improvement claim.

`candidates.lua` is the executable handoff for later Nexus implementation.
Candidates vary search order, one-Banish limits, resource reserves, pair-only
Freeze and Wishlist-family protection. They cannot see future draws or seeds.
The released planner remains a control, not a reimplementation.

`corpus.lua` covers short/long runs, large pools, rare targets, quality siblings,
exact copies, scarce resources, Freeze-only use, partial builds and impossible
completion. Version 2 uses calibrated keyed random streams. Profiles vary
Banish exclusion and duplicate/stack-cap assumptions. Reported confidence
intervals measure seed variation on the fixed corpus, not server-rule certainty.

The version-1 experiment below is retained as an audit fixture. Its small
corpus and older draw generator are **not** the policy-selection study.

## Version-1 audit fixture

This tool compares **Reroll-first** with **Banish-first** over complete, bounded,
synthetic Wishlist runs. It calls the real `Nexus.Policy.Decide` route. It does
not duplicate the planner. It does not run the addon or perform game actions.

Run from the repository root with Lua 5.1 or LuaJIT:

```text
lua5.1 tests/prototype/search_order_sim.lua
lua5.1 tools/echo-policy-sim/compare.lua
lua5.1 tools/echo-policy-sim/compare.lua 1000
```

The optional count is an integer from 1 to 10,000. The default uses seeds 1..200,
three resource budgets, three exclusion assumptions, two policies, and three
paired fixed examples: **3,606 runs**. The new regression is also registered in
`tools/run_prototype_tests.py` and the normal CI inventory.

## What changes between policies

`EchoWeaver.Decide` accepts `policy.banishBeforeReroll=true`. When the existing
Reroll branch is eligible, this option first uses a legal Banish if available.
After its replacement arrives, the planner evaluates the new board again.
It can use more than one Banish before Reroll. It still selects needed offers
and respects the existing permission, resource, pending, frozen, observed
guaranteed-card, and Orb guards.

`NEXUS_POLICY` does **not** enable this option. There is no new live setting,
UI control, saved variable, or executor. The simulator temporarily enables it
and restores the original options on success or failure. It stops when exact
Wishlist counts are met, picks are exhausted, the policy waits, or the action
bound is reached. A bound or wait is not completion.

## Version 1 assumptions — HYPOTHETICAL / UNPROVEN

| Mechanic | Explicit experiment rule |
| --- | --- |
| Draws | Independent weighted draws with replacement from the supplied ordered pool. Weights are synthetic, not measured odds. |
| Banish | Spend one charge; replace only the target slot. |
| Exclusion `none` | No later pool exclusion. |
| Exclusion `spell` | Exclude that exact ID for the rest of this synthetic run. |
| Exclusion `family` | Exclude its entire catalog family, including quality siblings. This can remove needed targets. |
| Reroll | Spend one charge; redraw all non-frozen slots. The production two-frozen guard remains active. |
| Freeze | Spend one charge; hold that slot across redraws and selections until selected. |
| Selection | Add one exact ID copy; spend one pick; redraw unheld slots if another pick is needed. |
| Confirmation | The synthetic executor assumes each allowed action succeeds. This is not native confirmation evidence. |

The client reference exposes a slot-specific Banish replacement event. It does
not establish server pool exclusions, odds, quality weights, or future offers.
These profiles are sensitivity experiments, **not** implementation of live pool
shaping. They do not establish server stack caps, resource regeneration,
eligibility changes, guarantees, lock/save behavior, combat behavior, latency,
or action rejection/reconciliation. No DPS or theoretical damage scoring is used.

The executor feeds the resulting synthetic observation back to the planner.
It never changes a decision to get an expected outcome. Invalid scripted draws,
empty eligible pools, unsupported profile versions, invalid actions, and resource
overspend fail the run. There is no fallback that invents a successful draw.

Seeded streams are keyed by action kind, that action's ordinal, and slot. Thus
the same ordinal Reroll uses the same variates in both policies even when one
policy spends Banishes first. Exclusion can change the distribution intentionally.
These paired synthetic samples are not statistical estimates of live success.

## Reading results

The report prints example summaries, trace fingerprints, and totals for each profile,
budget, and policy. `complete` counts runs meeting every exact target;
`missing` sums remaining copies. All action/resource columns are totals, not
per-run means. `draws` excludes the supplied initial board. There is no combined
efficiency score: saving a Reroll can cost a Banish or a completed Wishlist.

At the default seed count, the fixture fingerprint is `6207c2f6`. Repeated native
Lua 5.1.5 and LuaJIT 2.1 (Lupa bridge) outputs match after newline decoding.
The unchanged release decision battery remains `74e21b53` (432 states / 864
decisions). Do not update either value merely to make a test pass.

## Integration assessment and scope

The audited release is `v1.20.0-beta.1-test.9050`, commit
`8f03ade7821f530dbf04adda7019372e67966725`.
Its live call path is `AutomationRuntime.StepRun -> Policy.Decide ->
EchoWeaver.DecideNexus -> EchoWeaver.Decide`. It uses a separate Orb runtime.
It does **not** import Orbweaver's shared Automation Run engine or call its
`Engine.Run` acceptance facade. The inspected Orbweaver Normal Board policy
also checks Reroll before Board Banish. A Banish-first rule is not missing from
this port; it is a separate policy experiment.

This is a new, small Better-Nexus test tool. No private Orbweaver source,
historical addon source, reference addon source, or third-party planner was
copied. It is not a replacement for Orbweaver's full-run acceptance tests,
Transaction coordinator, ledger, recovery, or native validation gates.

## Conclusion

Banish-first is not always more efficient. The fixed examples prove both a
saved Reroll and a wasted Banish. The family-exclusion example also shows why
unknown mechanics matter. At the base budget, 200 synthetic runs produce:

| Assumed exclusion | Reroll-first complete | Banish-first complete | Rerolls used (R / B) | Banishes used (R / B) |
| --- | ---: | ---: | ---: | ---: |
| None | 41 | 19 | 389 / 400 | 600 / 600 |
| Exact ID | 87 | 109 | 382 / 338 | 593 / 599 |
| Family | 64 | 82 | 385 / 345 | 594 / 599 |

Do not choose the live default from these assumed pools. First establish native
Banish exclusion scope and draw/eligibility rules, then add evidence-backed
profiles and representative Wishlist/pool fixtures. Keep the live default
unchanged until that comparison supports a change.
# Exact reference

`optimal.py` enumerates every safe legal action and every possible draw for a
finite declared model. It uses rational arithmetic and backward induction.
Its value is lexicographic: complete Wishlist probability, fewer expected
missing copies, then fewer expected search actions. Individual charge types
are not assigned invented exchange rates. This proves a model-conditional
optimum, not live-server optimality. Pool weights and exclusion rules remain
hypotheses. Pool exhaustion or a state limit fails without a certificate.

```text
python tools/echo-policy-sim/test_optimal.py
python tools/echo-policy-sim/test_model_bridge.py --lupa-path .tools/lupa
python tools/echo-policy-sim/optimal.py --lupa-path .tools/lupa --output build/optimal-reference.json
python tools/echo-policy-sim/optimal.py --scenario tools/echo-policy-sim/exact-example.json --output build/exact-decision.json
```

The bridge requires `lupa` with its `luajit21` runtime. It loads the real Lua
candidate and production modules. The exact solver itself uses only Python's
standard library. `.tools/lupa` is an optional isolated installation path.
Differential tests feed the same observed actions and draws to both independent
transition implementations and compare complete-run results.

With one needed Echo of weight 1 in a total weight of 4, one pick, a trash
board, one Banish and one Reroll: no-exclusion completion is exactly 175/256
for either order. Reroll first needs 91/64 expected search actions; Banish
first needs 7/4. With exact-ID exclusion, optimal Banish first reaches 65/81,
versus the released policy's 23/32. There is no universal fixed-order winner.

The scenario JSON uses zero-based pool indices for the three board entries.
An entry can also be `[index, held, guaranteed]`. `owned` defaults to zero;
`freeze` defaults to zero. The returned action index is also zero-based.
The JSON entrypoint needs no Lua dependency and accepts no unknown mechanics
fields. An exact state budget failure must not be treated as a policy result.

## Model-based optimization

See `OPTIMIZATION.md` for new exact gaps and fresh-seed findings. Run:

```text
python tools/echo-policy-sim/planner_gaps.py --lupa-path .tools/lupa
python tools/echo-policy-sim/test_plan_study.py
python .tools/lua_jit.py tools/echo-policy-sim/test_planning.lua
python tools/echo-policy-sim/plan_study.py --lua python .tools/lua_jit.py --candidates adaptive-0-hold,adaptive-0-settle,adaptive-2-hold,adaptive-2-settle,adaptive-4-hold,adaptive-4-settle --train 200 --test 1000 --train-start 220001 --test-start 320001 --output build/adaptive-study
```

The `plan-16` and `plan-64` candidates perform bounded sampled complete-run
rollouts. They are slow experimental policies, not exact or recommended live
policies. The model-aware adaptive candidates also remain lab-only. The study
keeps the incumbent if training does not select a challenger.
