-- Deterministic mechanics for opt-in stutter evidence, without game access.
-- Synthetic heap values are global net readings, never allocated bytes or GC time.
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
local function pack(...) return {n=select('#', ...), ...} end
_G.Nexus = {}
_G.GetTime = function() return 100 end
dofile('core/Performance.lua')
local P = Nexus.Performance
local ms, seconds, heap = 0, 100, 500
local clockReads, sessionReads, memoryReads = 0, 0, 0
local function clock() clockReads = clockReads + 1; return ms end
local function sessionClock() sessionReads = sessionReads + 1; return seconds end
local function memoryReader() memoryReads = memoryReads + 1; return heap end
local function row(s, name)
    for _, item in ipairs(s.rows) do if item.name == name then return item end end
end
local function span(s, name)
    for _, item in ipairs(s.spans) do if item.name == name then return item end end
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
local function setup()
    check(P.SetDiagnosticEnabled(false), 'disable outside active span')
    check(P.SetDiagnosticMemoryReader(memoryReader), 'inject memory reader')
    check(P.SetDiagnosticSessionClock(sessionClock), 'inject independent seconds clock')
    P.SetClock(clock)
    check(P.ResetDiagnostics(), 'reset outside active span')
    check(P.SetDiagnosticEnabled(true), 'enable explicitly')
    ms, seconds, heap = 0, 100, 500
    clockReads, sessionReads, memoryReads = 0, 0, 0
end

-- The default bypass retains arguments, values and product error identity, and
-- incurs no diagnostic clock/heap readings, even with ordinary timing enabled.
check(P.DiagnosticEnabled() == false, 'diagnostics default off')
P.SetClock(clock)
check(P.SetDiagnosticMemoryReader(memoryReader), 'configure disabled memory reader')
check(P.SetDiagnosticSessionClock(sessionClock), 'configure disabled session clock')
local argument = {}
local values = pack(P.MeasureDiagnostic('orb.read', function(a, b)
    check(a == argument and b == 9, 'callback argument identity')
    return argument, nil, false, nil
end, argument, 9))
check(values.n == 4 and values[1] == argument and values[2] == nil
    and values[3] == false and values[4] == nil, 'trailing nil returns preserved')
local failure = {}
local ok, err = pcall(function()
    P.MeasureDiagnostic('orb.read', function() error(failure) end)
end)
check(not ok and err == failure, 'disabled error object preserved')
local s = P.SnapshotDiagnostics()
check(clockReads == 0 and sessionReads == 0 and memoryReads == 0,
    'default-off reads no timing or memory source')
check(s.activeDepth == 0 and #s.spans == 0 and row(s, 'orb.read').invocations == 0,
    'default-off records no invented measurements')
check(#s.rows == 10 and s.capacity == 32 and s.maximumDepth == 16,
    'fixed diagnostic labels and limits')
check(s.units == 'ms' and s.heapUnits == 'KB' and type(s.heapMeaning) == 'string'
    and type(s.residualMeaning) == 'string', 'export declares elapsed and heap semantics')

-- Millisecond duration and independent session geometry are observed at the
-- actual boundaries. Only direct child elapsed is subtracted from each parent.
setup()
P.MeasureDiagnostic('lifecycle.update', function()
    ms, seconds, heap = 1, 100.001, 501
    P.MeasureDiagnostic('orb.read', function()
        ms, seconds, heap = 3, 100.003, 505
        P.MeasureDiagnostic('echo.reconcile', function()
            ms, seconds, heap = 5, 100.005, 502
        end)
        ms, seconds, heap = 7, 100.007, 506
    end)
    ms, seconds, heap = 10, 100.010, 490
end)
s = P.SnapshotDiagnostics()
local root, child, leaf = span(s, 'lifecycle.update'), span(s, 'orb.read'), span(s, 'echo.reconcile')
check(root.elapsedAvailable and root.elapsedMs == 10 and root.residualAvailable
    and root.residualMs == 4, 'root subtracts its six-ms direct child once')
check(child.elapsedMs == 6 and child.residualMs == 4 and leaf.elapsedMs == 2,
    'nested residual belongs to the same invocation')
check(root.depth == 1 and child.depth == 2 and leaf.depth == 3
    and child.parentId == root.id and leaf.parentId == child.id,
    'actual parent identity and depth retained')
check(root.sessionWindowAvailable and root.sessionStart == 100 and root.sessionEnd == 100.010,
    'session span uses independent boundary readings')
check(root.heapAvailable and root.heapBeforeKB == 500 and root.heapAfterKB == 490
    and root.heapNetKB == -10, 'negative global heap net retained without clamping')
check(row(s, 'lifecycle.update').count == 1 and row(s, 'lifecycle.update').totalMs == 10
    and row(s, 'lifecycle.update').residualTotalMs == 4,
    'aggregate retains inclusive elapsed and separate residual')
