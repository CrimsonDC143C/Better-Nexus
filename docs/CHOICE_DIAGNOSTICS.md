# Echo choice and Orb diagnostic evidence

The support summary and prepared report separate three sources. An ordinary
Echo choice may exist while the Orb service is idle and the runner has never
started. None of these fields proves ownership, a successful roll or server
freshness.

## Observation contract

- `Echo choice` records the existing `GameAdapter.Board()` or Orb adapter
  `GetCurrentChoice` read. No additional native read is made. A plain dense
  response containing one to three valid spell-ID rows is `present`; a plain
  explicit empty table is `absent`. Nil, errors, missing APIs and malformed
  responses are `unknown`. Native nil semantics have not been established.
- `observedAt` is whole client uptime seconds, not UTC. `age` is elapsed client
  time since that evaluation. `recent` means at most one client second old;
  it is a diagnostic sampling bound, never an action or server-response gate.
  A stale sample, unavailable/regressed clock, interrupted/blocked Orb Status
  read, world leave/entry or logout cannot assert current absence/presence.
  `lastPresence` and `lastCount` preserve the sampled historical result.
- `sampleEpoch`, `currentEpoch` and `world` come from events received by the
  existing Main dispatcher since this addon load. They do not identify a
  server session or prove that a service mirror has hydrated after loading.
  Only a subsequent ordinary read records a sample in the new epoch.
- `Orb service` records the existing classifier, preserving its return values
  and arity. Only a recent `IDLE` result establishes `offer=absent`; `PENDING`
  establishes present. Unknown, invalid, missing or malformed capability is
  unknown. `status` and `lastOffer` remain the last normal read's facts.
- `Orb runner` reads initialized session memory without constructing a runtime,
  querying saved data, starting observers, sending or saving. Its receipt is
  unknown before initialization. State codes distinguish deliberate Stop,
  completion, resource exhaustion, no safe sources and recovery. They do not
  imply ordinary choice absence. The Orb-owner lifecycle epoch is unavailable
  until that owner's frame exists; it is distinct from Main's world context.
- Boundary comparisons are retained evidence. `changed_age` dates the stored
  comparison; `read_age` dates the last ordinary read even if values stayed
  stable. `scope=retained current=no` applies after completion too.

The views return detached scalar tables. No raw API error, card contents,
player identity or payload is retained in the new block. The report formats
fixed keys/codes. A prepared report is frozen when built: its printed ages do
not tick afterward. Rebuilding a report does not refresh native state.

## Reviewed scope and remaining gaps

The source review was pinned to public main
`18dc5b0313033dbc522bec1ab89c304078aa5645`. Actual Claude Opus 5.5 returned
all four requested report sections from a 74-file public-source packet. Its
controller terminated with a local maximum-cost error, so this is retained
review input, not a successfully completed provider run or approval. Findings
were checked against source before implementation. No private reports or
saved player data were shared. Changed implementation requires separate review.

| Review area | Disposition in this change |
| --- | --- |
| Ordinary choice and error/absence conflation (D1) | Existing-read sampling, tri-state presence, reason and age. Nil stays unknown. |
| Orb-service capability and offer state (D2) | Separate passive classifier sample and freshness. |
| Runner state omitted without a receipt (D3) | Pure runner view and uninitialized report guard. A hypothetical nil Store result is not asserted as a production defect. |
| Retained comparison age (D4) | Changed/read ages and an explicit retained/not-current label. |
| Lifecycle observer scope (D5) | Main observation context plus explicit Orb-owner observer availability. No gameplay epoch change. |
| Recovery slot/pick ages and Continue refusal breakdown (D6-D7) | Deferred; new choice block must not be used to reinterpret an older receipt. |
| Other action-latch history (D8) | Deferred; no latch watchdog or dead-latch behavior change. |
| General log-export purity and charge wording (D9-D10) | Deferred to a separate log-export audit. This change covers support-report evidence only. |
| Echo rejection export and roll-trace schema (D11-D12) | Deferred; no trace schema/Sync changes. |
| Continue-view side effects (D13) | Uninitialized report no longer calls recovery/Continue/history constructors. Existing initialized Continue-view behavior is deferred. |
| Board fingerprint comment/behavior and export privacy alignment (D14-D15) | Deferred, outside this diagnostic slice. |

## Verification and limits

Regression fixtures cover idle/stopped runners with an open choice; explicit
empty, nil, malformed, missing and raising APIs; clock loss/regression; old and
transition-invalidated samples; unknown Orb service states; report collection
without native reads/runtime initialization; and retained completed-operation
comparisons. Existing purity, ownership, transition and report guards remain
required, followed by the complete registered suite.

The additions use bounded scalar samples and at most four raw choice-key checks;
there is no new frame, timer, polling loop, network message or saved schema.
CPU/frame cost is not measured. Native API empty-response semantics, live loading
behavior and clipboard/export bytes have not been tested here. This diagnostics
PR does not diagnose or fix a particular live Orb failure, add retry policy,
automatically resume a run, merge code or publish a build.
