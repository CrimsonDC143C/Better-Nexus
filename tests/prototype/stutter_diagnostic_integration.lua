-- Provider compatibility and actual-window disclosure, using synthetic clocks.
-- No native frame, addon CPU, allocation attribution or hitch-causation claim.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function pack(...) return {n=select('#', ...), ...} end
_G.Nexus = {}
local ms, seconds, heap = 0, 10, 500
local clockReads, sessionReads, memoryReads = 0, 0, 0
_G.GetTime = function() return seconds end
dofile('core/Performance.lua')
dofile('core/StutterAlertIntegration.lua')
local P, I = Nexus.Performance, Nexus.StutterAlertIntegration
local function clock() clockReads = clockReads + 1; return ms end
local function session() sessionReads = sessionReads + 1; return seconds end
local function memory() memoryReads = memoryReads + 1; return heap end
local function setup(on)
    P.SetEnabled(false)
    P.SetClock(clock)
    P.SetDiagnosticEnabled(false)
    P.SetDiagnosticSessionClock(session)
    P.SetDiagnosticMemoryReader(memory)
    P.ResetDiagnostics()
    P.Reset()
    P.SetDiagnosticEnabled(on == true)
    ms, seconds, heap = 0, 10, 500
    clockReads, sessionReads, memoryReads = 0, 0, 0
end
local function context(startTime, endTime, profileEnd, profileWindow)
    return {addonName='Nexus',hitchStartTime=startTime,hitchEndTime=endTime,
        profilingTimestamp=profileEnd,profileWindowMs=profileWindow}
end
local function contains(value, wanted)
    if value == wanted then return true end
    if type(value) == 'table' then
        for key, child in pairs(value) do
            if contains(key, wanted) or contains(child, wanted) then return true end
        end
    end
    return false
end

-- Existing v1 operation contract remains usable with diagnostics OFF. Its
-- derived legacy geometry is disclosed and must not become exact invocation data.
setup(false)
P.SetEnabled(true)
P.Measure('automation.fallback.repair', function() ms, seconds = 4, 10.004 end)
local snapshotMethod, offSnapshotCalls = P.SnapshotDiagnostics, 0
P.SnapshotDiagnostics = function()
    offSnapshotCalls = offSnapshotCalls + 1
    return snapshotMethod()
end
local result = I.Collect(context(10, 10.010, 10.010, 10))
check(type(result.summary) == 'string' and #result.operations == 1,
    'legacy provider v1 summary/operations shape retained')
check(result.operations[1].name == 'automation.fallback.repair'
    and result.operations[1].durationMs == 4 and type(result.operations[1].fields) == 'table',
    'legacy v1 operation remains available while diagnostic OFF')
check(result.operations[1].geometry:find('derived', 1, true) ~= nil,
    'legacy inferred span geometry is labelled derived')
check(result.diagnostics.enabled == false and #result.diagnostics.spans == 0,
    'legacy call does not arm new diagnostics')
check(offSnapshotCalls == 0, 'diagnostic OFF legacy collection does not call optional snapshot')
P.SnapshotDiagnostics = snapshotMethod

-- Matched frame/profiler windows retain independent exact bounds; nested
-- diagnostic spans provide actual parent identity and observed session geometry.
setup(true)
local argument = {private='private source record'}
local values = pack(P.MeasureDiagnostic('orb.panel', function(a)
    check(a == argument, 'integration callback argument identity')
    ms, seconds = 2, 10.002
    P.MeasureDiagnostic('orb.read', function()
        ms, seconds, heap = 6, 10.006, 490
    end)
    ms, seconds, heap = 10, 10.010, 480
    return argument, nil
end, argument))
check(values.n == 2 and values[1] == argument, 'diagnostics retain callback arity')
result = I.Provider.Collect(I.Provider, context(10, 10.020, 10.020, 20))
check(result.windowRelationship == 'exact' and result.diagnostics.overlapStatus == 'exact',
    'exact frame/profile geometry explicitly classified')
check(result.frameStartTime == 10 and result.frameEndTime == 10.020
    and result.profileStartTime == 10 and result.profileEndTime == 10.020,
    'both original windows retained')
check(result.searchedWindowStart == 10 and result.searchedWindowEnd == 10.020,
    'search window is explicit')
check(#result.operations == 2 and #result.diagnostics.spans == 2,
    'diagnostic-only operations preserve v1 shape')
local outer, inner = result.operations[1], result.operations[2]
check(outer.name == 'orb.panel' and outer.durationMs == 10
    and outer.startTime == 10 and outer.endTime == 10.010 and outer.depth == 1,
    'largest elapsed operation uses actual observed boundaries')
check(inner.name == 'orb.read' and inner.parent == outer.sequence and inner.depth == 2,
    'nested operation has exact retained parent identifier')