check(row(s, 'lifecycle.update').heapCount == 1
    and row(s, 'lifecycle.update').heapNetKB == -10, 'global net aggregate carries sign')
check(clockReads == 6 and sessionReads == 6 and memoryReads == 6,
    'one reading per boundary per successful span')

-- Snapshots are detached and perform no new reads. A private/dynamic label is
-- bypassed without retained payload or an accidentally unbounded label row.
local beforeClock, beforeSession, beforeMemory = clockReads, sessionReads, memoryReads
s.spans[1].name = 'private character'; s.rows[1].totalMs = 999
local fresh = P.SnapshotDiagnostics()
check(span(fresh, 'lifecycle.update') ~= nil and row(fresh, 'orb.status').totalMs ~= 999,
    'snapshot tables are detached')
check(clockReads == beforeClock and sessionReads == beforeSession and memoryReads == beforeMemory,
    'snapshot has no observer reads')
P.MeasureDiagnostic('private character/payload', function() return 'secret' end)
fresh = P.SnapshotDiagnostics()
check(fresh.rejectedLabels == 1 and #fresh.rows == 10 and #fresh.spans == 3,
    'dynamic label is rejected without retention')
check(not contains(fresh, 'private character/payload') and not contains(fresh, 'secret'),
    'callback values and rejected private labels are not retained anywhere')
check(clockReads == beforeClock and sessionReads == beforeSession and memoryReads == beforeMemory,
    'rejected label bypasses clock and memory')

-- Opt-in diagnostics remain an explicit, independent observation flag; turning
-- ordinary aggregates off must not silently arm it or suppress an explicit ON.
setup()
P.SetEnabled(false)
P.MeasureDiagnostic('orb.status', function() ms, seconds = 3, 100.003 end)
check(row(P.SnapshotDiagnostics(), 'orb.status').count == 1,
    'explicit diagnostic ON independent of ordinary aggregate OFF')
P.SetDiagnosticEnabled(false)
P.SetEnabled(true)
local oldReads = clockReads
P.MeasureDiagnostic('orb.status', function() ms = 10 end)
check(clockReads == oldReads, 'ordinary aggregate ON does not arm diagnostics')

-- Failed callbacks retain product error objects, unwind all frames, and do not
-- invent completed samples. A caught child failure invalidates parent residual.
setup()
ok, err = pcall(function()
    P.MeasureDiagnostic('orb.panel', function()
        ms, seconds = 1, 100.001
        P.MeasureDiagnostic('orb.read', function() error(failure) end)
    end)
end)
s = P.SnapshotDiagnostics()
check(not ok and err == failure and s.activeDepth == 0, 'nested errors unwind unchanged')
check(row(s, 'orb.panel').failed == 1 and row(s, 'orb.read').failed == 1,
    'failure counted for each failed invocation')
check(row(s, 'orb.panel').count == 0 and not span(s, 'orb.panel').succeeded,
    'failed product call is not a completed elapsed sample')
P.MeasureDiagnostic('lifecycle.update', function()
    pcall(function() P.MeasureDiagnostic('orb.read', function() error(failure) end) end)
    ms, seconds = 10, 100.010
end)
s = P.SnapshotDiagnostics()
check(span(s, 'lifecycle.update').succeeded and not span(s, 'lifecycle.update').residualAvailable,
    'caught failed child withholds parent residual')
check(s.activeDepth == 0, 'caught-child path leaves no active context')

-- Frozen/failed seconds do not manufacture geometry from elapsed milliseconds.
setup()
P.MeasureDiagnostic('orb.status', function() ms = 7 end)
s = P.SnapshotDiagnostics()
check(span(s, 'orb.status').elapsedMs == 7 and not span(s, 'orb.status').sessionWindowAvailable
    and span(s, 'orb.status').sessionWindowReason == 'frozen_or_zero_window',
    'nonzero elapsed with frozen session clock explicitly unmatched')
setup()
P.SetDiagnosticSessionClock(function() error('seconds unavailable') end)
P.MeasureDiagnostic('orb.read', function() ms = 4 end)
s = P.SnapshotDiagnostics()
check(span(s, 'orb.read').elapsedAvailable and not span(s, 'orb.read').sessionWindowAvailable,
    'seconds failure does not invalidate available elapsed nor invent a window')
check(s.sessionClockFailures >= 1, 'session-reader failure is observable')

-- Heap failures and nonfinite values remain unknown, rather than measured zero;
-- a changed/failed elapsed clock likewise leaves callback completion intact.
setup()
P.SetDiagnosticMemoryReader(function() return 0/0 end)
P.MeasureDiagnostic('orb.read', function() ms, seconds = 3, 100.003 end)
s = P.SnapshotDiagnostics()
check(not span(s, 'orb.read').heapAvailable and span(s, 'orb.read').heapNetKB == nil,
    'nonfinite heap is unknown')
