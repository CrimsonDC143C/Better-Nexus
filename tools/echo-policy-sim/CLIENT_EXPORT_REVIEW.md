# Client export review — 2026-09-29

This records the read-only review before V4 implementation. Its references to
the existing simulator and next work describe that earlier state. The completed
follow-up and current results are in [CATALOG_STUDY.md](CATALOG_STUDY.md).

## Result and evidence boundary

The supplied files help. They provide a concrete catalog, client action protocol,
and more precise distinctions than the hypothetical simulator. They do **not**
contain the normal-board numeric draw algorithm. Request functions send actions
to the server; response handlers receive the selected IDs. This is static client
evidence, not a test of the current server or proof that this export is the active
installation. No reference source was copied into the simulator.

The parallel read-only MPQ inspection located the configured Data directory at
`EBONHOLD_INSTALL/Data`. Its inventory contains 28
archives. I checked that inventory: all six supplied perk paths were found in
`patch-4.MPQ`, and all six extracted SHA-256 values match this report. This
establishes archive/export identity, not proof of live client loading or server
behavior. The inventory also records 58,309 Spell.dbc records in `patch-5.MPQ`;
matching the CSV row count alone does not establish full field equality.
[Private extraction receipt](<PRIVATE_EVIDENCE_ROOT/client-evidence/inventory.json>).

Source links below use the user's local export. The root is
`PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/`.

## Mechanics findings

| Subject | What the source establishes | Remaining uncertainty |
| --- | --- | --- |
| Banish | Client describes removal for the run. Request targets a zero-based slot; server response replaces that one slot. Empty/zero responses are failures. [Tooltip](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks.lua:776>), [response](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_service.lua:350>), [request](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_service.lua:636>) | Does exclusion cover exact ID, quality group, or another identity? Replacement weights are absent. |
| Reroll | Tooltip says the current echoes cannot appear in the next choice, can return later, and their families receive lower odds. Client sends an empty Reroll request and accepts the next server board. [Tooltip](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks.lua:1330>), [request](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_service.lua:629>) | Penalty magnitude, lifetime, stacking, overlap, exclusion identity and frozen-card interaction are not computed here. |
| Selection | Family hint says selecting an Echo raises the chance of more from that family. [Hint](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks.lua:1763>) | Boost magnitude, stacking and application to multi-family Echoes remain unknown. |
| Family versus group | `groupId` is documented as a mutually exclusive perk group. `families` is a separate list of role categories. Cross-quality drop-source lookup uses `groupId`. [Schema and examples](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_data.lua:10>), [cross-quality lookup](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_data.lua:754>) | Role weighting must not silently reuse the simulator's single quality-sibling identity. Server handling of intersecting role categories is absent. |
| Eligibility and caps | Catalog contains `classMask`, `minLevel`, `maxStack`, `requiredSpell`; class and level helpers exist. Learned tome disabling is separate live server state, with a level-one toggle guard. [Schema](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_data.lua:10>), [helpers](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_data.lua:763>), [tome state](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_service.lua:755>) | Catalog membership alone is not the actual eligible pool. Need character, level, discoveries, disabled tomes, owned stacks, and server rules. |
| Freeze | Tooltip promises carry-over to the next selection. Freeze is asynchronous: the UI optimistically increments usage; server failure reverses it. Choice flags distinguish frozen, carried and guaranteed. [Tooltip](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks.lua:734>), [result](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_service.lua:426>), [flags](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_service.lua:143>) | A successful request return is not a confirmed Freeze. Complete live transition semantics still need server evidence. |
| Orb | Client explicitly describes forgetting one stack, server-owned authority, no removal of permanent Echoes, and additive one percentage point per Orb toward the highest eligible quality, with certainty at 100. [Description](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/orb_of_lost_memories.lua:6>), [quality explanation](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/orb_of_lost_memories.lua:203>) | This is a numeric client assertion, not the implementation of `PerksHandler::ApplyOrbQualityBoost`. It does not provide base quality odds or normal-board odds. Orb behavior remains outside the current simulator. |
| Orb redraw | An Orb offer disables normal Reroll/Banish/Freeze. One additional Orb redraws it without forgetting another stack or adding another owed offer. Server charge updates replace optimistic state. [Journal](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/echo_journal.lua:3757>), [redraw](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/orb_of_lost_memories.lua:134>), [reconciliation](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/orb_of_lost_memories.lua:734>) | Must use separate action and resource semantics from normal boards. |

## Important inconsistencies in the export

Do not turn comments into server truth. The service still describes level-one
build activation and guaranteed missing-Echo injection, while the journal and
service error text say snapshots work only at level 80 and leveling draws are
random. The client still parses choice flag 3 and guards it against Banish and
Freeze. [Old service description](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_service.lua:969>),
[journal](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/echo_journal.lua:1470>),
[error text](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_service.lua:1135>).

The Orb file declares a display ceiling of 1000 but a later comment mentions an
80-Orb cap. Neither is verified server capacity.
[Display ceiling](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/orb_of_lost_memories.lua:33>),
[older comment](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/orb_of_lost_memories.lua:738>).

## Catalog and CSV audit

Counts were computed read-only from every catalog row beginning with a numeric
ID and `maxStack`, then joined on exact IDs to the semicolon-delimited
[spell.csv](<PRIVATE_EXPORT_ROOT/spell.csv:1>). This checks linkage, not
server eligibility or authenticity. The catalog header says it was generated
from `world.perks` and last updated 2026-02-23; that text is not proof of the
current installation date. [Header](<PRIVATE_EXPORT_ROOT/patch-4.MPQ/interface/addons/projectebonhold/modules/perks/perks_data.lua:1>)

