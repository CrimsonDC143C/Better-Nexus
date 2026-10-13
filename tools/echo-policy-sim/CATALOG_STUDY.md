# Catalog-backed Normal Board study

## Scope

Version 4 separates exact spell IDs, quality/mutual-exclusion groups (`groupId`),
and multi-valued role categories (`families` in the client catalog). Version 3
used one quality-sibling identity for both exclusion and weight modifiers. Its
frozen results remain valid for that synthetic model; they are not a calibrated
live recommendation. See [CLIENT_EXPORT_REVIEW.md](CLIENT_EXPORT_REVIEW.md).

The importer reads generated catalog rows as data. It never executes the source
Lua. Catalog facts and their SHA-256 receipt remain under ignored `build/`.
No Project Ebonhold source or catalog is shipped in this repository or addon.
The ordinary production policy still runs through `Nexus.Policy.Decide`.

## Reproduce locally

From the repository root, provide your own local client export:

The import/study commands require Python 3.10 or newer and a Lua 5.1-compatible
runtime. The checked local environment uses Python 3.14 and LuaJIT 2.1.

```text
python tools/echo-policy-sim/catalog_import.py PATH/TO/perks_data.lua
python tools/echo-policy-sim/test_catalog_import.py
python .tools/lua_jit.py tools/echo-policy-sim/test_catalog_model.lua
python tools/echo-policy-sim/catalog_study.py --lua python .tools/lua_jit.py --catalog build/catalog/catalog.lua --output build/catalog-study --train 20 --test 100
```

The `.tools/lua_jit.py` launcher is the local Windows LuaJIT environment, not a
WoW client. With LuaJIT on PATH use `--lua luajit`. The generated local catalog
has no executable source from the addon; it is an input table made by the importer.
Only load generated catalogs you trust; the Lua runner loads that generated table
with `dofile`. The importer rejects malformed rows rather than silently dropping
them. Supported role labels are ASCII letters and spaces.

## Declared experiment

| Input | Meaning |
| --- | --- |
| Catalog | 546 entries from the supplied export; source hash in the local receipt |
| Character snapshots | Class bits 1, 4, 128; fixed level 20; either no prerequisite spells or all prerequisite spells known and enabled |
| Workloads | Two exact targets with one copy each over 40 selections; three targets with two copies each over 70 selections |
| Resources | Respectively Banish/Reroll/Freeze = 6/4/3 and 12/8/4 |
| Targets | Stable ID ordering with one target per quality group; selected before policy evaluation |
| Base weights | Equal weight per eligible exact ID; an explicit hypothesis, not recovered server odds |
| Banish exclusion | Exact ID or quality group for the rest of the scenario; not entire role category |
| Role modifiers | Neutral; or selection x2 and Reroll x0.5 |
| Multiple roles | Apply each modifier once if any role matches, or once per matching role |
| Modifier history | Ownership activates a role once, not once per stack; Reroll marks each offered role once, with no repeated-action stacking |
| Penalty lifetime | Replacement batch only, or remainder of scenario |
| Caps | Exact-ID cap from the catalog; shared group-cap semantics are not established |
| Boards | Three distinct exact IDs; Reroll excludes current exact IDs for its replacement batch; held cards stay |

There are 12 profile combinations and 12 character/Wishlist workloads: 144 cells.
Neutral profiles duplicate outcomes across penalty lifetime deliberately. Cells
have equal experimental weight, not observed frequency. The fixed character level
does not simulate leveling from 1 to 80. The workload horizons are synthetic
opportunities, not a claim about the game's level schedule.

Class masks, minimum levels, prerequisite spell state, and exact-ID stack caps
filter draws. Zero class mask means unavailable. This implements the client data
rules; it does not establish all hidden server eligibility conditions. Discoveries,
mutual-exclusion behavior beyond the declared Banish rule, base quality odds,
group-wide caps, native failures, combat, Orbs, saves, and restoration remain out
of scope. No DPS score or damage valuation is used.

All policies see observations and the declared model, never draw seeds or future
offers. V4 supplies the adaptive candidate with effective role-adjusted pool
weights after eligibility/cap filtering. That is model knowledge, not a claim that
these values can be obtained from the live client. Older observation contracts
remain unchanged.

## Protocol and outputs

Training uses seeds 900001..900020. The selected policy is written to
`selection.json` before held-out seeds 1000001..1000100 run. All four candidates
remain in evaluation: released, Reroll with pair-Freeze, group-safe Banish with
pair-Freeze, and the prior adaptive candidate. Ranking is complete Wishlists,
then missing copies, then total search actions. Separate charge counts remain
visible. No monetary exchange rate is assigned to charges.