check(outer.heapAvailable and outer.heapBeforeKB == 500 and outer.heapAfterKB == 480
    and outer.heapDeltaKB == -20, 'provider preserves signed global heap net')
check(type(outer.fields) == 'table' and #outer.fields == 0
    and outer.geometry == 'observed session bounds', 'v1-compatible scalar geometry without payload fields')
check(result.correlationMeaning:find('not same-window addon CPU', 1, true) ~= nil
    and result.diagnostics.heapMeaning:find('not allocated', 1, true) ~= nil,
    'same-window geometry does not imply CPU/allocation attribution')
check(not contains(result, 'private source record') and not contains(result, argument),
    'callback argument/payload never exported')

-- The two windows must stay separate when one is wider. Do not replace a
-- partial overlap with a single matched window or synthesize uncovered wall time.
result = I.Collect(context(10.005, 10.020, 10.030, 40))
check(result.windowRelationship == 'partial' and result.diagnostics.overlapStatus == 'partial',
    'mismatched frame/profile windows classified partial')
check(result.frameStartTime == 10.005 and result.frameEndTime == 10.020
    and result.profileStartTime == 9.990 and result.profileEndTime == 10.030,
    'partial windows exported independently')
check(result.searchedWindowStart == 9.990 and result.searchedWindowEnd == 10.030,
    'expanded union search disclosed')
check(result.unattributedWallMs == nil and result.exclusiveCpuMs == nil,
    'partial evidence has no fabricated wall-time or CPU remainder')
result = I.Collect(context(10, 10.020))
check(result.windowRelationship == 'unmatched' and result.diagnostics.overlapStatus == 'unmatched',
    'missing profiler window remains unmatched')
check(result.profileStartTime == nil and result.profileEndTime == nil,
    'unavailable profiler bounds remain nil')
check(next(I.Collect(context(30, 31, 31, 1000))) == nil,
    'nonoverlapping diagnostics do not become correlated operations')

-- Frozen GetTime cannot be reconstructed by dividing a different elapsed
-- clock. A later valid span may be exported alongside an unmatched counter.
setup(true)
P.MeasureDiagnostic('orb.status', function() ms = 8 end)
check(next(I.Collect(context(9.9, 10.1, 10.1, 200))) == nil,
    'all-frozen span set returns valid empty v1 result')
P.MeasureDiagnostic('orb.read', function() ms, seconds = 11, 10.003 end)
result = I.Collect(context(9.9, 10.1, 10.1, 200))
check(#result.diagnostics.spans == 1 and result.diagnostics.unmatchedSpanCount == 1,
    'frozen span excluded with explicit unmatched count')
check(result.operations[1].name == 'orb.read', 'valid span is not displaced by unmatched duration')

-- Provider selection and report snapshots stay bounded and detached. Snapshot
-- collection reads no clocks/heap and remains an optional user-report action.
setup(true)
for index=1, 40 do
    P.MeasureDiagnostic('orb.read', function()
        ms, seconds = ms + index, seconds + index / 1000
    end)
end
result = I.Collect(context(10, 11, 11, 1000))
check(#result.operations == 5 and #result.diagnostics.spans == 5,
    'provider exports at most five overlapping operations')
check(result.operations[1].durationMs == 40 and result.operations[5].durationMs == 36,
    'largest elapsed spans selected deterministically')
result.diagnostics.spans[1].name = 'tampered private'
check(I.Collect(context(10, 11, 11, 1000)).diagnostics.spans[1].name == 'orb.read',
    'provider result has no retained aliases')
local beforeClock, beforeSession, beforeMemory = clockReads, sessionReads, memoryReads
local report = I.Provider.CollectDiagnosticSnapshot(I.Provider)
check(report.version == 1 and report.diagnostics.enabled
    and #report.diagnostics.spans == 32 and #report.diagnostics.rows == 10,
    'user-report snapshot bounded by diagnostic limits')
check(type(report.assignmentDetail) == 'table' and report.assignmentDetail.enabled == false,
    'assignment detail remains separately default OFF in report')
check(clockReads == beforeClock and sessionReads == beforeSession and memoryReads == beforeMemory,
    'snapshot collection performs no clock or heap reading')
report.diagnostics.spans[1].name = 'tampered private'
check(I.CollectDiagnosticSnapshot().diagnostics.spans[1].name == 'orb.read',
    'report snapshot is detached')

-- Invalid consumer context and optional-reader failure cannot throw into the
-- attributed hitch path or masquerade as a populated valid provider report.
check(next(I.Collect(nil)) == nil and next(I.Collect({})) == nil,
    'invalid context is valid empty v1 table')
check(next(I.Collect({addonName='Other',hitchStartTime=10,hitchEndTime=11})) == nil,
    'other addon context refused')
