# Declared mechanics, not a recovered server formula

The local Project Ebonhold client describes run-long Banish removal, next-choice
Reroll exclusion, lower odds for current-offer families after Reroll, and higher
family odds after selection. Exact source and line references are in
`OPTIMIZATION.md`. No third-party source was copied or translated into policy.

Version 3 tests these directions with explicit assumptions:

| Field | Tested values | Exact meaning in this simulator |
| --- | --- | --- |
| `banishExclusion` | `spell`, `family` | Exclude an exact ID or every quality sibling until run end |
| `rerollExcludeCurrent` | `true` | Current three IDs cannot appear in the Reroll replacement batch; held offers stay |
| `selectFamilyBoost` | `1`, `2`, `4` | Multiply weight once when any family member is owned; no per-stack accumulation |
| `rerollFamilyPenalty` | `1`, `0.5`, `0.25` | Multiply weight once for families on a rerolled board |
| `rerollPenaltyLifetime` | `board`, `run` | Penalty lasts for that replacement batch or for the run; repeated penalties do not stack |
| `uniqueOffers` / `maxStacks` | replacement/no cap; unique/cap 5 | Exact-ID uniqueness and exact-ID stack-cap sensitivity |

There are 72 fixed profile combinations and 12 workloads: 864 cells. Neutral
factors are controls. Equal weighting is an experimental convention, not an
estimate of how often real server mechanics occur. Profiles with equivalent
neutral modifiers are retained deliberately. Confidence intervals cluster by
seed and do not count those equivalent profiles as independent samples.

The model excludes combat failures, pending confirmations, hidden server state,
Orb offers, save/restoration, live release gates, and damage/DPS valuation.
It assumes successful actions. Those exclusions prevent a claim of live-game
optimality. The existing execution-safety policy remains unchanged.

## Validation and use

```text
python .tools/lua_jit.py tools/echo-policy-sim/test_mechanics.lua
python tools/echo-policy-sim/test_optimal_v3.py
python tools/echo-policy-sim/optimal_v3.py --output build/optimal-v3.json
python tools/echo-policy-sim/test_v3_oracle.py --lupa-path .tools/lupa
python tools/echo-policy-sim/sensitivity.py --lua python .tools/lua_jit.py --output build/mechanics-study
python tools/echo-policy-sim/early_study.py --lua python .tools/lua_jit.py --output build/early-study
```

`optimal_v3.py --scenario INPUT.json --output RESULT.json --limit 200000` also
solves a supplied finite state. Its `model` object accepts the `optimal.py`
fields plus required `boost`, `penalty`, `lifetime`, and `exclude_current`.
Modifiers can be exact fraction strings. The `state` object uses zero-based
board indices as in `exact-example.json`. The exact reference has no hidden
future sequence and does not emit a certificate when its limit is exceeded.
Only accept a result from a command that exits successfully; an older output
file is not a new certificate after a failed run. The JSON entrypoint assumes
no prior Banish or persistent-penalty history. Mid-run reference tests supply
those explicit state masks through the Python state API. Do not omit real
history when interpreting an observed board.

## Evidence required for a live-optimality claim

Obtain a current server formula, or a private labelled capture corpus sufficient
to estimate its parameters. Required information includes the eligible pool and
weights by state, quality/family exclusion identity, stack caps, the exact scope
and lifetime of Reroll exclusion, and boost/penalty magnitude and accumulation.
Static client tooltips do not establish these values. Unlabelled success totals
alone cannot identify them.

Do not replace unknown odds with the sensitivity grid's values. Do not install
an experimental policy merely because it wins an aggregate synthetic study.