`result.json` includes aggregate and per-profile results, paired wins/losses,
seed-cluster intervals, source hashes, and raw CSV hashes. Intervals describe
random-seed variation within this fixed corpus, not uncertainty in server rules
or generalization to all Wishlists. Fewer than 30 evaluation seeds are smoke
checks and get no improvement interval. Failures and incomplete trials fail
the command; they are not counted as successful outcomes.

## Result

The frozen training selection was `adaptive-0-settle`. Training comprised 11,520
runs; held-out evaluation comprised 57,600 runs. All four candidates received
the same 14,400 held-out cells/seeds. No candidate changed during the study.

| Policy | Complete Wishlists | Completion | Mean missing copies | Mean search charges |
| --- | ---: | ---: | ---: | ---: |
| Adaptive | 2,776 | 19.2778% | 1.787500 | 14.991875 |
| Protected Banish-first + pair-Freeze | 2,705 | 18.7847% | 1.787361 | 14.993403 |
| Reroll-first + pair-Freeze | 2,469 | 17.1458% | 1.893472 | 14.440764 |
| Released | 2,424 | 16.8333% | 1.903750 | 14.456111 |

Adaptive versus released: +2.4444 percentage points; paired seed-cluster 95%
interval [+1.3310, +3.5579]. It wins 1,725 pairs and loses 1,373, for 352 net
additional completions. It spends about 0.536 more search charges per run.
This matches the user's completion-first ranking, not minimum resource use.

Adaptive versus protected Banish-first: +0.4931 points; interval
[-0.2560, +1.2421]. The measured lead is **inconclusive**. It wins 815 pairs and
loses 744. The simpler candidate also has a fractionally lower mean missing-copy
count. Do not describe adaptive as proven superior to that candidate.

Adaptive's point estimate exceeds released in all 12 profiles, but falls below
protected Banish-first in five. These are descriptive comparisons, not separate
per-profile confidence claims. No unique winner is established.

The supported research direction remains: take needed offers; protect usable
second offers; on unwanted boards, compare safe Banish-first search against
Reroll-first. This does not establish that Banish should precede every selection,
or that either policy is the best live policy. Current server probabilities
remain unknown. Do not deploy hypothetical weight-aware choices to the addon.

Measured training/evaluation wall times were 139.932 and 739.117 seconds, including
CSV output and all policies. These are offline batch times, not live decision latency.

Artifact SHA-256 values:

- Training CSV: `1c213bed0ee32e2c8170d9ecec54862fb8bb6c63febbbfcf8a64d572e340716c`
- Evaluation CSV: `c137e09708645549d29eaf76f6ddf78e38e01430a5992e8057ced08c83ba7f35`

## Remaining calibration evidence

The current local Nexus logs contain 46 unlabelled board observations, not a
complete before/action/confirmed-after calibration corpus. A proposed action is
not evidence of a successful server transition. No private log records were
copied into this repository or used to fit this study.

Calibration needs verified server rules or private labelled runs with full owned
stacks, character eligibility, prerequisite/disabled state, offered IDs and flags,
resource counters, the actual action, and its confirmed response. This is needed
to distinguish base odds, Banish exclusion scope, and role-modifier arithmetic
and lifetime. More draws from invented odds cannot supply that missing evidence.

## Validation

- Importer: four tests plus a command-line guard against output outside ignored
  `build/`. The current source imports 546 records with a deterministic receipt.
- V4 module and complete-run checks: role overlap/group distinction, class/level/
  prerequisite/cap behavior, malformed profiles, 3,000-draw calibration (630/3,000
  versus analytic 4/19), and 120 synthetic full/fast production comparisons.
- Actual catalog: 576 complete-run full/fast pairs agree. Native Lua 5.1 and
  LuaJIT agree on all recorded fields in 576 complete catalog-backed runs.
- Legacy: 432 V2 and 2,592 V3 study records replay exactly. V1 fingerprint stays
  `6207c2f6` across 3,606 runs. Existing policy lab: 6,616 checks pass. Planning
  projection: 432 complete-run pairs pass. Exact-reference tests remain green.
- Full repository suite on the delivered code: 233 passed, 0 failed, 0 not run.
  This is an offline LuaJIT test suite, not a WoW or live-server test.
- Final held-out replay: all 576 records for seed 1000001 match every recorded
  field. Source and raw-artifact hashes were rechecked after evaluation.