check(next(I.Collect(context(11, 10))) == nil
    and next(I.Collect(context(0/0, 11))) == nil,
    'inverted/nonfinite windows refused')
local recent, diagnostics = P.RecentOperations, P.SnapshotDiagnostics
P.RecentOperations = function() error('optional reader failure') end
check(next(I.Collect(context(10, 11))) == nil, 'recent-reader failure isolated as valid empty')
P.RecentOperations = recent
P.SnapshotDiagnostics = function() error('optional diagnostic reader failure') end
check(next(I.Collect(context(10, 11))) == nil and I.CollectDiagnosticSnapshot() == nil,
    'diagnostic-reader failure isolated in both optional methods')
P.SnapshotDiagnostics = diagnostics

-- Optional diagnostics must not erase an existing legacy v1 breadcrumb when
-- their method or data is missing/malformed/failing. Lookup itself must not
-- invoke an optional __index constructor or poisoned facade.
setup(false)
P.SetEnabled(true)
check(P.SetDiagnosticEnabled(true), 'optional failure controls explicitly arm diagnostics')
P.Measure('lifecycle.update', function()
    ms, seconds = 1, 10.001
    P.Measure('lifecycle.phase.catalog', function() ms, seconds = 6, 10.006 end)
    ms, seconds = 9, 10.009
end)
local function legacySurvives(message)
    local collected = I.Collect(context(10, 10.020, 10.020, 20))
    local operation = collected.operations and collected.operations[1]
    check(operation and operation.name == 'lifecycle.update' and operation.durationMs == 9,
        message..': existing v1 name/duration retained')
    local fields = {}
    for _, field in ipairs(operation.fields) do fields[field.key] = field.value end
    check(fields.mode == 'lifecycle.phase.catalog' and fields.outcome == 5,
        message..': existing v1 classification retained')
end
P.SnapshotDiagnostics = nil
legacySurvives('optional method absent')
local failingSnapshotCalls = 0
P.SnapshotDiagnostics = function()
    failingSnapshotCalls = failingSnapshotCalls + 1
    error('optional snapshot failure')
end
legacySurvives('optional snapshot throws')
check(failingSnapshotCalls == 1, 'optional throwing snapshot actually invoked in ON control')
P.SnapshotDiagnostics = 42
legacySurvives('optional method nonfunction')
P.SnapshotDiagnostics = nil
local optionalLookupCalls, priorMeta = 0, getmetatable(P)
setmetatable(P, {__index=function(_, key)
    if key == 'SnapshotDiagnostics' then
        optionalLookupCalls = optionalLookupCalls + 1
        error('optional facade lookup must not run')
    end
end})
legacySurvives('poisoned optional facade lookup')
check(optionalLookupCalls == 0, 'optional diagnostic method lookup does not invoke __index')
setmetatable(P, priorMeta)
P.SnapshotDiagnostics = function()
    return setmetatable({}, {__index=function() error('optional snapshot metadata failure') end})
end
legacySurvives('poisoned optional snapshot metadata')
P.SnapshotDiagnostics = function()
    return {enabled=true,spans='invalid collection'}
end
legacySurvives('malformed optional span collection')
P.SnapshotDiagnostics = diagnostics
local enabledMethod, enabledLookupCalls = P.DiagnosticEnabled, 0
P.DiagnosticEnabled = function() error('optional enablement reader failure') end
legacySurvives('optional enablement reader throws')
P.DiagnosticEnabled = nil
priorMeta = getmetatable(P)
setmetatable(P, {__index=function(_, key)
    if key == 'DiagnosticEnabled' then
        enabledLookupCalls = enabledLookupCalls + 1
        error('optional enablement facade lookup must not run')
    end
end})
legacySurvives('poisoned optional enablement facade')
check(enabledLookupCalls == 0, 'optional enablement lookup does not invoke __index')
setmetatable(P, priorMeta)
P.DiagnosticEnabled = enabledMethod

-- Registration is the unchanged optional v1 protocol; no stronger API or
-- extra registration is required to receive the added report method.
local registered, unregistered, received = 0, 0, nil
_G.StutterAlert = {DIAGNOSTIC_PROVIDER_API=1,
    RegisterDiagnosticProvider=function(name, provider)
        registered = registered + 1; received = provider
        return name == 'Nexus'
    end,
    UnregisterDiagnosticProvider=function(name)
        unregistered = unregistered + 1; return name == 'Nexus'
    end}
check(I.Register() and I.Register() and registered == 1, 'v1 registration idempotent')
check(received == I.Provider and type(received.CollectDiagnosticSnapshot) == 'function',
    'optional snapshot method uses existing provider object')
check(I.Unregister() and unregistered == 1 and not I.IsRegistered(),
    'v1 unregister remains compatible')