| Check | Result |
| --- | --- |
| Catalog entries / distinct group IDs | 546 / 304 |
| Quality 0 / 1 / 2 / 3 | 112 / 136 / 186 / 112 |
| Quality 4 | Named in the quality enum, but no catalog entries |
| Maximum-stack distribution | 1: 196; 5: 7; 10: 4; 15: 2; 20: 4; 80: 333 |
| Multi-role / no-role entries | 245 / 66 |
| Role names | Caster DPS, Healer, Melee DPS, Ranged DPS, Survivability, Tank |
| Tome-gated entries / distinct required spells | 195 / 149 |
| Minimum-level values | 1, 10, 20 |
| CSV data rows | 58,309 |
| Exact catalog ID matches in CSV | 546 / 546 |
| Exact required-spell matches in CSV | 149 / 149 |

`spell.csv` supplies spell identities, descriptions and spell effects. Its
`ProcChance` is a spell-proc field, not evidence of Echo draw probability. No
normal-board draw weights are present in its schema. No DPS score was derived.

## Implication for the simulator

The existing sensitivity results remain valid only for their declared synthetic
models. They are not calibrated to this catalog. The simulator currently uses
one `catalog.familyOf` identity for Banish exclusion, selection boosts, and
Reroll penalties. [Simulator](simulator.lua:83), [declared mechanics](MECHANICS.md).
Before a catalog-backed live-policy recommendation, separate exact ID,
quality/mutual-exclusion group, and multi-valued role categories. Use real
per-entry caps and eligibility facts; do not convert the old cap-five control
into a claimed server rule. Do not silently update the frozen studies.

Next simulator work: use a new model version to separate role categories from
quality groups and load catalog-backed caps/eligibility. Preserve the old frozen
experiments as synthetic evidence, not a live policy recommendation. Then collect private
labelled before/action/after boards with character eligibility and run history.
Normal base quality weights, group exclusions, role modifier arithmetic and
modifier lifetime remain unresolved. Further MPQ extraction cannot be presumed
to reveal server-only code.

## Installed archive inspection

Used the installed wow.export 0.2.19 MPQ reader and its decompression modules
unchanged in an isolated Node process. The adapter only permits read-mode archive
access. It did not launch WoW, execute addon Lua, contact the game server, or change
the exporter settings. The private adapter and extraction receipt are beside the
linked inventory. Exported reference source remains outside the Git repository.

All 28 local MPQ hash tables were checked for the named files. A full hash-table
scan agreed with the reader's named lookups. The six perk paths, TOC, constants,
core protocol, utility, and run-resource service paths occurred only in patch-4.
There are no physical ProjectEbonhold or ProjectEbonholdEnhanced AddOns directories
at this installation. This is a local named-file provenance check, not proof of
the server build or an exhaustive inventory of every unnamed archive member.

The reader could not enumerate patch-G's listfile (`incorrect data check`), and
patch-H returned an empty file list. Named hash-table checks still completed for
both. No negative whole-archive content claim is based on those empty lists.

The TOC declares Interface 30300, account-wide SpecCustomNames/ProjectEbonholdDB,
and per-character ActionBarSaverDB. The extracted core sets addon.version to 37.
These are client metadata, not a server version. Player-run response parsing
receives Reroll, Banish and Freeze counters; constants.lua enables Banish but
contains no numeric draw weights. SavedVariables contents were not inspected.

- patch-4.MPQ SHA-256: `99692ed4c08b21df710e23e0f2bbee31458ee529b00fda51605f93487f4e673d`
- patch-5.MPQ SHA-256: `e5849efbcea84738ae00e5f092865fb05abd89dfb8c555177fa825dd3c90152c`
- patch-5 Spell.dbc SHA-256: `dfc560885dfe5d77462885c7cdb02cd3ecb24ca6348fd25c6e1845815b28cdda`
- Installed exporter bundle SHA-256: `83aab66ac2ebe406815bd20acd8b72891a85664ab3691ac0cf0b2c259bf717a5`

## SHA-256 receipt

| Source | SHA-256 |
| --- | --- |
| `perks.lua` | `6fd6b028e7cae05b5a92534926f6f4cc6f1e0ae417e34272fcb1d1809660851f` |
| `perks_data.lua` | `7f320a07a86a04b3717b8dbf813575591a8953c2c6d55bef0ce5772f247469e5` |
| `perks_service.lua` | `52043425c2b32e693e50796ed7ccc6e772b9e93e7b4f0471a698878be6b91f34` |
| `perks_browser.lua` | `00d03bd606df3a588d5e861d018049078c62381a1e34ae015b0b94dee45f41b2` |
| `echo_journal.lua` | `8ec0d3721b526262792fe92a314ee3b2f8809010435599acf5fcb55b07627a13` |
| `orb_of_lost_memories.lua` | `8be57039210e1b66c4057cfb3a8ab8afd0060b568a68aa2afcb07a47f8212846` |
| `spell.csv` | `288abf2be7f0d61a4e9e5600cb877be3d899357564f28956e1e0a1cfcb0fd1bd` |

Read-only source inspection. No game action, source import, policy edit, commit,
publication, or `.vibe` change was performed for this review.