check(row(s, 'orb.read').heapCount == 0 and not row(s, 'orb.read').heapAvailable,
    'unknown heap not aggregated as zero')
setup()
P.SetClock(function() error('millisecond reader unavailable') end)
values = pack(P.MeasureDiagnostic('orb.read', function() return argument, nil end))
s = P.SnapshotDiagnostics()
check(values.n == 2 and values[1] == argument and not span(s, 'orb.read').elapsedAvailable,
    'failed elapsed reader keeps callback semantics with unknown elapsed')
check(row(s, 'orb.read').count == 0 and not row(s, 'orb.read').available,
    'failed elapsed reader not counted as measured zero')
setup()
P.MeasureDiagnostic('orb.read', function()
    P.SetClock(function() return 99 end)
    seconds = 100.004
end)
check(not span(P.SnapshotDiagnostics(), 'orb.read').elapsedAvailable,
    'clock generation change invalidates a cross-clock span')

-- Active configuration changes must be rejected, and depth overflow must not
-- leave a complete residual for the retained frame whose direct child bypassed.
setup()
local mutationsRejected = false
local function recurse(depth)
    P.MeasureDiagnostic('orb.read', function()
        if depth == 1 then
            mutationsRejected = not P.ResetDiagnostics() and not P.SetDiagnosticEnabled(false)
                and not P.SetDiagnosticSessionClock(sessionClock)
                and not P.SetDiagnosticMemoryReader(memoryReader)
        end
        if depth < 20 then recurse(depth + 1) end
        ms, seconds = ms + 1, seconds + .001
    end)