_G.StutterAlert = {DIAGNOSTIC_PROVIDER_API=2,RegisterDiagnosticProvider=function() error('must not register') end}
check(not I.Register(), 'unsupported API remains safely unregistered')

-- Exercise the actual ordinary measurement hooks, rather than manual wrappers
-- alone. OFF has precisely the preexisting two millisecond reads per call;
-- ON adds one diagnostic span without executing a product callback twice.
local hooks = {'hud.prepare','lifecycle.update','sync.update','gameadapter.poll',
    'dps.update','lifecycle.phase.catalog'}
setup(false)
P.SetEnabled(true)
local bodies = 0
for _, name in ipairs(hooks) do
    values = pack(P.Measure(name, function(a)
        bodies = bodies + 1; ms, seconds = ms + 2, seconds + .002
        return a, nil, false, nil
    end, argument))
    check(values.n == 4 and values[1] == argument and values[3] == false,
        name..': ordinary OFF-hook callback arity retained')
    check(P.Stats(name).count == 1, name..': ordinary aggregate count retained')
end
check(bodies == #hooks and clockReads == #hooks * 2
    and memoryReads == 0 and sessionReads == 0,
    'diagnostic OFF adds no readers or callback executions to actual hooks')
check(#P.SnapshotDiagnostics().spans == 0, 'ordinary hooks do not implicitly arm diagnostics')
setup(true)
P.SetEnabled(true)
bodies = 0
for _, name in ipairs(hooks) do
    values = pack(P.Measure(name, function(a)
        bodies = bodies + 1; ms, seconds = ms + 2, seconds + .002
        return a, nil, false, nil
    end, argument))
    check(values.n == 4 and values[1] == argument and values[3] == false,
        name..': actual ON-hook callback arity retained')
    local ordinary = P.Stats(name)
    local diagnostic
    for _, item in ipairs(P.SnapshotDiagnostics().rows) do
        if item.name == name then diagnostic = item end
    end
    check(ordinary.count == 1 and ordinary.total == 2 and diagnostic.count == 1,
        name..': existing elapsed aggregate and one opt-in span coexist')
end
check(bodies == #hooks and #P.SnapshotDiagnostics().spans == #hooks,
    'actual hooks record once and call each product body once')
setup(true)
P.SetEnabled(true)
P.Measure('lifecycle.update', function()
    ms, seconds = 1, 10.001
    P.Measure('lifecycle.phase.catalog', function() ms, seconds = 6, 10.006 end)
    ms, seconds = 9, 10.009
end)
local legacy = P.RecentOperations(9.9, 10.1, 10.1)
local classifications = {}
for _, item in ipairs(legacy) do
    if item.name == 'lifecycle.update' then
        for _, field in ipairs(item.fields) do classifications[field.key] = field.value end
    end
end
check(classifications.mode == 'lifecycle.phase.catalog' and classifications.outcome == 5,
    'ordinary dominant-phase breadcrumb unchanged with diagnostics ON')

-- The real GameAdapter reconciliation entry retains same-frame generation and
-- saved semantics. This harness is synthetic, with no game or record mutation.
Nexus, NexusDB, WishlistRealizerDB = nil, nil, nil
local H = dofile('tests/prototype/harness.lua')
H.Boot()
local actualP, A = Nexus.Performance, Nexus.GameAdapter
actualP.SetClock(function() return H.now * 1000 end)
actualP.SetDiagnosticMemoryReader(function() return 500 end)
actualP.SetDiagnosticSessionClock(function() return H.now end)
actualP.ResetDiagnostics()
local beforeActions, beforeSends = #H.actions, #H.sent
local generation = A.EchoActiveSlotGeneration()
check(actualP.DiagnosticEnabled() == false and #actualP.SnapshotDiagnostics().spans == 0,
    'real adapter entry retains diagnostic default OFF')
local durable = H.Clone(NexusDB)
check(actualP.SetDiagnosticEnabled(true), 'real adapter diagnostics explicitly enabled')
local nextGeneration = A.EchoActiveSlotGeneration()
local againGeneration = A.EchoActiveSlotGeneration()
local echo
for _, item in ipairs(actualP.SnapshotDiagnostics().rows) do
    if item.name == 'echo.reconcile' then echo = item end
end
check(echo and echo.invocations >= 2, 'actual reconciliation entry is covered')
check(nextGeneration == generation and againGeneration == generation,
    'same-frame adapter generation unchanged by observation')
local F = dofile('tests/prototype/assignment_context_benchmark_support.lua')
check(F.Equal(durable, NexusDB) and #H.actions == beforeActions and #H.sent == beforeSends,
    'opt-in adapter observation preserves durable state and does not send/act')
print('stutter_diagnostic_integration: '..checks..' checks PASS (synthetic provider windows only)')
