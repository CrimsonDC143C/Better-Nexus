# Private stutter diagnostics

This private diagnostic path records elapsed operation spans and the global Lua
heap before and after those spans. It does not establish addon CPU, allocated
bytes, garbage collection time, hitch causation, or an FPS improvement. Existing
Lua error counts are separate evidence: no retained errors does not mean the
frame time was acceptable.

It defaults OFF on every load, independently of ordinary Performance timings,
assignment detail, StutterAlert trace and script profiling. Nothing is written to
SavedVariables. Enabling it introduces observation overhead and changes the Lua
heap being observed. Keep an ordinary OFF window separate from a brief ON
window; do not format reports, copy exports or compare source hashes inside a
measurement window. Keep the actual build, views, workload, settings, interval
and enabled states with the results. No setting, action or spending change is
required by this diagnostic API.

The supported API is:

```lua
Nexus.Performance.ResetDiagnostics()
Nexus.Performance.SetDiagnosticEnabled(true)
Nexus.Performance.DiagnosticEnabled()
Nexus.Performance.SetDiagnosticEnabled(false)
Nexus.Performance.SnapshotDiagnostics()
```

Turn it OFF before requesting an export. **Collect both the full Nexus prepared
support report and the StutterAlert report.** The full Nexus report must include
the new span/timing, global net heap and assignment-detail sections, with their
actual enabled states and availability flags. Retain the complete prepared
report, not only its short support summary; identify any missing or truncated
section. SnapshotDiagnostics returns a detached copy without reading a clock or
heap. A reload resets this session-only evidence and restores diagnostics OFF;
collect both reports before reloading.

The fixed labels are `orb.status`, `orb.read`, `orb.panel`, `echo.reconcile`,
`hud.prepare`, `lifecycle.update`, `sync.update`, `gameadapter.poll`, `dps.update`
and `lifecycle.phase.catalog`. Each has a fixed aggregate. The ring retains at
most 32 completed or failed spans, with nesting depth limited to 16. Span IDs
refer only to this reset generation and are assigned when a span begins; parent
spans therefore can complete after their children. The ring order is completion
order, not start-ID order. Older parents/children may have left the ring, so an
absent parent is not evidence that a retained span was a root.

`startedMs`/`endedMs` use the millisecond clock, normally debugprofilestop.
`sessionStart`/`sessionEnd` are independent actual GetTime readings. They are
never reconstructed from elapsed milliseconds. Frozen GetTime is common within
one frame: the elapsed sample can remain valid while sessionWindowAvailable is
false. The hitch provider excludes such spans from window matching. A timer
failure, backwards elapsed time or clock-generation change withholds elapsed;
it is not a measured zero. Reader failures and callback failures remain visible
and do not alter the callback's results or error object.

Elapsed is inclusive. `residualMs` subtracts only valid, nonoverlapping direct
child intervals from that same invocation. Failed, bypassed or invalid child
coverage withholds the residual. This residual is elapsed time left outside the
measured direct children, not exclusive addon CPU. Do not add parent/child
totals or sum overlapping inclusive spans.

`heapNetKB` is GLOBAL Lua heap after minus before, read with
`collectgarbage("count")`. It includes other addons, collection and diagnostic
overhead; it can be negative. It does not identify the operation's allocations,
the responsible addon or GC duration. Missing/nonfinite heap samples remain
unknown. Parent/child heap deltas overlap and must not be summed as allocation.
The implementation never forces collection, changes GC configuration or invokes
UpdateAddonMemoryUsage. Reader injection methods are for deterministic source
tests; the export identifies an injected reader rather than claiming it used
the live global heap API.

The StutterAlert API v1 shape and its legacy operation selection are preserved.
Additional fields declare frame/profiler windows as exact, partial or unmatched.
Legacy operation bounds are explicitly marked as derived from a session end and
elapsed duration. New spans carry observed session boundaries and nesting. Even
exact consumer windows establish temporal overlap only: they do not supply
same-window addon CPU or prove that the operation caused the hitch.

The independently checked installed StutterAlert API v1 consumer accepts this
provider but its sanitizer retains only legacy summary/name/duration/fields. It
discards the new geometry, heap and diagnostic fields and does not call the
optional CollectDiagnosticSnapshot method. **Its copied report alone cannot
carry the new evidence or establish an exact span/hitch join.** The new fields
must be collected through the full Nexus prepared support report alongside the
StutterAlert report. Differing profiler windows and frozen GetTime remain
partial or unmatched even with both reports. No third-party addon change,
protocol change or consumer version bump is part of this private candidate.