end
recurse(1)
s = P.SnapshotDiagnostics()
check(mutationsRejected and s.enabled and s.activeDepth == 0, 'active configuration preserved')
check(s.depthBypasses >= 1 and #s.spans == 16, 'depth bounded with explicit bypass count')
local overflowParent
for _, item in ipairs(s.spans) do if item.depth == 16 then overflowParent = item end end
check(overflowParent and not overflowParent.residualAvailable,
    'overflow invalidates its parent direct-child residual coverage')

-- Capacity remains fixed even under repeated zero/short spans; sequence IDs
-- advance independently of bounded retention and reset starts a new generation.
setup()
for index = 1, 90 do
    P.MeasureDiagnostic('orb.status', function()
        ms, seconds = ms + 1, seconds + .001
    end)
end
s = P.SnapshotDiagnostics()
check(#s.spans == 32 and row(s, 'orb.status').invocations == 90,
    'ring bounded while aggregate records all fixed-label invocations')
check(s.lastSpanId >= 90, 'retention does not reuse retained IDs')
local generation = s.resetGeneration
P.ResetDiagnostics()
s = P.SnapshotDiagnostics()
check(#s.spans == 0 and s.resetGeneration > generation and row(s, 'orb.status').invocations == 0,
    'reset clears bounded evidence with distinct generation')

-- Observer readers can re-enter instrumented APIs. Such callbacks still run,
-- but are observer work and must not recursively create product span records.
-- The <=6 guard makes the previous recursion finite and fail-capable offline.
local function setReader(kind, reader)
    if kind == 'elapsed' then P.SetClock(reader)
    elseif kind == 'session' then P.SetDiagnosticSessionClock(reader)
    else P.SetDiagnosticMemoryReader(reader) end
end
local function readerValue(kind)
    if kind == 'elapsed' then return ms end
    if kind == 'session' then return seconds end
    return heap
end
local function measurementAvailable(item, kind)
    if kind == 'elapsed' then return item.elapsedAvailable end
    if kind == 'session' then return item.sessionWindowAvailable end
    return item.heapAvailable
end
for _, kind in ipairs({'memory', 'elapsed', 'session'}) do
    setup()
    local readerCalls, observerCalls, productCalls = 0, 0, 0
    setReader(kind, function()
        readerCalls = readerCalls + 1
        if readerCalls <= 6 then
            P.MeasureDiagnostic('orb.status', function() observerCalls = observerCalls + 1 end)
        end
        return readerValue(kind)
    end)
    values = pack(P.MeasureDiagnostic('orb.read', function()
        productCalls = productCalls + 1
        ms, seconds = 4, 100.004
        return argument, nil
    end))
    s = P.SnapshotDiagnostics()
    check(readerCalls == 2 and observerCalls == 2,
        kind..': one observer reading at each boundary, without recursive sampling')
    check(productCalls == 1 and values.n == 2 and values[1] == argument and values[2] == nil,
        kind..': observer entry preserves one product call and trailing nil result')
    check(#s.spans == 1 and s.lastSpanId == 1 and s.spans[1].name == 'orb.read'
        and s.activeDepth == 0 and row(s, 'orb.status').invocations == 0,
        kind..': only product span and ID are recorded')
    check(measurementAvailable(s.spans[1], kind), kind..': successful reentrant reader value retained')
    P.MeasureDiagnostic('orb.read', function()
        productCalls = productCalls + 1
        ms, seconds = 8, 100.008
    end)
    s = P.SnapshotDiagnostics()
    check(#s.spans == 2 and s.lastSpanId == 2 and productCalls == 2
        and readerCalls == 4 and observerCalls == 4,
        kind..': success restores observer suppression before later product entry')
end

-- Nil/throwing readers both leave a bounded unknown measurement and restore
-- suppression. A later product call must still get its own ID/span while the
-- failed reader stays unavailable, and explicit reader replacement recovers it.
local readerFailure = {}
for _, kind in ipairs({'memory', 'elapsed', 'session'}) do
    for _, mode in ipairs({'nil', 'throw'}) do
        setup()
        local readerCalls, observerCalls, productCalls = 0, 0, 0
        setReader(kind, function()
            readerCalls = readerCalls + 1
            P.MeasureDiagnostic('orb.status', function() observerCalls = observerCalls + 1 end)
            if mode == 'throw' then error(readerFailure) end
            return nil
        end)
        values = pack(P.MeasureDiagnostic('orb.read', function()
            productCalls = productCalls + 1
            ms, seconds = 3, 100.003
            return argument, nil
        end))
        s = P.SnapshotDiagnostics()
        check(readerCalls == 1 and observerCalls == 1 and #s.spans == 1
            and s.lastSpanId == 1 and s.activeDepth == 0,
            kind..' '..mode..': failed observer sampled once without nested spans')
        check(productCalls == 1 and values.n == 2 and values[1] == argument,
            kind..' '..mode..': reader failure does not change product results')
        check(not measurementAvailable(s.spans[1], kind),
            kind..' '..mode..': unavailable observation is not a measured zero')
        P.MeasureDiagnostic('orb.read', function() productCalls = productCalls + 1 end)
        s = P.SnapshotDiagnostics()
        check(productCalls == 2 and #s.spans == 2 and s.lastSpanId == 2
            and readerCalls == 1 and row(s, 'orb.status').invocations == 0,
            kind..' '..mode..': failure restores suppression for later product entry')
        setReader(kind, function() return readerValue(kind) end)
        P.MeasureDiagnostic('orb.read', function()
            productCalls = productCalls + 1
            ms, seconds = 4, 100.004
        end)
        s = P.SnapshotDiagnostics()
        check(#s.spans == 3 and s.lastSpanId == 3
            and measurementAvailable(s.spans[3], kind),
            kind..' '..mode..': explicit reader replacement recovers observation')
    end
end

-- If the reader's reentrant callback itself errors, only the existing reader
-- pcall handles that error. Its measurement becomes unknown; product behavior
-- is neither retried nor replaced, including an independent product exception.
for _, kind in ipairs({'memory', 'elapsed', 'session'}) do
    setup()
    local readerCalls, observerCalls, productCalls = 0, 0, 0
    setReader(kind, function()
        readerCalls = readerCalls + 1
        P.MeasureDiagnostic('orb.status', function()
            observerCalls = observerCalls + 1
            error(readerFailure)
        end)
        return readerValue(kind)
    end)
    values = pack(P.MeasureDiagnostic('orb.read', function()
        productCalls = productCalls + 1
        ms, seconds = 3, 100.003
        return argument, nil
    end))
    s = P.SnapshotDiagnostics()
    check(readerCalls == 1 and observerCalls == 1 and productCalls == 1
        and values.n == 2 and values[1] == argument,
        kind..': reentrant observer error isolated from product call')
    check(#s.spans == 1 and s.lastSpanId == 1 and s.activeDepth == 0
        and not measurementAvailable(s.spans[1], kind),
        kind..': reentrant callback error remains unknown observer evidence')
    local productFailure = {}
    ok, err = pcall(function()
        P.MeasureDiagnostic('orb.read', function() error(productFailure) end)
    end)
    s = P.SnapshotDiagnostics()
    check(not ok and err == productFailure and #s.spans == 2 and s.lastSpanId == 2
        and not s.spans[2].succeeded and s.activeDepth == 0,
        kind..': independent product error still propagates unchanged')
    P.MeasureDiagnostic('orb.read', function() productCalls = productCalls + 1 end)
    check(#P.SnapshotDiagnostics().spans == 3 and productCalls == 2,
        kind..': reader/product failures leave future product sampling enabled')
end
print('stutter_diagnostic_spans: '..checks..' checks PASS (synthetic clocks/global heap only)')
