# Build-hash source query coalescing

`BuildHashCache.CheckSource` read the current passive catalog source, then
`SameSource` immediately read that same source again to compare its identity.
Both run inside one cache operation with no intervening mutation or callback.
In a real-TOC synthetic settled lifecycle, 40 frames made 80 source queries
from the build-hash pump. The existing diagnostic timer named `catalog.status`
measures `BuildCatalog.ManualPreparationStatus`, not `BuildCatalog.Status`.

The comparison now accepts the fresh source description already validated by
`CheckSource`. It is a local value on that call's stack, never a retained cache
or a frame-wide authorization. Other `SameSource` callers continue to read a
fresh description. The next pump, digest read or marker read still checks the
current catalog before serving anything. This reduces settled hash-pump source
queries from two to one without changing the pump's frequency or work budget.

The following contracts remain required:

- A refused saved root, owner, map, binding or generation serves no old digest
  or marker authority, including replacements with unchanged revisions.
- A same-source pending transaction keeps the admitted serving root; a false
  `ready` flag alone does not invalidate its digest.
- Committed publication invalidates/rebuilds through existing subscriptions
  and bounded work, preserving the canonical delta and legacy bytes.
- Warm collection, job source checks, diagnostic queries and callbacks retain
  their fresh-read behavior. No result is reused across public operations.

`hash_cache_source_coalescing` exercises the actual lifecycle seam, first
failing with 80 queries in 40 frames and then requiring 40. It also checks
unchanged idle work counters, exact digest preservation, immediate root-swap
refusal, recovery and pending/publication behavior. Existing source-refusal,
same-revision identity, warm-budget and collision-budget regressions cover
the other boundaries. Disposable mutations that retain a source across calls
or remove the source comparison must fail those correctness regressions.

Full validation exposed a pre-existing ordering defect in the Orb pick-evidence
test: it allowed a healthy retry before installing the throwing writer. A
retimed control reproduces that failure on the unchanged UI baseline too. The
test now installs the throwing writer before advancing either tick and asserts
that a throwing flush was attempted. Production Orb behavior is unchanged.

Offline call reduction is not a native FPS improvement. Native A/B requires
the same UI, profile, scene, addon set and comparable dataset/transport work.
The installed UI build is unchanged until a separately sealed candidate is
selected and the designated operator has fresh control and a quiet window.
